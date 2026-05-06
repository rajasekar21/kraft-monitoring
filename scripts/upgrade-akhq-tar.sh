#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: sudo $0 /path/to/akhq.jar <new-version>" >&2
  exit 1
fi

ARTIFACT="$1"
VERSION="$2"
INSTALL_ROOT="/opt/akhq"
RELEASE_DIR="${INSTALL_ROOT}/releases/${VERSION}"

if [[ ! -f "${ARTIFACT}" ]]; then
  echo "AKHQ artifact not found: ${ARTIFACT}" >&2
  exit 1
fi

mkdir -p "${RELEASE_DIR}"
install -o akhq -g akhq -m 0644 "${ARTIFACT}" "${RELEASE_DIR}/akhq.jar"
ln -sfn "${RELEASE_DIR}" "${INSTALL_ROOT}/current"
chown -h akhq:akhq "${INSTALL_ROOT}/current"

systemctl restart akhq
echo "Upgraded AKHQ to ${VERSION}"
