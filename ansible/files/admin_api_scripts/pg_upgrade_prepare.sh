#! /usr/bin/env bash

set -euo pipefail

systemctl stop postgresql
umount /data