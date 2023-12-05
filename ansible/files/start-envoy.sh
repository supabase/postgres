#!/usr/bin/env bash
set -eou pipefail
# Workaround using `tee` to get `/dev/stdout` access logging to work, see:
# https://github.com/envoyproxy/envoy/issues/8297#issuecomment-620659781
exec /opt/envoy --config-path /etc/envoy/envoy.yaml --restart-epoch "$RESTART_EPOCH" 2>&1 | tee
