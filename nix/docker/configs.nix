{
  lib,
  pkgs,
  variant,
  sourceRoot,
}:
let
  isOrioledb = variant == "orioledb-17";
  isPg17 = variant == "17" || isOrioledb;
in
pkgs.runCommand "postgres-docker-configs-${variant}" { nativeBuildInputs = [ pkgs.gnused ]; } ''
    mkdir -p $out/etc/postgresql
    mkdir -p $out/etc/postgresql-custom
    mkdir -p $out/etc/postgresql-custom/extension-custom-scripts
    mkdir -p $out/usr/lib/postgresql/bin
    mkdir -p $out/home/postgres
    mkdir -p $out/root
    mkdir -p $out/docker-entrypoint-initdb.d/init-scripts
    mkdir -p $out/docker-entrypoint-initdb.d/migrations
    mkdir -p $out/var/lib/postgresql
    mkdir -p $out/var/run/postgresql

    # Create passwd and group entries for postgres user
    # These will be merged with the base image's files by the entrypoint
    # Using standard postgres UID/GID (999) matching the official postgres image
    cat > $out/etc/passwd <<'PASSWD'
  root:x:0:0:root:/root:/bin/bash
  daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
  bin:x:2:2:bin:/bin:/usr/sbin/nologin
  sys:x:3:3:sys:/dev:/usr/sbin/nologin
  sync:x:4:65534:sync:/bin:/bin/sync
  games:x:5:60:games:/usr/games:/usr/sbin/nologin
  man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
  lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
  mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
  news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
  uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
  proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
  www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
  backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
  list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
  irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
  _apt:x:42:65534::/nonexistent:/usr/sbin/nologin
  nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
  postgres:x:999:999:PostgreSQL administrator:/var/lib/postgresql:/bin/bash
  wal-g:x:998:998::/nonexistent:/bin/bash
  PASSWD

    cat > $out/etc/group <<'GROUP'
  root:x:0:
  daemon:x:1:
  bin:x:2:
  sys:x:3:
  adm:x:4:
  tty:x:5:
  disk:x:6:
  lp:x:7:
  mail:x:8:
  news:x:9:
  uucp:x:10:
  man:x:12:
  proxy:x:13:
  kmem:x:15:
  dialout:x:20:
  fax:x:21:
  voice:x:22:
  cdrom:x:24:
  floppy:x:25:
  tape:x:26:
  sudo:x:27:
  audio:x:29:
  dip:x:30:
  www-data:x:33:
  backup:x:34:
  operator:x:37:
  list:x:38:
  irc:x:39:
  src:x:40:
  shadow:x:42:
  utmp:x:43:
  video:x:44:
  sasl:x:45:
  plugdev:x:46:
  staff:x:50:
  games:x:60:
  users:x:100:
  nogroup:x:65534:
  postgres:x:999:
  wal-g:x:998:
  GROUP

    cat > $out/etc/shadow <<'SHADOW'
  root:*:19000:0:99999:7:::
  daemon:*:19000:0:99999:7:::
  bin:*:19000:0:99999:7:::
  sys:*:19000:0:99999:7:::
  sync:*:19000:0:99999:7:::
  games:*:19000:0:99999:7:::
  man:*:19000:0:99999:7:::
  lp:*:19000:0:99999:7:::
  mail:*:19000:0:99999:7:::
  news:*:19000:0:99999:7:::
  uucp:*:19000:0:99999:7:::
  proxy:*:19000:0:99999:7:::
  www-data:*:19000:0:99999:7:::
  backup:*:19000:0:99999:7:::
  list:*:19000:0:99999:7:::
  irc:*:19000:0:99999:7:::
  _apt:*:19000:0:99999:7:::
  nobody:*:19000:0:99999:7:::
  postgres:*:19000:0:99999:7:::
  wal-g:*:19000:0:99999:7:::
  SHADOW
    chmod 640 $out/etc/shadow

    # Copy base configs (and make writable for sed transformations)
    cp ${sourceRoot}/ansible/files/postgresql_config/postgresql.conf.j2 $out/etc/postgresql/postgresql.conf
    cp ${sourceRoot}/ansible/files/postgresql_config/pg_hba.conf.j2 $out/etc/postgresql/pg_hba.conf
    cp ${sourceRoot}/ansible/files/postgresql_config/pg_ident.conf.j2 $out/etc/postgresql/pg_ident.conf
    cp ${sourceRoot}/ansible/files/postgresql_config/postgresql-stdout-log.conf $out/etc/postgresql/logging.conf
    cp ${sourceRoot}/ansible/files/postgresql_config/supautils.conf.j2 $out/etc/postgresql-custom/supautils.conf
    cp ${sourceRoot}/ansible/files/postgresql_config/custom_read_replica.conf.j2 $out/etc/postgresql-custom/read-replica.conf
    cp ${sourceRoot}/ansible/files/postgresql_config/custom_walg.conf.j2 $out/etc/postgresql-custom/wal-g.conf
    mkdir -p $out/etc/postgresql-custom/conf.d
    cp -r ${sourceRoot}/ansible/files/postgresql_config/conf.d/* $out/etc/postgresql-custom/conf.d/
    cp ${sourceRoot}/ansible/files/postgresql_extension_custom_scripts/before-create.sql $out/etc/postgresql-custom/extension-custom-scripts/

    # Make config files writable for sed transformations
    chmod -R u+w $out/etc/postgresql $out/etc/postgresql-custom

    # Create pgsodium getkey script with writable key location
    # The original script writes to /etc/postgresql-custom which is read-only in nix
    # Use PGDATA directory which is owned by postgres
    cat > $out/usr/lib/postgresql/bin/pgsodium_getkey.sh <<'GETKEY'
  #!/bin/bash
  set -euo pipefail

  # Use PGDATA for the key file - this directory is created and owned by postgres
  KEY_FILE="''${PGDATA:-/var/lib/postgresql/data}/pgsodium_root.key"

  if [[ ! -f "''${KEY_FILE}" ]]; then
      head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' > "''${KEY_FILE}"
      chmod 600 "''${KEY_FILE}"
  fi
  cat $KEY_FILE
  GETKEY
    chmod +x $out/usr/lib/postgresql/bin/pgsodium_getkey.sh

    # Copy wal-g helper scripts
    cp ${sourceRoot}/ansible/files/walg_helper_scripts/wal_fetch.sh $out/home/postgres/wal_fetch.sh
    cp ${sourceRoot}/ansible/files/walg_helper_scripts/wal_change_ownership.sh $out/root/wal_change_ownership.sh

    # Copy migrations
    cp -r ${sourceRoot}/migrations/db/* $out/docker-entrypoint-initdb.d/
    cp ${sourceRoot}/ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql $out/docker-entrypoint-initdb.d/init-scripts/00-schema.sql
    cp ${sourceRoot}/ansible/files/stat_extension.sql $out/docker-entrypoint-initdb.d/migrations/00-extension.sql

    # Make init scripts writable for OrioleDB additions
    chmod -R u+w $out/docker-entrypoint-initdb.d

    # Apply sed transformations (same as Dockerfile)
    sed -i \
      -e "s|#unix_socket_directories = '/tmp'|unix_socket_directories = '/var/run/postgresql'|g" \
      -e "s|#session_preload_libraries = '''|session_preload_libraries = 'supautils'|g" \
      -e "s|#include = '/etc/postgresql-custom/supautils.conf'|include = '/etc/postgresql-custom/supautils.conf'|g" \
      -e "s|#include = '/etc/postgresql-custom/wal-g.conf'|include = '/etc/postgresql-custom/wal-g.conf'|g" \
      $out/etc/postgresql/postgresql.conf

    echo "pgsodium.getkey_script= '/usr/lib/postgresql/bin/pgsodium_getkey.sh'" >> $out/etc/postgresql/postgresql.conf
    echo "vault.getkey_script= '/usr/lib/postgresql/bin/pgsodium_getkey.sh'" >> $out/etc/postgresql/postgresql.conf

    ${lib.optionalString isPg17 ''
      # PG17 specific: remove timescaledb from shared_preload_libraries
      sed -i 's/ timescaledb,//g' $out/etc/postgresql/postgresql.conf
      # PG 16.4+ deprecation
      sed -i 's/db_user_namespace = off/#db_user_namespace = off/g' $out/etc/postgresql/postgresql.conf
      sed -i 's/ timescaledb,//g; s/ plv8,//g' $out/etc/postgresql-custom/supautils.conf
    ''}

    ${lib.optionalString isOrioledb ''
      # OrioleDB specific transforms
      sed -i 's/ timescaledb,//g; s/ plv8,//g; s/ postgis,//g; s/ pgrouting,//g' $out/etc/postgresql-custom/supautils.conf
      sed -i "s/\(shared_preload_libraries.*\)'\(.*\)$/\1, orioledb'\2/" $out/etc/postgresql/postgresql.conf
      echo "default_table_access_method = 'orioledb'" >> $out/etc/postgresql/postgresql.conf

      # OrioleDB rewind configuration
      echo "orioledb.enable_rewind = true" >> $out/etc/postgresql/postgresql.conf
      echo "orioledb.rewind_max_time = 1200" >> $out/etc/postgresql/postgresql.conf
      echo "orioledb.rewind_max_transactions = 100000" >> $out/etc/postgresql/postgresql.conf
      echo "orioledb.rewind_buffers = 1280" >> $out/etc/postgresql/postgresql.conf

      # Enable orioledb extension first - use exact same format as initial-schema but with name that sorts earlier
      # Must match the 14-zero format because en_US.UTF-8 locale collation ignores punctuation initially
      echo "CREATE EXTENSION orioledb;" > $out/docker-entrypoint-initdb.d/init-scripts/00000000000000-a-orioledb.sql
    ''}
''
