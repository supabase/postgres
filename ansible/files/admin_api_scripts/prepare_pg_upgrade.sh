#! /usr/bin/env bash

set -euo pipefail

service postgresql stop
unmount /data