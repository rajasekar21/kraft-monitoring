#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: sudo $0 /path/to/akhq.jar <version>" >&2
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

id akhq >/dev/null 2>&1 || useradd --system --home "${INSTALL_ROOT}" --shell /usr/sbin/nologin akhq

mkdir -p "${RELEASE_DIR}" /etc/akhq/certs /var/log/akhq
install -o akhq -g akhq -m 0644 "${ARTIFACT}" "${RELEASE_DIR}/akhq.jar"
ln -sfn "${RELEASE_DIR}" "${INSTALL_ROOT}/current"
chown -h akhq:akhq "${INSTALL_ROOT}/current"
chown -R akhq:akhq "${INSTALL_ROOT}" /var/log/akhq
chown -R root:akhq /etc/akhq
chmod 0750 /etc/akhq

echo "Installed AKHQ ${VERSION} at ${RELEASE_DIR}"
echo "Next: install /etc/akhq/application.yml, /etc/akhq/akhq.env, and the systemd unit."
