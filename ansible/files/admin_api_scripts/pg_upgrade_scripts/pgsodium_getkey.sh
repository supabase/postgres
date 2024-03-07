#!/bin/bash

set -euo pipefail

if [ ! -d /etc/postgresql-custom/pgsodium ]; then
  mkdir /etc/postgresql-custom/pgsodium
fi

KEY_FILE=/etc/postgresql-custom/pgsodium/pgsodium_root.key

# if key file doesn't exist (project previously didn't use pgsodium), generate a new key
if [[ ! -f "${KEY_FILE}" ]]; then
    head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' > $KEY_FILE
fi

cat $KEY_FILE
