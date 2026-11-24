package discovery

import (
	"bufio"
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"

	"gopkg.in/yaml.v3"
)

var skippedTrees = []string{
	"/proc",
	"/sys",
	"/dev",
	"/run",
	"/tmp",
	"/var/tmp",
	"/nix/store",
}

type Exception struct {
	Path   string `yaml:"path"`
	Reason string `yaml:"reason,omitempty"`
}

type Policy struct {
	Roots      []string    `yaml:"roots"`
	FileModes  []string    `yaml:"file_modes"`
	DirModes   []string    `yaml:"dir_modes"`
	Setuid     []string    `yaml:"setuid"`
	Exceptions []Exception `yaml:"exceptions"`
}

type Finding struct {
	Path   string
	Detail string
}

func (f Finding) String() string {
	return f.Path + ": " + f.Detail
}

type Result struct {
	Findings []Finding
	Scanned  int
	Errors   []string
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
	for _, m := range append(append([]string{}, p.FileModes...), p.DirModes...) {
		if _, err := strconv.ParseUint(m, 8, 32); err != nil {
			return nil, fmt.Errorf("invalid mode %q in %s", m, path)
		}
	}
	return &p, nil
}

type entry struct {
	path  string
	mode  fs.FileMode
	isDir bool
	uid   uint32
	gid   uint32
}

func under(path, tree string) bool {
	return path == tree || strings.HasPrefix(path, strings.TrimRight(tree, "/")+"/")
}

func (p *Policy) excepted(path string) bool {
	for _, e := range p.Exceptions {
		if base, ok := strings.CutSuffix(e.Path, "/**"); ok {
			if under(path, base) {
				return true
			}
		} else if path == e.Path {
			return true
		}
	}
	return false
}

func modeSet(values []string) map[fs.FileMode]bool {
	set := make(map[fs.FileMode]bool, len(values))
	for _, v := range values {
		n, _ := strconv.ParseUint(v, 8, 32)
		set[fs.FileMode(n)] = true
	}
	return set
}

func parseIDs(path string) (map[uint32]bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	ids := make(map[uint32]bool)
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Split(sc.Text(), ":")
		if len(fields) < 3 {
			continue
		}
		if n, err := strconv.ParseUint(fields[2], 10, 32); err == nil {
			ids[uint32(n)] = true
		}
	}
	return ids, sc.Err()
}

// Scan walks root and reports entries that break the policy. Paths in the
// result are relative to root with a leading slash, so a mounted image can
// be scanned in place.
func Scan(ctx context.Context, root string, p *Policy) (*Result, error) {
	root = filepath.Clean(root)
	users, err := parseIDs(filepath.Join(root, "etc/passwd"))
	if err != nil {
		return nil, fmt.Errorf("read passwd: %w", err)
	}
	groups, err := parseIDs(filepath.Join(root, "etc/group"))
	if err != nil {
		return nil, fmt.Errorf("read group: %w", err)
	}

	res := &Result{}
	toPath := func(real string) string {
		rel, err := filepath.Rel(root, real)
		if err != nil || rel == "." {
			return "/"
		}
		return "/" + filepath.ToSlash(rel)
	}

	err = filepath.WalkDir(root, func(real string, d fs.DirEntry, walkErr error) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		path := toPath(real)
		for _, t := range skippedTrees {
			if under(path, t) {
				if d != nil && d.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}
		}
		if walkErr != nil {
			if !os.IsNotExist(walkErr) {
				res.Errors = append(res.Errors, fmt.Sprintf("%s: %v", path, walkErr))
			}
			if d != nil && d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !d.IsDir() && !d.Type().IsRegular() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			if !os.IsNotExist(err) {
				res.Errors = append(res.Errors, fmt.Sprintf("%s: %v", path, err))
			}
			return nil
		}
		st, ok := info.Sys().(*syscall.Stat_t)
		if !ok {
			return fmt.Errorf("no stat data for %s", path)
		}
		res.Scanned++
		res.Findings = append(res.Findings, p.check(entry{
			path:  path,
			mode:  info.Mode(),
			isDir: d.IsDir(),
			uid:   st.Uid,
			gid:   st.Gid,
		}, users, groups)...)
		return nil
	})
	if err != nil {
		return res, err
	}
	sort.Slice(res.Findings, func(i, j int) bool {
		if res.Findings[i].Path != res.Findings[j].Path {
			return res.Findings[i].Path < res.Findings[j].Path
		}
		return res.Findings[i].Detail < res.Findings[j].Detail
	})
	return res, nil
}

func (p *Policy) check(e entry, users, groups map[uint32]bool) []Finding {
	if p.excepted(e.path) {
		return nil
	}
	var out []Finding
	add := func(format string, args ...any) {
		out = append(out, Finding{Path: e.path, Detail: fmt.Sprintf(format, args...)})
	}

	perm := e.mode.Perm()
	sticky := e.isDir && e.mode&fs.ModeSticky != 0
	if !e.isDir && e.mode&(fs.ModeSetuid|fs.ModeSetgid) != 0 && !p.isSetuidAllowed(e.path) {
		add("setuid or setgid file %04o not in setuid list", unixMode(e.mode))
	}
	if perm&0o002 != 0 && !sticky {
		add("world-writable %04o", unixMode(e.mode))
	}
	if perm&0o020 != 0 && !sticky {
		add("group-writable %04o", unixMode(e.mode))
	}
	if !users[e.uid] {
		add("owner id %d has no passwd entry", e.uid)
	}
	if !groups[e.gid] {
		add("group id %d has no group entry", e.gid)
	}
	if p.inRoots(e.path) {
		allowed := p.FileModes
		if e.isDir {
			allowed = p.DirModes
		}
		if !modeSet(allowed)[perm] {
			add("mode %04o not in allowlist", perm)
		}
	}
	return out
}

func (p *Policy) isSetuidAllowed(path string) bool {
	for _, s := range p.Setuid {
		if s == path {
			return true
		}
	}
	return false
}

func (p *Policy) inRoots(path string) bool {
	for _, r := range p.Roots {
		if under(path, r) {
			return true
		}
	}
	return false
}

func unixMode(m fs.FileMode) uint32 {
	out := uint32(m.Perm())
	if m&fs.ModeSetuid != 0 {
		out |= 0o4000
	}
	if m&fs.ModeSetgid != 0 {
		out |= 0o2000
	}
	if m&fs.ModeSticky != 0 {
		out |= 0o1000
	}
	return out
}
