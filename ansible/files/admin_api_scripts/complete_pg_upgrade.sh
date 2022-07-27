#! /usr/bin/env bash

set -euo pipefail

mount -a -v

vacuumdb --all --analyze-in-stages
service postgresql start