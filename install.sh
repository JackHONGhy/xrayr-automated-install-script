#!/usr/bin/env bash
set -euo pipefail

REPO="${XRAYR_REPO:-JackHONGhy/xrayr-automated-install-script}"
BRANCH="${XRAYR_BRANCH:-master}"
MANAGER="xrayr-manager.sh"
BASE_URL="${XRAYR_BASE_URL:-https://raw.githubusercontent.com/${REPO}/${BRANCH}}"
BUILD_ID="xrayr-0.9.4-quicfix.1-online.1"
TMP_DIR="$(mktemp -d)"
INSTALL_ROOT="${XRAYR_INSTALL_ROOT:-/}"
ROOT_PREFIX="${INSTALL_ROOT%/}"
[ -n "${ROOT_PREFIX}" ] || ROOT_PREFIX="/"
CONFIG_FILE="${XRAYR_CONFIG_FILE:-${ROOT_PREFIX}/etc/XrayR/config.yml}"
SERVICE_FILE="${XRAYR_SERVICE_FILE:-${ROOT_PREFIX}/etc/systemd/system/XrayR.service}"
XRAYR_BINARY="${XRAYR_BINARY:-${ROOT_PREFIX}/usr/local/XrayR/XrayR}"
MANAGER_INSTALL_PATH="${XRAYR_MANAGER_INSTALL_PATH:-${ROOT_PREFIX}/usr/bin/XrayR}"
MANAGER_LINK_TARGET="${XRAYR_MANAGER_LINK_TARGET:-/usr/bin/XrayR}"
MANAGER_LINK_PATH_1="${XRAYR_MANAGER_LINK_PATH_1:-${ROOT_PREFIX}/usr/bin/xrayr}"
MANAGER_LINK_PATH_2="${XRAYR_MANAGER_LINK_PATH_2:-${ROOT_PREFIX}/usr/local/bin/XrayR}"
MANAGER_LINK_PATH_3="${XRAYR_MANAGER_LINK_PATH_3:-${ROOT_PREFIX}/usr/local/bin/xrayr}"
CONFIG_BACKUP="${TMP_DIR}/config.yml"
BINARY_BACKUP="${TMP_DIR}/XrayR"
SERVICE_BACKUP="${TMP_DIR}/XrayR.service"
CONFIG_WAS_PRESENT=0
BINARY_WAS_PRESENT=0
SERVICE_WAS_PRESENT=0
WAS_ACTIVE=0

cleanup() { rm -rf -- "${TMP_DIR}"; }
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ] && [ "${XRAYR_INSTALLER_TEST_MODE:-0}" != "1" ]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64|amd64)
    ARCHIVE="xrayr-0.9.4-linux-amd64-default-config.tar.gz"
    SHA256="f771409273e716aa821db42011343d3ac4a2b3465c986073a8dbe081147bcd9b"
    ARCH_NAME="linux-amd64" ;;
  aarch64|arm64)
    ARCHIVE="xrayr-0.9.4-linux-arm64-default-config.tar.gz"
    SHA256="31f1499429ae1a587566fd44291c402614faadda1176bdfd9430a1156645998b"
    ARCH_NAME="linux-arm64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
for command_name in curl tar sha256sum cp grep install systemctl journalctl; do need_cmd "${command_name}"; done

