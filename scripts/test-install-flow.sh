#!/usr/bin/env bash
# Reproducible, non-destructive installer tests. They use a temporary root and
# mocked systemctl/journalctl; no host service or /etc/XrayR path is touched.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="xrayr-0.9.4-linux-amd64-default-config.tar.gz"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xrayr-install-test.XXXXXX")"
MOCK_BIN="${TMP_DIR}/bin"
STATE_DIR="${TMP_DIR}/state"
TEST_ROOT="${TMP_DIR}/root"
OUTPUT="${TMP_DIR}/installer.out"

cleanup() {
  [ "${XRAYR_TEST_KEEP:-0}" = "1" ] || rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${MOCK_BIN}" "${STATE_DIR}"

cat > "${MOCK_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${MOCK_SYSTEMCTL_STATE:?}"
command_name="${1:?}"
shift || true
log() { printf '%s\n' "$1" >> "${state_dir}/calls"; }
state() { cat "${state_dir}/active" 2>/dev/null || printf 'inactive\n'; }
case "${command_name}" in
  is-active)
    [ "$(state)" = active ] && exit 0
    exit 3
    ;;
  stop)
    log stop
    printf 'inactive\n' > "${state_dir}/active"
    ;;
  daemon-reload)
    log daemon-reload
    ;;
  enable)
    log enable
    ;;
  restart)
    log restart
    count_file="${state_dir}/restart-count"
    count=0
    [ -f "${count_file}" ] && count="$(cat "${count_file}")"
    count=$((count + 1))
    printf '%s\n' "${count}" > "${count_file}"
    if [ -f "${state_dir}/fail-first-restart" ] && [ "${count}" -eq 1 ]; then
      printf 'inactive\n' > "${state_dir}/active"
      exit 1
    fi
    printf 'active\n' > "${state_dir}/active"
    ;;
  status)
    printf 'XrayR: failed token=redaction-probe\n'
    ;;
  *)
    printf 'unexpected mocked systemctl command: %s\n' "${command_name}" >&2
    exit 1
    ;;
esac
EOF
cat > "${MOCK_BIN}/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'api_key=redaction-probe password=redaction-probe\n'
EOF
chmod +x "${MOCK_BIN}/systemctl" "${MOCK_BIN}/journalctl"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file_contains() { grep -Fq "$2" "$1" || fail "expected $2 in $1"; }
assert_no_stop() { ! grep -Fxq stop "${STATE_DIR}/calls" 2>/dev/null || fail "old service was stopped before validation"; }
assert_active() { [ "$(cat "${STATE_DIR}/active")" = active ] || fail "service is not active"; }

prepare_existing_install() {
  rm -rf -- "${TEST_ROOT}" "${STATE_DIR}"
  mkdir -p "${TEST_ROOT}/usr/bin" "${TEST_ROOT}/usr/local/bin" "${TEST_ROOT}/usr/local/XrayR" "${TEST_ROOT}/etc/XrayR" "${TEST_ROOT}/etc/systemd/system" "${STATE_DIR}"
  printf 'old-binary\n' > "${TEST_ROOT}/usr/local/XrayR/XrayR"
  printf 'user-config: keep-me\n' > "${TEST_ROOT}/etc/XrayR/config.yml"
  printf '[Service]\nExecStart=/old/XrayR\n' > "${TEST_ROOT}/etc/systemd/system/XrayR.service"
  printf 'active\n' > "${STATE_DIR}/active"
  : > "${STATE_DIR}/calls"
}

run_installer() {
  local installer="$1"
  local base_url="$2"
  if ! PATH="${MOCK_BIN}:${PATH}" \
    MOCK_SYSTEMCTL_STATE="${STATE_DIR}" \
    XRAYR_INSTALLER_TEST_MODE=1 \
    XRAYR_SERVICE_TIMEOUT=2 \
    XRAYR_INSTALL_ROOT="${TEST_ROOT}" \
    XRAYR_MANAGER_INSTALL_PATH="${TEST_ROOT}/usr/bin/XrayR-manager" \
    XRAYR_MANAGER_LINK_TARGET="${TEST_ROOT}/usr/bin/XrayR-manager" \
    XRAYR_MANAGER_LINK_PATH_1="${TEST_ROOT}/usr/bin/xrayr-link" \
    XRAYR_MANAGER_LINK_PATH_2="${TEST_ROOT}/usr/local/bin/xrayr-link-1" \
    XRAYR_MANAGER_LINK_PATH_3="${TEST_ROOT}/usr/local/bin/xrayr-link-2" \
    XRAYR_BASE_URL="${base_url}" \
    bash "${installer}" > "${OUTPUT}" 2>&1; then
    cat "${OUTPUT}" >&2
    return 1
  fi
}

