#!/bin/bash
set -eou pipefail

touch /var/log/services/fail2ban.log
touch /var/log/postgresql/auth-failures.csv
