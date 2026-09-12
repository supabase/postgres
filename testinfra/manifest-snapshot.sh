#!/bin/sh
set -eu

EXCLUDE='^/(proc|run|tmp|var/log|data)(/|$)'

find / -xdev \( -type f -o -type l \) 2>/dev/null | grep -Ev "$EXCLUDE" | sort | while read -r f; do
  if [ -L "$f" ]; then
    printf '%s\tlink\t%s\n' "$f" "$(readlink "$f")"
  else
    printf '%s\t%s\t%s\n' "$f" "$(stat -c '%a:%U:%G' "$f" 2>/dev/null || echo '?')" "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)"
  fi
done

echo '--- units ---'
systemctl list-unit-files --no-pager 2>/dev/null | sort
echo '--- users ---'
getent passwd | sort
echo '--- groups ---'
getent group | sort
echo '--- nft ---'
nft list ruleset 2>/dev/null || true
echo '--- sysctl ---'
sysctl -a 2>/dev/null | sort
