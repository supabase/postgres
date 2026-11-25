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

func testPolicy() *Policy {
	return &Policy{
		Roots:     []string{"/etc", "/opt"},
		FileModes: []string{"0644", "0600"},
		DirModes:  []string{"0755"},
		Setuid:    []string{"/usr/bin/allowed"},
		Exceptions: []Exception{
			{Path: "/etc/loose.conf"},
			{Path: "/opt/vendor/**"},
		},
	}
}

func details(findings []Finding) string {
	var parts []string
	for _, f := range findings {
		parts = append(parts, f.String())
	}
	return strings.Join(parts, "\n")
}

func TestCheck(t *testing.T) {
	known := map[uint32]bool{0: true}
	tests := []struct {
		name  string
		entry entry
		want  []string
	}{
		{"clean file", entry{path: "/etc/a", mode: 0o644}, nil},
		{"setuid not listed", entry{path: "/usr/bin/x", mode: 0o755 | fs.ModeSetuid}, []string{"setuid or setgid file 4755"}},
		{"setgid not listed", entry{path: "/usr/bin/x", mode: 0o755 | fs.ModeSetgid}, []string{"setuid or setgid file 2755"}},
		{"setuid listed", entry{path: "/usr/bin/allowed", mode: 0o755 | fs.ModeSetuid}, nil},
		{"world-writable file", entry{path: "/srv/x", mode: 0o666}, []string{"world-writable 0666", "group-writable 0666"}},
		{"sticky world-writable dir", entry{path: "/srv/t", mode: 0o777 | fs.ModeSticky, isDir: true}, nil},
		{"world-writable dir", entry{path: "/srv/t", mode: 0o777, isDir: true}, []string{"world-writable 0777", "group-writable 0777"}},
		{"group-writable file", entry{path: "/srv/x", mode: 0o664}, []string{"group-writable 0664"}},
		{"group-writable excepted", entry{path: "/etc/loose.conf", mode: 0o664}, nil},
		{"subtree excepted", entry{path: "/opt/vendor/deep/bin", mode: 0o775}, nil},
		{"subtree root excepted", entry{path: "/opt/vendor", mode: 0o775, isDir: true}, nil},
		{"sibling of subtree", entry{path: "/opt/vendor2/bin", mode: 0o755}, []string{"mode 0755 not in allowlist"}},
		{"orphan uid", entry{path: "/srv/x", mode: 0o644, uid: 42}, []string{"owner id 42 has no passwd entry"}},
		{"orphan gid", entry{path: "/srv/x", mode: 0o644, gid: 43}, []string{"group id 43 has no group entry"}},
		{"mode outside allowlist", entry{path: "/etc/x", mode: 0o640}, []string{"mode 0640 not in allowlist"}},
		{"mode outside roots", entry{path: "/srv/x", mode: 0o640}, nil},
		{"dir mode outside allowlist", entry{path: "/etc/d", mode: 0o700, isDir: true}, []string{"mode 0700 not in allowlist"}},
		{"dir mode allowed", entry{path: "/etc/d", mode: 0o755, isDir: true}, nil},
	}
	p := testPolicy()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := p.check(tt.entry, known, known)
			if len(got) != len(tt.want) {
				t.Fatalf("got %d findings, want %d:\n%s", len(got), len(tt.want), details(got))
			}
			for i, w := range tt.want {
				if !strings.Contains(got[i].Detail, w) {
					t.Errorf("finding %d = %q, want it to contain %q", i, got[i].Detail, w)
				}
			}
		})
	}
}

func TestLoadPolicy(t *testing.T) {
	dir := t.TempDir()
	good := filepath.Join(dir, "good.yml")
	os.WriteFile(good, []byte("roots: [/etc]\nfile_modes: ['0644']\ndir_modes: ['0755']\nsetuid: [/usr/bin/su]\nexceptions:\n  - path: /etc/x\n    reason: test\n"), 0o644)
	p, err := LoadPolicy(good)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Exceptions) != 1 || p.Exceptions[0].Reason != "test" || p.Setuid[0] != "/usr/bin/su" {
		t.Errorf("unexpected policy: %+v", p)
	}

	bad := filepath.Join(dir, "bad.yml")
	os.WriteFile(bad, []byte("file_modes: ['rw-r--r--']\n"), 0o644)
	if _, err := LoadPolicy(bad); err == nil {
		t.Error("expected error for invalid mode")
	}
	if _, err := LoadPolicy(filepath.Join(dir, "missing.yml")); err == nil {
		t.Error("expected error for missing file")
	}
}

