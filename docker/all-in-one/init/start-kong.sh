#!/bin/bash
set -eou pipefail

# In the event of a restart, properly stop any running kong instances first
# Confirmed by running /usr/local/bin/kong health
trap '/usr/local/bin/kong quit' EXIT
/usr/local/bin/kong start
