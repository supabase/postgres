#!/bin/bash
set -eou pipefail

mkdir -p /var/run/fail2ban
touch /var/log/services/fail2ban.log
touch /var/log/postgresql/auth-failures.csv
