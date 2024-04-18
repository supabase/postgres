#!/usr/bin/env bash

export GOTRUE_DISABLE=true
export FAIL2BAN_DISABLE=true

# docker run -v "$(pwd)"/salt:/opt/salt \
docker run --rm -ti -v "$(pwd)"/salt:/opt/salt \
  --name salt-minion \
  salt-minion \
  /usr/bin/salt-call --local state.apply # -l debug
