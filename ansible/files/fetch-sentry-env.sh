#!/usr/bin/env bash
# fetch-sentry-env.sh — Boot-time Sentry environment fetcher
# Fetches AMI ID, instance ID, region, and Sentry DSN from SSM.
# Writes to /run/sentry.env (tmpfs — never touches disk).
# Idempotent: safe to re-run.

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
SENTRY_ENV_FILE="/run/sentry.env"
SSM_PARAM="/sentry/dsn"
IMDS_BASE="http://169.254.169.254"
MAX_RETRIES=3
RETRY_DELAY=2

IMDS_TOKEN=""

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

# ── IMDSv2 token fetch (once, reused across calls) ───────────────────────────
fetch_imds_token() {
    local attempt
    for (( attempt=1; attempt<=MAX_RETRIES; attempt++ )); do
        IMDS_TOKEN=$(curl -sf --retry 0 --connect-timeout 3 \
            -X PUT \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
            "${IMDS_BASE}/latest/api/token" 2>/dev/null) && return 0
        log "IMDS token attempt ${attempt}/${MAX_RETRIES} failed"
        [[ $attempt -lt $MAX_RETRIES ]] && sleep "$RETRY_DELAY"
    done
    die "Failed to obtain IMDSv2 token after ${MAX_RETRIES} attempts"
}

# ── IMDSv2 helper (with retry) ────────────────────────────────────────────────
imds_get() {
    local path="$1"
    local result attempt
    for (( attempt=1; attempt<=MAX_RETRIES; attempt++ )); do
        result=$(curl -sf --retry 0 --connect-timeout 3 \
            -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
            "${IMDS_BASE}/latest/meta-data/${path}" 2>/dev/null) && {
            echo "${result}"
            return 0
        }
        log "IMDS GET ${path} attempt ${attempt}/${MAX_RETRIES} failed"
        [[ $attempt -lt $MAX_RETRIES ]] && sleep "$RETRY_DELAY"
    done
    die "Failed to fetch IMDS ${path} after ${MAX_RETRIES} attempts"
}

# ── Fetch metadata ────────────────────────────────────────────────────────────
log "Fetching instance metadata via IMDSv2..."
fetch_imds_token

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

# ── Write /run/sentry.env (tmpfs — never on disk, mode 0600) ─────────────────
log "Writing ${SENTRY_ENV_FILE}..."
_tmp=$(mktemp "${SENTRY_ENV_FILE}.XXXXXX")
cat > "${_tmp}" <<EOF
# Generated at boot by fetch-sentry-env.sh — do not edit manually
SENTRY_RELEASE="${AMI_ID}"
SENTRY_ENVIRONMENT="${SENTRY_ENVIRONMENT}"
SENTRY_DSN="${SENTRY_DSN}"
SENTRY_SERVER_NAME="${INSTANCE_ID}"
EOF
chmod 0600 "${_tmp}"
mv "${_tmp}" "${SENTRY_ENV_FILE}"

log "Done. Sentry env written to ${SENTRY_ENV_FILE} (tmpfs, never on disk)."
