package discovery

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestCheck(t *testing.T) {
	p := &Policy{
		Roots:     []string{"/etc"},
		FileModes: []string{"0644"},
		DirModes:  []string{"0755"},
		Setuid:    []string{"/usr/bin/allowed"},
	}
	known := map[uint32]bool{0: true}
	tests := []struct {
		name  string
		path  string
		mode  fs.FileMode
		isDir bool
		uid   uint32
		want  string
	}{
		{"clean", "/etc/a", 0o644, false, 0, ""},
		{"setuid not listed", "/usr/bin/x", 0o755 | fs.ModeSetuid, false, 0, "setuid"},
		{"setgid not listed", "/usr/bin/x", 0o755 | fs.ModeSetgid, false, 0, "setuid"},
		{"setuid listed", "/usr/bin/allowed", 0o755 | fs.ModeSetuid, false, 0, ""},
		{"world-writable", "/srv/x", 0o646, false, 0, "world-writable"},
		{"sticky dir", "/srv/t", 0o777 | fs.ModeSticky, true, 0, ""},
		{"group-writable", "/srv/x", 0o664, false, 0, "group-writable"},
		{"orphan uid", "/srv/x", 0o644, false, 42, "owner id 42"},
		{"mode outside allowlist", "/etc/x", 0o640, false, 0, "not in allowlist"},
		{"mode outside roots", "/srv/x", 0o640, false, 0, ""},
		{"dir mode", "/etc/d", 0o700, true, 0, "not in allowlist"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := strings.Join(p.check(tt.path, tt.mode, tt.isDir, tt.uid, 0, known, known), ";")
			if tt.want == "" && got != "" || !strings.Contains(got, tt.want) {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}

func TestExcepted(t *testing.T) {
	p := &Policy{Exceptions: map[string][]string{"/etc/a": {"mode"}, "/opt/v/**": {"mode", "group-writable"}}}
	for _, tt := range []struct {
		path, rule string
		want       bool
	}{
		{"/etc/a", "mode", true},
		{"/etc/a", "group-writable", false},
		{"/etc/ab", "mode", false},
		{"/opt/v", "group-writable", true},
		{"/opt/v/x/y", "mode", true},
		{"/opt/v/x", "setuid", false},
		{"/opt/vx", "mode", false},
	} {
		if got := p.excepted(tt.path, tt.rule); got != tt.want {
			t.Errorf("excepted(%q, %q) = %v, want %v", tt.path, tt.rule, got, tt.want)
		}
	}
}

func TestLoadPolicyRejectsUnknownRule(t *testing.T) {
	path := filepath.Join(t.TempDir(), "p.yml")
	os.WriteFile(path, []byte("exceptions:\n  /etc/a: [modee]\n"), 0o644)
	if _, err := LoadPolicy(path); err == nil {
		t.Error("expected error for unknown rule")
	}
}

func TestScan(t *testing.T) {
	root := t.TempDir()
	info, _ := os.Stat(root)
	st := info.Sys().(*syscall.Stat_t)
	etc := filepath.Join(root, "etc")
	os.MkdirAll(etc, 0o755)
	writeID := func(name string, id uint32) {
		line := fmt.Sprintf("me:x:%d:\n", id)
		os.WriteFile(filepath.Join(etc, name), []byte(line), 0o644)
	}
	writeID("passwd", st.Uid)
	writeID("group", st.Gid)
	for name, mode := range map[string]fs.FileMode{"etc/loose": 0o664, "etc/skip": 0o664, "srv/suid": 0o755 | fs.ModeSetuid, "tmp/ignored": 0o666} {
		full := filepath.Join(root, name)
		os.MkdirAll(filepath.Dir(full), 0o755)
		os.WriteFile(full, nil, 0o600)
		os.Chmod(full, mode)
	}

	got, err := Scan(context.Background(), root, &Policy{Exceptions: map[string][]string{"/etc/skip": {"group-writable"}}})
	if err != nil {
		t.Fatal(err)
	}
	text := strings.Join(got, "\n")
	for _, want := range []string{"/etc/loose: group-writable", "/srv/suid: setuid"} {
		if !strings.Contains(text, want) {
			t.Errorf("missing %q in:\n%s", want, text)
		}
	}
	for _, unwanted := range []string{"/etc/skip", "/tmp"} {
		if strings.Contains(text, unwanted) {
			t.Errorf("unexpected %q in:\n%s", unwanted, text)
		}
	}
}
