#!/usr/bin/env bash

set -euo pipefail

: "${IMAGE:?}" "${PG_UPGRADE_STORE_PATH:?}"

cd "$(git rev-parse --show-toplevel)"
[[ $(uname -s) == Darwin ]] && accel=hvf || accel=kvm
work=$(mktemp -d)
trap '[ ! -f "$work/pid" ] || kill "$(cat "$work/pid")"; rm -rf "$work"' EXIT

share=$(dirname "$(dirname "$(command -v qemu-system-aarch64)")")/share/qemu
install -m 644 "$share/edk2-arm-vars.fd" "$work/vars.fd"
qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$IMAGE")" "$work/disk.qcow2" 30G
cloud-localds "$work/seed.iso" user-data-cloudimg meta-data

qemu-system-aarch64 \
	-machine "virt,gic-version=max,highmem=on,accel=$accel" -cpu host -smp 4 -m 8192 \
	-display none -serial "file:${CONSOLE_LOG:-/tmp/pg-upgrade-qemu-console.log}" -daemonize -pidfile "$work/pid" \
	-drive "if=pflash,format=raw,readonly=on,file=$share/edk2-aarch64-code.fd" \
	-drive "if=pflash,format=raw,file=$work/vars.fd" \
	-drive "file=$work/disk.qcow2,if=virtio,format=qcow2" \
	-drive "file=$work/seed.iso,format=raw,if=virtio" \
	-netdev "user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22" -device virtio-net-pci,netdev=n0

export SSHPASS=ubuntu
ssh_opts=(-p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
vm() { sshpass -e ssh "${ssh_opts[@]}" ubuntu@127.0.0.1 "$@"; }

# nix copy needs a trusted user over key auth, which only root is
ssh-keygen -q -N '' -f "$work/key"
until vm 'sudo install -d -m 700 /root/.ssh && sudo tee /root/.ssh/authorized_keys >/dev/null' <"$work/key.pub" 2>/dev/null; do sleep 5; done
vm() { ssh "${ssh_opts[@]}" -i "$work/key" root@127.0.0.1 "$@"; }
NIX_SSHOPTS="${ssh_opts[*]} -i $work/key" nix copy --no-check-sigs \
	--to "ssh-ng://root@127.0.0.1?remote-program=/nix/var/nix/profiles/default/bin/nix-daemon" \
	"$PG_UPGRADE_STORE_PATH"

tar --no-xattrs -c migrations/db ansible/files/admin_api_scripts/pg_upgrade_scripts ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql ansible/files/stat_extension.sql tests/pg_upgrade/tests |
	vm 'rm -rf /tmp/t && mkdir /tmp/t && tar -C /tmp/t -x'

vm bash -eu -s "$PG_UPGRADE_STORE_PATH" <<'EOF'
export PATH=/usr/lib/postgresql/bin:$PATH PGDATA=/var/lib/postgresql/data PG_MAJOR_VERSION=17
export PG_UPGRADE_STORE_PATH=$1
cd /tmp/t
scripts=$PWD/ansible/files/admin_api_scripts/pg_upgrade_scripts
psql_admin() { psql -h localhost -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -X "$@"; }

# initdb's bootstrap child reads timezone data from the compiled-in /usr/share/postgresql
ln -sfn /usr/lib/postgresql/share/postgresql /usr/share/postgresql
install -d -o postgres -g postgres -m 0750 /data/pgdata
flags=(--data-checksums)
[ "$(pg_config --version | grep -o '[0-9]*' | head -1)" -ge 17 ] && flags+=(--locale-provider=icu --encoding=UTF-8 --icu-locale=en_US.UTF-8)
su postgres -c "LC_ALL=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive pg_ctl -D /var/lib/postgresql/data initdb -o '--allow-group-access --username=supabase_admin ${flags[*]}'"
bash "$scripts/pgsodium_getkey.sh" >/dev/null
systemctl start postgresql
until pg_isready -h localhost; do sleep 1; done

psql_admin -c "create role postgres superuser login; alter database postgres owner to postgres;"
for f in pgbouncer_config/pgbouncer_auth_schema.sql stat_extension.sql; do psql_admin -U postgres -f "ansible/files/$f"; done
POSTGRES_HOST=localhost sh migrations/db/migrate.sh
for f in tests/pg_upgrade/tests/9*.sql; do psql_admin -f "$f"; done

# arm64 packages are not on archive.ubuntu.com
sed -i 's|http://[a-z]*.ubuntu.com/ubuntu|http://ports.ubuntu.com/ubuntu-ports|' /etc/apt/sources.list.d/*.sources

IS_LOCAL_UPGRADE=true NIX_FLAKE_VERSION=local "$scripts/initiate.sh" 17

# complete.sh starts the new server from here, which a nix upgrade fills with only a version file
rm -rf /tmp/pg_upgrade_bin/17
ln -s "$PG_UPGRADE_STORE_PATH" /tmp/pg_upgrade_bin/17
# Restart=always would bring the old server back, and complete.sh moves /data_migration to /data, which must not exist
systemctl disable --now postgresql
mv /data /data.old
rm -f /tmp/pg-upgrade-status
IS_CI=true "$scripts/complete.sh"

[ "$(psql_admin -At -c 'show server_version_num')" -ge 170000 ]
for f in tests/pg_upgrade/tests/0*.sql; do
	out=$(psql_admin -At -f "$f")
	echo "$out"
	if grep -q '^not ok' <<<"$out"; then exit 1; fi
done
EOF