wait_for_active() {
  local deadline=$((SECONDS + ${XRAYR_SERVICE_TIMEOUT:-30}))
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    systemctl is-active --quiet XrayR 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

redact_diagnostics() {
  sed -E 's/(token|api[_-]?key|password|secret)=([^[:space:]]+)/\1=[redacted]/gi; s/("?(token|api[_-]?key|password|secret)"?[[:space:]]*:[[:space:]]*)("[^"]*"|[^,[:space:]]+)/\1[redacted]/gi'
}

show_start_failure() {
  echo "XrayR failed to become active; recent service diagnostics:" >&2
  systemctl status XrayR --no-pager 2>&1 | tail -n 40 | redact_diagnostics >&2 || true
  journalctl -u XrayR.service --no-pager -n 40 2>&1 |
    redact_diagnostics >&2 || true
}

rollback_install() {
  local rollback_ok=1
  if [ "${BINARY_WAS_PRESENT}" -eq 1 ]; then
    cp -p "${BINARY_BACKUP}" "${XRAYR_BINARY}" || rollback_ok=0
  else
    rm -f "${XRAYR_BINARY}" || rollback_ok=0
  fi
  if [ "${CONFIG_WAS_PRESENT}" -eq 1 ]; then
    mkdir -p "$(dirname "${CONFIG_FILE}")"
    cp -p "${CONFIG_BACKUP}" "${CONFIG_FILE}" || rollback_ok=0
  else
    rm -f "${CONFIG_FILE}" || rollback_ok=0
  fi
  if [ "${SERVICE_WAS_PRESENT}" -eq 1 ]; then
    mkdir -p "$(dirname "${SERVICE_FILE}")"
    cp -p "${SERVICE_BACKUP}" "${SERVICE_FILE}" || rollback_ok=0
  else
    rm -f "${SERVICE_FILE}" || rollback_ok=0
  fi
  systemctl daemon-reload || rollback_ok=0
  if [ "${WAS_ACTIVE}" -eq 1 ]; then
    systemctl enable XrayR >/dev/null 2>&1 || rollback_ok=0
    systemctl restart XrayR || rollback_ok=0
    wait_for_active || rollback_ok=0
  fi
  if [ "${rollback_ok}" -eq 1 ]; then
    echo "XrayR update failed; previous files restored and previous service state recovered." >&2
  else
    echo "XrayR update failed; automatic rollback was incomplete. Inspect the service immediately." >&2
  fi
  return 1
}

abort_install() {
  rollback_install || true
  exit 1
}

echo "Downloading and verifying ${ARCH_NAME} package..."
if ! curl -fL --retry 3 --connect-timeout 15 -o "${TMP_DIR}/${ARCHIVE}" "${BASE_URL}/${ARCHIVE}"; then
  echo "Customized XrayR package is unavailable: ${ARCHIVE}" >&2; exit 1
fi
if ! curl -fL --retry 3 --connect-timeout 15 -o "${TMP_DIR}/${MANAGER}" "${BASE_URL}/${MANAGER}"; then
  echo "Customized XrayR manager is unavailable: ${MANAGER}" >&2; exit 1
fi
echo "${SHA256}  ${TMP_DIR}/${ARCHIVE}" | sha256sum -c -
BUILD_INFO="$(tar -xOf "${TMP_DIR}/${ARCHIVE}" usr/local/XrayR/BUILD-INFO)" || { echo "Package is missing BUILD-INFO." >&2; exit 1; }
printf '%s\n' "${BUILD_INFO}" | grep -Fq "Build ID: ${BUILD_ID}" || { echo "Refusing package without build ID ${BUILD_ID}." >&2; exit 1; }

# Everything above this point is validation. Do not stop the old service before it.
if [ -f "${CONFIG_FILE}" ]; then cp -p "${CONFIG_FILE}" "${CONFIG_BACKUP}"; CONFIG_WAS_PRESENT=1; fi
if [ -f "${XRAYR_BINARY}" ]; then cp -p "${XRAYR_BINARY}" "${BINARY_BACKUP}"; BINARY_WAS_PRESENT=1; fi
if [ -f "${SERVICE_FILE}" ]; then cp -p "${SERVICE_FILE}" "${SERVICE_BACKUP}"; SERVICE_WAS_PRESENT=1; fi
if systemctl is-active --quiet XrayR 2>/dev/null; then WAS_ACTIVE=1; fi
if [ "${WAS_ACTIVE}" -eq 1 ]; then systemctl stop XrayR || abort_install; fi

tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "${INSTALL_ROOT}" || abort_install
if [ "${CONFIG_WAS_PRESENT}" -eq 1 ]; then cp -p "${CONFIG_BACKUP}" "${CONFIG_FILE}" || abort_install; fi
chmod +x "${XRAYR_BINARY}" || abort_install
install -m 0755 "${TMP_DIR}/${MANAGER}" "${MANAGER_INSTALL_PATH}" || abort_install
rm -f "${MANAGER_LINK_PATH_1}" "${MANAGER_LINK_PATH_2}" "${MANAGER_LINK_PATH_3}" || abort_install
ln -s "${MANAGER_LINK_TARGET}" "${MANAGER_LINK_PATH_1}" || abort_install
ln -s "${MANAGER_LINK_TARGET}" "${MANAGER_LINK_PATH_2}" || abort_install
ln -s "${MANAGER_LINK_TARGET}" "${MANAGER_LINK_PATH_3}" || abort_install

if ! systemctl daemon-reload || ! systemctl enable XrayR || ! systemctl restart XrayR || ! wait_for_active; then
  show_start_failure
  abort_install
fi

echo "XrayR ${BUILD_ID} installed for ${ARCH_NAME}; service is active and enabled."
echo "Existing configuration was preserved: ${CONFIG_FILE}"
