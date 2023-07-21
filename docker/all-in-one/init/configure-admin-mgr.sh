#!/bin/bash
set -eou pipefail

ADMINMGR_CUSTOM_DIR="${DATA_VOLUME_MOUNTPOINT}/admin-mgr"

if [ "${DATA_VOLUME_MOUNTPOINT}" ]; then
  mkdir -p "${ADMINMGR_CUSTOM_DIR}"

  if [ ! -f "${ADMINMGR_CUSTOM_DIR}/admin-mgr" ]; then
    echo "Copying existing admin-mgr binary from /usr/bin/admin-mgr to ${ADMINMGR_CUSTOM_DIR}"
    cp "/usr/bin/admin-mgr" "${ADMINMGR_CUSTOM_DIR}/admin-mgr"
  fi

  rm -f "/usr/bin/admin-mgr"
  ln -s "${ADMINMGR_CUSTOM_DIR}/admin-mgr" "/usr/bin/admin-mgr"
  chown -R postgres:postgres "/usr/bin/admin-mgr"

  chown -R /usr/bin/admin-mgr "${ADMINMGR_CUSTOM_DIR}"
  chmod g+rx "${ADMINMGR_CUSTOM_DIR}"
fi
