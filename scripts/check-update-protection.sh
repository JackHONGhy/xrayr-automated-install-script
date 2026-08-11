#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT_DIR}/install.sh"
MANAGER="${ROOT_DIR}/xrayr-manager.sh"
BUILD_SCRIPT="${ROOT_DIR}/scripts/build-xrayr.sh"
ONLINE_PATCH="${ROOT_DIR}/patches/xrayr-newv2board-online-device.patch"
TEST_PATCH="${ROOT_DIR}/patches/xrayr-offline-test-gates.patch"
BUILD_ID="xrayr-0.9.4-quicfix.1-online.1"

[[ -f "${INSTALLER}" ]] || { echo "Missing installer: ${INSTALLER}" >&2; exit 1; }
[[ -f "${MANAGER}" ]] || { echo "Missing manager: ${MANAGER}" >&2; exit 1; }
[[ -f "${BUILD_SCRIPT}" ]] || { echo "Missing build script: ${BUILD_SCRIPT}" >&2; exit 1; }
[[ -f "${ONLINE_PATCH}" ]] || { echo "Missing online device patch: ${ONLINE_PATCH}" >&2; exit 1; }
[[ -f "${TEST_PATCH}" ]] || { echo "Missing offline test patch: ${TEST_PATCH}" >&2; exit 1; }

if grep -nE 'XrayR-project/XrayR-release|raw\.githubusercontent\.com/.*/XrayR\.sh' "${MANAGER}"; then
  echo "Official XrayR update path is still present in the manager" >&2
  exit 1
fi

grep -Fq "${BUILD_ID}" "${INSTALLER}" || {
  echo "Installer does not require the customized build ID" >&2
  exit 1
}
grep -Fq 'sha256sum -c' "${INSTALLER}" || {
  echo "Installer does not verify package SHA256" >&2
  exit 1
}
grep -Fq 'CONFIG_BACKUP' "${INSTALLER}" || {
  echo "Installer does not protect /etc/XrayR/config.yml" >&2
  exit 1
}
grep -Fq "${BUILD_ID}" "${BUILD_SCRIPT}" || {
  echo "Build script does not publish the online-device build ID" >&2
  exit 1
}
grep -Fq 'ONLINE_PATCH_FILE' "${BUILD_SCRIPT}" || {
  echo "Build script does not apply the online-device patch" >&2
  exit 1
}
grep -Fq 'TEST_PATCH_FILE' "${BUILD_SCRIPT}" || {
  echo "Build script does not apply the offline test patch" >&2
  exit 1
}
grep -Fq 'SHA256SUMS' "${BUILD_SCRIPT}" || {
  echo "Build script does not generate SHA256SUMS" >&2
  exit 1
}

echo "Customized install/update path checks passed"
