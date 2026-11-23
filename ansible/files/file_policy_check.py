import argparse
import os
import stat
import sys
import tarfile
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("file_policy_check.py requires PyYAML (apt install python3-yaml)")

DEFAULT_POLICY = Path(__file__).with_name("file_policy.yml")
SKIPPED_TREES = (
    "/proc",
    "/sys",
    "/dev",
    "/run",
    "/tmp",
    "/var/tmp",
    "/nix/store",
)


def under(path, tree):
    return path == tree or path.startswith(tree.rstrip("/") + "/")


def parse_mode(value):
    return value if isinstance(value, int) else int(value, 8)


def load_policy(path):
    raw = yaml.safe_load(Path(path).read_text())
    exceptions = []
    for entry in raw.get("exceptions") or []:
        exceptions.append(entry["path"] if isinstance(entry, dict) else entry)
    return {
        "files": {parse_mode(m) for m in raw["modes"]["files"]},
        "dirs": {parse_mode(m) for m in raw["modes"]["dirs"]},
        "roots": raw.get("roots") or [],
        "owners": raw.get("owners") or {},
        "setuid": set(raw.get("setuid") or []),
        "exceptions": exceptions,
    }


def excepted(path, exceptions):
    for pattern in exceptions:
        if pattern.endswith("/**"):
            if under(path, pattern[:-3]):
                return True
        elif path == pattern:
            return True
    return False


def parse_id_map(text):
    ids = {}
    for line in text.splitlines():
        fields = line.split(":")
        if len(fields) >= 3 and fields[2].isdigit():
            ids.setdefault(int(fields[2]), fields[0])
    return ids


def walk_root(root):
    entries = []
    errors = []
    root = os.path.abspath(root)

    def to_path(real):
        rel = os.path.relpath(real, root)
        return "/" if rel == "." else "/" + rel

    def record(real):
        path = to_path(real)
        try:
            st = os.lstat(real)
        except FileNotFoundError:
            return
        except OSError as e:
            errors.append(f"{path}: cannot stat: {e}")
            return
        if stat.S_ISDIR(st.st_mode):
            kind = "dir"
        elif stat.S_ISREG(st.st_mode):
            kind = "file"
        else:
            return
        entries.append((path, stat.S_IMODE(st.st_mode), kind, st.st_uid, st.st_gid))

    def on_error(e):
        if not isinstance(e, FileNotFoundError):
            errors.append(f"{to_path(e.filename)}: cannot read: {e}")

    for dirpath, dirnames, filenames in os.walk(root, onerror=on_error):
        dirnames[:] = [
            d
            for d in dirnames
            if not any(
                under(to_path(os.path.join(dirpath, d)), t) for t in SKIPPED_TREES
            )
        ]
        if not any(under(to_path(dirpath), t) for t in SKIPPED_TREES):
            record(dirpath)
        for name in filenames:
            path = to_path(os.path.join(dirpath, name))
            if not any(under(path, t) for t in SKIPPED_TREES):
                record(os.path.join(dirpath, name))

    users = groups = {}
    try:
        users = parse_id_map((Path(root) / "etc/passwd").read_text())
        groups = parse_id_map((Path(root) / "etc/group").read_text())
    except OSError as e:
        errors.append(f"cannot read passwd or group under {root}: {e}")
    return entries, users, groups, errors


def walk_tar(source):
    entries = []
    users = groups = {}
    with tarfile.open(
        name=None if source == "-" else source,
        fileobj=sys.stdin.buffer if source == "-" else None,
        mode="r|*",
    ) as tf:
        for member in tf:
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            name = name.rstrip("/")
            path = "/" + name if name not in ("", ".") else "/"
            if path == "/etc/passwd" and member.isreg():
                users = parse_id_map(tf.extractfile(member).read().decode())
            elif path == "/etc/group" and member.isreg():
                groups = parse_id_map(tf.extractfile(member).read().decode())
            if any(under(path, t) for t in SKIPPED_TREES):
                continue
            if member.isdir():
                kind = "dir"
            elif member.isreg() or member.islnk():
                kind = "file"
            else:
                continue
            entries.append((path, member.mode & 0o7777, kind, member.uid, member.gid))
    return entries, users, groups, []


def check(entries, users, groups, policy):
    violations = []
    by_path = {path: (mode, uid, gid) for path, mode, _, uid, gid in entries}
    excepted_paths = policy["exceptions"]

    for path, mode, kind, uid, gid in entries:
        if excepted(path, excepted_paths):
            continue
        if kind == "file" and mode & 0o6000 and path not in policy["setuid"]:
            violations.append(f"{path}: setuid/setgid {mode:04o} not in setuid list")
        sticky_dir = kind == "dir" and mode & 0o1000
        if mode & 0o002 and not sticky_dir:
            violations.append(f"{path}: world-writable {mode:04o}")
        if mode & 0o020 and not sticky_dir:
            violations.append(f"{path}: group-writable {mode:04o}")
        if uid not in users:
            violations.append(f"{path}: owner id {uid} has no passwd entry")
        if gid not in groups:
            violations.append(f"{path}: group id {gid} has no group entry")
        if any(under(path, r) for r in policy["roots"]):
            allowed = policy["files"] if kind == "file" else policy["dirs"]
            if mode & 0o777 not in allowed:
                violations.append(f"{path}: mode {mode & 0o777:04o} not in allowlist")

    for path, expected in policy["owners"].items():
        if path not in by_path or excepted(path, excepted_paths):
            continue
        _, uid, gid = by_path[path]
        actual = f"{users.get(uid, uid)}:{groups.get(gid, gid)}"
        if actual != expected:
            violations.append(f"{path}: owner {actual}, expected {expected}")
    return violations


def main():
    parser = argparse.ArgumentParser(
        description="Check file modes and owners against file_policy.yml"
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--root", help="directory to walk")
    source.add_argument("--tar", help="tar file to read, or - for stdin")
    parser.add_argument("--policy", default=str(DEFAULT_POLICY))
    args = parser.parse_args()

    policy = load_policy(args.policy)
    if args.root:
        entries, users, groups, errors = walk_root(args.root)
    else:
        entries, users, groups, errors = walk_tar(args.tar)

    violations = errors + check(entries, users, groups, policy)
    if violations:
        print("=" * 80)
        print("FILE POLICY VIOLATIONS:")
        print("=" * 80)
        for violation in violations:
            print(violation)
        print("=" * 80)
        print(f"{len(violations)} violation(s) in {len(entries)} entries")
        sys.exit(1)
    print(f"File policy check passed: {len(entries)} entries")


if __name__ == "__main__":
    main()
