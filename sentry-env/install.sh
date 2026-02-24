#!/usr/bin/env bash
# install.sh — Installs the sentry-env boot integration
# Usage: sudo ./install.sh [postgresql-service-name]
# Default PostgreSQL service name: postgresql
# Example override: sudo ./install.sh postgresql@15-main
# Supports Ubuntu 22.04/24.04 and Amazon Linux 2023.

set -euo pipefail

PG_SERVICE="${1:-postgresql}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[install] $*"; }
die() { echo "[install] ERROR: $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Must be run as root (use sudo)"

# 1. Install fetch script
log "Installing /usr/local/bin/fetch-sentry-env.sh..."
install -m 0755 "${SCRIPT_DIR}/fetch-sentry-env.sh" /usr/local/bin/fetch-sentry-env.sh

# 2. Install systemd unit
log "Installing /etc/systemd/system/sentry-env.service..."
install -m 0644 "${SCRIPT_DIR}/sentry-env.service" /etc/systemd/system/sentry-env.service

# 3. Install PostgreSQL drop-in
DROPIN_DIR="/etc/systemd/system/${PG_SERVICE}.service.d"
log "Installing drop-in to ${DROPIN_DIR}/sentry.conf..."
mkdir -p "${DROPIN_DIR}"
install -m 0644 "${SCRIPT_DIR}/postgresql-sentry.conf" "${DROPIN_DIR}/sentry.conf"

# 4. Reload systemd and enable
log "Running systemctl daemon-reload..."
systemctl daemon-reload

log "Enabling sentry-env.service..."
systemctl enable sentry-env.service

log "Installation complete."
log "On next boot, sentry-env.service will run automatically."
log "To test now: systemctl start sentry-env.service && journalctl -u sentry-env.service"
