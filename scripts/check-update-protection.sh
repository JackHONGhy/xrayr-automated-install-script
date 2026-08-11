#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT_DIR}/install.sh"
MANAGER="${ROOT_DIR}/xrayr-manager.sh"
BUILD_SCRIPT="${ROOT_DIR}/scripts/build-xrayr.sh"
ONLINE_PATCH="${ROOT_DIR}/patches/xrayr-newv2board-online-device.patch"
TEST_PATCH="${ROOT_DIR}/patches/xrayr-offline-test-gates.patch"
SUMS_FILE="${ROOT_DIR}/SHA256SUMS"
BUILD_ID="xrayr-0.9.4-quicfix.1-online.1"

[[ -f "${INSTALLER}" ]] || { echo "Missing installer: ${INSTALLER}" >&2; exit 1; }
[[ -f "${MANAGER}" ]] || { echo "Missing manager: ${MANAGER}" >&2; exit 1; }
[[ -f "${BUILD_SCRIPT}" ]] || { echo "Missing build script: ${BUILD_SCRIPT}" >&2; exit 1; }
[[ -f "${ONLINE_PATCH}" ]] || { echo "Missing online device patch: ${ONLINE_PATCH}" >&2; exit 1; }
[[ -f "${TEST_PATCH}" ]] || { echo "Missing offline test patch: ${TEST_PATCH}" >&2; exit 1; }
[[ -f "${SUMS_FILE}" ]] || { echo "Missing SHA256SUMS: ${SUMS_FILE}" >&2; exit 1; }

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
for required_marker in BINARY_BACKUP SERVICE_BACKUP rollback_install wait_for_active 'systemctl restart XrayR' 'systemctl is-active --quiet XrayR'; do
  grep -Fq "${required_marker}" "${INSTALLER}" || {
    echo "Installer is missing safe restart marker: ${required_marker}" >&2
    exit 1
  }
done
if grep -Fq 'sleep 2' "${INSTALLER}" || grep -Fq 'sleep 2' "${MANAGER}"; then
  echo "A fixed two-second service success check is still present" >&2
  exit 1
fi
if ! grep -Fq '不支持任意版本号' "${MANAGER}"; then
  echo "Manager does not reject unsupported version arguments" >&2
  exit 1
fi
if ! grep -Fq '未报告更新成功' "${MANAGER}"; then
  echo "Manager may claim update success without an active-service check" >&2
  exit 1
fi
build_id_check_line="$(grep -nF 'Refusing package without build ID' "${INSTALLER}" | head -n1 | cut -d: -f1)"
stop_line="$(grep -nF 'systemctl stop XrayR' "${INSTALLER}" | head -n1 | cut -d: -f1)"
[[ -n "${build_id_check_line}" && -n "${stop_line}" && "${build_id_check_line}" -lt "${stop_line}" ]] || {
  echo "Installer may stop XrayR before Build ID validation" >&2
  exit 1
}
if grep -q $'\r' "${SUMS_FILE}"; then
  echo "SHA256SUMS contains CRLF bytes" >&2
  exit 1
fi
grep -Fqx 'SHA256SUMS text eol=lf' "${ROOT_DIR}/.gitattributes" || {
  echo ".gitattributes does not force LF for SHA256SUMS" >&2
  exit 1
}
for archive in xrayr-0.9.4-linux-amd64-default-config.tar.gz xrayr-0.9.4-linux-arm64-default-config.tar.gz; do
  expected="$(awk -v name="${archive}" '$2 == name { print $1 }' "${SUMS_FILE}")"
  [[ -n "${expected}" ]] && grep -Fq "SHA256=\"${expected}\"" "${INSTALLER}" || {
    echo "Installer checksum for ${archive} differs from SHA256SUMS" >&2
    exit 1
  }
done
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
