#!/usr/bin/env bash
# fetch-sentry-env.sh — Boot-time Sentry environment fetcher
# Fetches AMI ID, instance ID, region, and Sentry DSN from SSM.
# Writes /etc/sentry.env (systemd EnvironmentFile) and
# /etc/profile.d/sentry_env.sh (login shell export format).
# Idempotent: safe to re-run.

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
SENTRY_ENV_FILE="/etc/sentry.env"
PROFILE_FILE="/etc/profile.d/sentry_env.sh"
SSM_PARAM="/sentry/dsn"
IMDS_BASE="http://169.254.169.254"
MAX_RETRIES=3
RETRY_DELAY=2

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
    local msg="fetch-sentry-env: $*"
    echo "$msg" >&2
    logger -t fetch-sentry-env "$*" 2>/dev/null || true
}

die() {
    log "ERROR: $*"
    exit 1
}

# ── IMDSv2 helper (with retry) ────────────────────────────────────────────────
imds_get() {
    local path="$1"
    local token attempt

    for attempt in $(seq 1 "$MAX_RETRIES"); do
        # Step 1: get IMDSv2 token (TTL 21600s = 6h)
        token=$(curl -sf --retry 0 --connect-timeout 3 \
            -X PUT \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
            "${IMDS_BASE}/latest/api/token" 2>/dev/null) && break || {
            log "IMDS token attempt ${attempt}/${MAX_RETRIES} failed, waiting ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        }
    done

    [[ -n "${token:-}" ]] || die "Failed to obtain IMDSv2 token after ${MAX_RETRIES} attempts"

    # Step 2: fetch the metadata path
    curl -sf --retry 0 --connect-timeout 3 \
        -H "X-aws-ec2-metadata-token: ${token}" \
        "${IMDS_BASE}/latest/meta-data/${path}" \
        || die "IMDS GET /latest/meta-data/${path} failed"
}

# ── Fetch metadata ────────────────────────────────────────────────────────────
log "Fetching instance metadata via IMDSv2..."

AMI_ID=$(imds_get "ami-id")
INSTANCE_ID=$(imds_get "instance-id")
REGION=$(imds_get "placement/region")

log "AMI_ID=${AMI_ID} INSTANCE_ID=${INSTANCE_ID} REGION=${REGION}"

# ── Optional: instance tag for SENTRY_ENVIRONMENT ────────────────────────────
SENTRY_ENVIRONMENT="production"
tag_value=$(aws ec2 describe-tags \
    --region "${REGION}" \
    --filters "Name=resource-id,Values=${INSTANCE_ID}" \
              "Name=key,Values=Environment" \
    --query 'Tags[0].Value' \
    --output text 2>/dev/null || true)

if [[ -n "${tag_value}" && "${tag_value}" != "None" && "${tag_value}" != "null" ]]; then
    SENTRY_ENVIRONMENT="${tag_value}"
    log "SENTRY_ENVIRONMENT overridden from EC2 tag: ${SENTRY_ENVIRONMENT}"
fi

# ── Fetch Sentry DSN from SSM ─────────────────────────────────────────────────
log "Fetching Sentry DSN from SSM Parameter Store (${SSM_PARAM})..."
SENTRY_DSN=$(aws ssm get-parameter \
    --region "${REGION}" \
    --name "${SSM_PARAM}" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text 2>/dev/null) \
    || { log "WARNING: Failed to fetch SSM parameter ${SSM_PARAM}. Sentry reporting may be disabled."; SENTRY_DSN=""; }

# ── Write /etc/sentry.env (systemd EnvironmentFile format) ───────────────────
log "Writing ${SENTRY_ENV_FILE}..."
cat > "${SENTRY_ENV_FILE}" <<EOF
# Generated at boot by fetch-sentry-env.sh — do not edit manually
SENTRY_RELEASE=${AMI_ID}
SENTRY_ENVIRONMENT=${SENTRY_ENVIRONMENT}
SENTRY_DSN=${SENTRY_DSN}
SENTRY_SERVER_NAME=${INSTANCE_ID}
EOF
chmod 0644 "${SENTRY_ENV_FILE}"

# ── Write /etc/profile.d/sentry_env.sh (login shell format) ──────────────────
log "Writing ${PROFILE_FILE}..."
cat > "${PROFILE_FILE}" <<EOF
# Generated at boot by fetch-sentry-env.sh — do not edit manually
export SENTRY_RELEASE="${AMI_ID}"
export SENTRY_ENVIRONMENT="${SENTRY_ENVIRONMENT}"
export SENTRY_DSN="${SENTRY_DSN}"
export SENTRY_SERVER_NAME="${INSTANCE_ID}"
EOF
chmod 0644 "${PROFILE_FILE}"

log "Done. Sentry env written to ${SENTRY_ENV_FILE} and ${PROFILE_FILE}."