func TestLoadPolicyInclude(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(filepath.Join(dir, "build"), 0o755)
	os.WriteFile(filepath.Join(dir, "common.yml"), []byte("roots: [/etc]\nfile_modes: ['0644']\nsetuid: [/usr/bin/su]\nexceptions:\n  - path: /etc/a\n"), 0o644)
	child := filepath.Join(dir, "build", "policy.yml")
	os.WriteFile(child, []byte("include: [../common.yml]\nsetuid: [/usr/bin/sudo]\nexceptions:\n  - path: /etc/b\n"), 0o644)
	p, err := LoadPolicy(child)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Roots) != 1 || len(p.FileModes) != 1 || len(p.Setuid) != 2 || len(p.Exceptions) != 2 {
		t.Errorf("unexpected merge: %+v", p)
	}
	if !p.excepted("/etc/a") || !p.excepted("/etc/b") || !p.isSetuidAllowed("/usr/bin/sudo") {
		t.Errorf("merged policy missing entries: %+v", p)
	}
}

func TestLoadPolicyIncludeCycle(t *testing.T) {
	dir := t.TempDir()
	a, b := filepath.Join(dir, "a.yml"), filepath.Join(dir, "b.yml")
	os.WriteFile(a, []byte("include: [b.yml]\n"), 0o644)
	os.WriteFile(b, []byte("include: [a.yml]\n"), 0o644)
	if _, err := LoadPolicy(a); err == nil || !strings.Contains(err.Error(), "cycle") {
		t.Errorf("expected include cycle error, got %v", err)
	}
}

func ownerOf(t *testing.T, path string) (int, int) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	st := info.Sys().(*syscall.Stat_t)
	return int(st.Uid), int(st.Gid)
}

func writeIDs(t *testing.T, root string, uid, gid int) {
	t.Helper()
	etc := filepath.Join(root, "etc")
	if err := os.MkdirAll(etc, 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(etc, "passwd"), []byte(fmt.Sprintf("me:x:%d:%d:::\n", uid, gid)), 0o644)
	os.WriteFile(filepath.Join(etc, "group"), []byte(fmt.Sprintf("me:x:%d:\n", gid)), 0o644)
}

func TestScan(t *testing.T) {
	root := t.TempDir()
	uid, gid := ownerOf(t, root)
	writeIDs(t, root, uid, gid)
	for path, mode := range map[string]fs.FileMode{
		"etc/ok.conf":        0o644,
		"etc/loose.conf":     0o664,
		"etc/bad.conf":       0o664,
		"srv/suid":           0o755 | fs.ModeSetuid,
		"srv/world":          0o666,
		"tmp/ignored":        0o666,
		"nix/store/ignored":  0o666,
		"usr/bin/allowed":    0o755 | fs.ModeSetuid,
		"usr/bin/not-listed": 0o755 | fs.ModeSetuid,
	} {
		full := filepath.Join(root, path)
		os.MkdirAll(filepath.Dir(full), 0o755)
		if err := os.WriteFile(full, []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chmod(full, mode); err != nil {
			t.Fatal(err)
		}
	}
	os.Symlink("/etc/ok.conf", filepath.Join(root, "srv/link"))

	p := testPolicy()
	p.Roots = []string{"/etc"}
	res, err := Scan(context.Background(), root, p)
	if err != nil {
		t.Fatal(err)
	}
	got := details(res.Findings)
	for _, want := range []string{
		"/etc/bad.conf: group-writable 0664",
		"/etc/bad.conf: mode 0664 not in allowlist",
		"/srv/suid: setuid or setgid file 4755",
		"/srv/world: world-writable 0666",
		"/usr/bin/not-listed: setuid or setgid file 4755",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing finding %q in:\n%s", want, got)
		}
	}
	for _, unwanted := range []string{"/etc/ok.conf", "/etc/loose.conf", "/tmp/", "/nix/store", "/usr/bin/allowed", "srv/link"} {
		if strings.Contains(got, unwanted) {
			t.Errorf("unexpected finding for %q in:\n%s", unwanted, got)
		}
	}
	if res.Scanned == 0 {
		t.Error("expected scanned entries")
	}
}

func TestScanOrphanIDs(t *testing.T) {
	root := t.TempDir()
	uid, gid := ownerOf(t, root)
	writeIDs(t, root, uid+1000, gid+1000)
	os.WriteFile(filepath.Join(root, "file"), []byte("x"), 0o644)
	res, err := Scan(context.Background(), root, &Policy{})
	if err != nil {
		t.Fatal(err)
	}
	got := details(res.Findings)
	if !strings.Contains(got, "/file: owner id") || !strings.Contains(got, "/file: group id") {
		t.Errorf("expected orphan id findings, got:\n%s", got)
	}
}

func TestScanMissingPasswd(t *testing.T) {
	if _, err := Scan(context.Background(), t.TempDir(), &Policy{}); err == nil {
		t.Error("expected error without etc/passwd")
	}
}
