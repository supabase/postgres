#!/bin/bash
exec /opt/envoy --config-path /etc/envoy/envoy.yaml --restart-epoch "$RESTART_EPOCH"
