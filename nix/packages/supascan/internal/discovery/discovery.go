package discovery

import (
	"bufio"
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"

	"gopkg.in/yaml.v3"
)

var skippedTrees = []string{"/proc", "/sys", "/dev", "/run", "/tmp", "/var/tmp", "/nix/store"}

type Policy struct {
	Roots      []string `yaml:"roots"`
	FileModes  []string `yaml:"file_modes"`
	DirModes   []string `yaml:"dir_modes"`
	Setuid     []string `yaml:"setuid"`
	Exceptions []string `yaml:"exceptions"`
}

func LoadPolicy(path string) (*Policy, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var p Policy
	if err := yaml.Unmarshal(data, &p); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return &p, nil
}

func under(path, tree string) bool {
	return path == tree || strings.HasPrefix(path, strings.TrimRight(tree, "/")+"/")
}

func (p *Policy) excepted(path string) bool {
	for _, e := range p.Exceptions {
		if base, ok := strings.CutSuffix(e, "/**"); ok {
			if under(path, base) {
				return true
			}
		} else if path == e {
			return true
		}
	}
	return false
}

func allowed(modes []string, perm fs.FileMode) bool {
	return slices.ContainsFunc(modes, func(m string) bool {
		n, err := strconv.ParseUint(m, 8, 32)
		return err == nil && fs.FileMode(n) == perm
	})
}

func readIDs(path string) (map[uint32]bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	ids := map[uint32]bool{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if fields := strings.Split(sc.Text(), ":"); len(fields) >= 3 {
			if n, err := strconv.ParseUint(fields[2], 10, 32); err == nil {
				ids[uint32(n)] = true
			}
		}
	}
	return ids, sc.Err()
}

// Scan walks root and returns "path: problem" lines. Paths are relative to
// root with a leading slash, so an extracted image can be scanned in place.
func Scan(ctx context.Context, root string, p *Policy) ([]string, error) {
	users, err := readIDs(filepath.Join(root, "etc/passwd"))
	if err != nil {
		return nil, err
	}
	groups, err := readIDs(filepath.Join(root, "etc/group"))
	if err != nil {
		return nil, err
	}

	var findings []string
	err = filepath.WalkDir(root, func(real string, d fs.DirEntry, walkErr error) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		path := "/"
		if rel, _ := filepath.Rel(root, real); rel != "." {
			path = "/" + filepath.ToSlash(rel)
		}
		if slices.ContainsFunc(skippedTrees, func(t string) bool { return under(path, t) }) {
			if d != nil && d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if walkErr != nil || (!d.IsDir() && !d.Type().IsRegular()) || p.excepted(path) {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		st := info.Sys().(*syscall.Stat_t)
		for _, problem := range p.check(path, info.Mode(), d.IsDir(), st.Uid, st.Gid, users, groups) {
			findings = append(findings, path+": "+problem)
		}
		return nil
	})
	return findings, err
}

func (p *Policy) check(path string, mode fs.FileMode, isDir bool, uid, gid uint32, users, groups map[uint32]bool) []string {
	var out []string
	perm := mode.Perm()
	sticky := isDir && mode&fs.ModeSticky != 0
	if !isDir && mode&(fs.ModeSetuid|fs.ModeSetgid) != 0 && !slices.Contains(p.Setuid, path) {
		out = append(out, "setuid or setgid file not in setuid list")
	}
	if perm&0o002 != 0 && !sticky {
		out = append(out, fmt.Sprintf("world-writable %04o", perm))
	}
	if perm&0o020 != 0 && !sticky {
		out = append(out, fmt.Sprintf("group-writable %04o", perm))
	}
	if !users[uid] {
		out = append(out, fmt.Sprintf("owner id %d has no passwd entry", uid))
	}
	if !groups[gid] {
		out = append(out, fmt.Sprintf("group id %d has no group entry", gid))
	}
	if slices.ContainsFunc(p.Roots, func(r string) bool { return under(path, r) }) {
		modes := p.FileModes
		if isDir {
			modes = p.DirModes
		}
		if !allowed(modes, perm) {
			out = append(out, fmt.Sprintf("mode %04o not in allowlist", perm))
		}
	}
	return out
}