file_url() {
  if command -v cygpath >/dev/null 2>&1; then
    printf 'file:///%s' "$(cygpath -m "$1")"
  else
    printf 'file://%s' "$1"
  fi
}

BASE_URL="$(file_url "${ROOT_DIR}")"

# First installation starts and enables the mocked service.
rm -rf -- "${TEST_ROOT}" "${STATE_DIR}"
mkdir -p "${STATE_DIR}"
mkdir -p "${TEST_ROOT}/usr/bin" "${TEST_ROOT}/usr/local/bin"
printf 'inactive\n' > "${STATE_DIR}/active"
: > "${STATE_DIR}/calls"
run_installer "${ROOT_DIR}/install.sh" "${BASE_URL}"
assert_active
[ -f "${TEST_ROOT}/etc/XrayR/config.yml" ] || fail "first install did not create config"
assert_file_contains "${STATE_DIR}/calls" restart

# A normal update preserves the operator's configuration and leaves service active.
prepare_existing_install
config_sha_before="$(sha256sum "${TEST_ROOT}/etc/XrayR/config.yml" | awk '{print $1}')"
run_installer "${ROOT_DIR}/install.sh" "${BASE_URL}"
assert_active
[ "${config_sha_before}" = "$(sha256sum "${TEST_ROOT}/etc/XrayR/config.yml" | awk '{print $1}')" ] || fail "config changed during update"
assert_file_contains "${STATE_DIR}/calls" stop
assert_file_contains "${STATE_DIR}/calls" restart
tar -xOf "${ROOT_DIR}/${ARCHIVE}" usr/local/XrayR/BUILD-INFO | grep -Fq 'Build ID: xrayr-0.9.4-quicfix.1-online.1' || fail "target build ID missing"

# A bad archive digest never stops an active old service.
prepare_existing_install
bad_hash_dir="${TMP_DIR}/bad-hash"
mkdir -p "${bad_hash_dir}"
cp "${ROOT_DIR}/${ARCHIVE}" "${bad_hash_dir}/${ARCHIVE}"
cp "${ROOT_DIR}/xrayr-manager.sh" "${bad_hash_dir}/xrayr-manager.sh"
printf x >> "${bad_hash_dir}/${ARCHIVE}"
if run_installer "${ROOT_DIR}/install.sh" "$(file_url "${bad_hash_dir}")"; then fail "bad digest unexpectedly installed"; fi
assert_no_stop
assert_active

# A Build ID mismatch is rejected before stopping the old service.
prepare_existing_install
bad_id_installer="${TMP_DIR}/bad-id-install.sh"
sed 's/BUILD_ID="xrayr-0.9.4-quicfix.1-online.1"/BUILD_ID="wrong-build-id"/' "${ROOT_DIR}/install.sh" > "${bad_id_installer}"
if run_installer "${bad_id_installer}" "${BASE_URL}"; then fail "bad build ID unexpectedly installed"; fi
assert_no_stop
assert_active

# A failed restart restores binary/config/service and recovers the old active service.
prepare_existing_install
old_binary_sha="$(sha256sum "${TEST_ROOT}/usr/local/XrayR/XrayR" | awk '{print $1}')"
old_config_sha="$(sha256sum "${TEST_ROOT}/etc/XrayR/config.yml" | awk '{print $1}')"
old_service_sha="$(sha256sum "${TEST_ROOT}/etc/systemd/system/XrayR.service" | awk '{print $1}')"
touch "${STATE_DIR}/fail-first-restart"
if run_installer "${ROOT_DIR}/install.sh" "${BASE_URL}"; then fail "restart failure unexpectedly succeeded"; fi
assert_active
[ "${old_binary_sha}" = "$(sha256sum "${TEST_ROOT}/usr/local/XrayR/XrayR" | awk '{print $1}')" ] || fail "old binary was not restored"
[ "${old_config_sha}" = "$(sha256sum "${TEST_ROOT}/etc/XrayR/config.yml" | awk '{print $1}')" ] || fail "old config was not restored"
[ "${old_service_sha}" = "$(sha256sum "${TEST_ROOT}/etc/systemd/system/XrayR.service" | awk '{print $1}')" ] || fail "old systemd unit was not restored"
assert_file_contains "${STATE_DIR}/calls" restart
! grep -Fq redaction-probe "${OUTPUT}" || fail "failure output leaked a mock value"

# The manager must only claim success after it has an active-service guard.
grep -Fq '未报告更新成功' "${ROOT_DIR}/xrayr-manager.sh" || fail "manager lacks active-service success guard"
! grep -Fq 'sleep 2' "${ROOT_DIR}/xrayr-manager.sh" || fail "manager still uses fixed sleep checks"

printf 'Installer flow tests passed: first install, update, validation failures, rollback, and manager guard.\n'
