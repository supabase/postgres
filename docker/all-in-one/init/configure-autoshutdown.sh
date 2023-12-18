#!/bin/bash
set -eou pipefail

mkdir -p /etc/supa-shutdown

AUTOSHUTDOWN_CUSTOM_DIR="${DATA_VOLUME_MOUNTPOINT}/etc/supa-shutdown"
if [ "${DATA_VOLUME_MOUNTPOINT}" ]; then
  mkdir -p "${AUTOSHUTDOWN_CUSTOM_DIR}"

  AUTOSHUTDOWN_CUSTOM_CONFIG_FILE_PATH="${AUTOSHUTDOWN_CUSTOM_DIR}/shutdown.conf"
  if [ ! -f "${AUTOSHUTDOWN_CUSTOM_CONFIG_FILE_PATH}" ]; then
    echo "Copying existing custom shutdown config from /etc/supa-shutdown to ${AUTOSHUTDOWN_CUSTOM_CONFIG_FILE_PATH}"
    cp "/etc/supa-shutdown/shutdown.conf" "${AUTOSHUTDOWN_CUSTOM_CONFIG_FILE_PATH}"
  fi

  rm -f "/etc/supa-shutdown/shutdown.conf"
  ln -s "${AUTOSHUTDOWN_CUSTOM_CONFIG_FILE_PATH}" "/etc/supa-shutdown/shutdown.conf"
  chmod g+wrx "${AUTOSHUTDOWN_CUSTOM_DIR}"
  chown -R adminapi:adminapi "/etc/supa-shutdown/shutdown.conf"
  chown -R adminapi:adminapi "${AUTOSHUTDOWN_CUSTOM_CONFIG_FILE_PATH}"
fi
