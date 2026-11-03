#!/usr/bin/env bash
# Usage: install.sh <version> <amd64|arm64> <sha256> [url]
# url is a presigned URL, or an s3:// URL to presign with the caller's AWS credentials.
# Defaults to the internal artifacts bucket. Safe to rerun on a live host.
set -euo pipefail

version=$1
arch=$2
sha256=$3

archive=supa-tripwire-v$version-$arch.tar.xz
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

url=${4:-s3://supabase-internal-artifacts/supa-tripwire/$archive}
[[ $url != s3://* ]] || url=$(aws s3 presign --region ap-southeast-1 "$url")
curl -fsSL --retry 3 -o "$tmp/$archive" "$url"
echo "$sha256  $tmp/$archive" | sha256sum -c --quiet -

tar -xJf "$tmp/$archive" -O "supa-tripwire-v$version-$arch-linux-musl" >/usr/local/bin/supa-tripwire.new
chmod 0755 /usr/local/bin/supa-tripwire.new
mv -f /usr/local/bin/supa-tripwire.new /usr/local/bin/supa-tripwire

cat >/usr/local/bin/supa-tripwire-wrapped <<'WRAPPER'
#!/usr/bin/env bash

POSTGRES_BIN=$(readlink -f $(which postgres))
POSTGRES_DIR=$(dirname "$POSTGRES_BIN")
WRAPPED="$POSTGRES_DIR/.postgres-wrapped"

if [ -f "$WRAPPED" ]; then
    TARGET="$WRAPPED"
else
    TARGET="$POSTGRES_BIN"
fi

exec /usr/local/bin/supa-tripwire "$TARGET"
WRAPPER
chmod 0755 /usr/local/bin/supa-tripwire-wrapped

[[ -e /etc/supa-tripwire.env ]] || install -m 0600 /dev/null /etc/supa-tripwire.env

cat >/etc/systemd/system/supa-tripwire.service <<'UNIT'
# /etc/systemd/system/supa-tripwire.service
[Unit]
Description=supa-tripwire - Postgres badness monitor
After=postgresql.service

[Service]
User=root
Restart=always
RestartSec=5

EnvironmentFile=/etc/supa-tripwire.env

ExecStart=/usr/local/bin/supa-tripwire-wrapped

NoNewPrivileges=true
SecureBits=no-setuid-fixup-locked
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload || true
systemctl enable supa-tripwire
if systemctl is-active --quiet supa-tripwire; then
	systemctl restart supa-tripwire
fi
