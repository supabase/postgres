#! /usr/bin/env bash

set -euo pipefail

string=$1

# conditions
# no space that could lead to multiple files
# no form of slashes or two dots that leads to a relative path
if [[ $string =~ \ |\'|\.{2}|\/|\\ ]]; then
    echo "Invalid string. Exiting."
    exit 1
fi

# once valid, proceed to change ownership
chown postgres:postgres  /tmp/$string
