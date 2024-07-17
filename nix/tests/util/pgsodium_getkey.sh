# NOTE (aseipp): just use some random key for testing, no need to query
# /dev/urandom. also helps ferrit out other random flukes, perhaps?

#echo -n 8359dafbba5c05568799c1c24eb6c2fbff497654bc6aa5e9a791c666768875a1

#!/bin/bash

set -euo pipefail

KEY_FILE="${1:-/tmp/pgsodium.key}"

if [[ ! -f "${KEY_FILE}" ]]; then
    head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' > "${KEY_FILE}"
fi
cat $KEY_FILE