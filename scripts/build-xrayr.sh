#!/usr/bin/env bash
set -euo pipefail

# Reproducible XrayR 0.9.4 QUIC-sniffer build.
# This script only builds local artifacts; it never contacts a runtime server.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/xrayr-quicfix.XXXXXX")}"
KEEP_BUILD_ROOT="${KEEP_BUILD_ROOT:-0}"
XRAYR_REPO="${XRAYR_REPO:-https://github.com/XrayR-project/XrayR.git}"
XRAYR_COMMIT="944e8cd6a8376d6daa86e9e445b8afb8264c0b33"
CORE_REPO="${CORE_REPO:-https://github.com/XTLS/Xray-core.git}"
CORE_COMMIT="8deb953aec3c194300150bb57d858819ed2c9966"
PATCH_FILE="${ROOT_DIR}/patches/xray-core-quic-sniff.patch"
ONLINE_PATCH_FILE="${ROOT_DIR}/patches/xrayr-newv2board-online-device.patch"
TEST_PATCH_FILE="${ROOT_DIR}/patches/xrayr-offline-test-gates.patch"
BUILD_ID="xrayr-0.9.4-quicfix.1-online.1"
GO_BIN="${GO_BIN:-go}"
BUILD_TIME_UTC="${BUILD_TIME_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

if [[ "${GO_BIN}" == */* ]]; then
  GOFMT_BIN="${GOFMT_BIN:-$(dirname "${GO_BIN}")/gofmt}"
else
  GOFMT_BIN="${GOFMT_BIN:-gofmt}"
fi

cleanup() {
  if [[ "${KEEP_BUILD_ROOT}" != "1" && -d "${BUILD_ROOT}" ]]; then
    rm -rf -- "${BUILD_ROOT}"
  fi
}
trap cleanup EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

for cmd in git tar sha256sum file ldd install sed date; do
  need_cmd "$cmd"
done
"${GO_BIN}" version >/dev/null
"${GOFMT_BIN}" -h >/dev/null 2>&1
[[ -f "${PATCH_FILE}" ]] || { echo "Missing patch: ${PATCH_FILE}" >&2; exit 1; }
[[ -f "${ONLINE_PATCH_FILE}" ]] || { echo "Missing online device patch: ${ONLINE_PATCH_FILE}" >&2; exit 1; }
[[ -f "${TEST_PATCH_FILE}" ]] || { echo "Missing offline test patch: ${TEST_PATCH_FILE}" >&2; exit 1; }
bash "${ROOT_DIR}/scripts/check-update-protection.sh"

mkdir -p "${BUILD_ROOT}/src" "${BUILD_ROOT}/out"
XRAYR_DIR="${BUILD_ROOT}/src/XrayR"
CORE_DIR="${BUILD_ROOT}/src/xray-core"

clone_at_commit() {
  local repo="$1"
  local commit="$2"
  local dir="$3"
  local repo_dir
  local actual_commit
  # A local mirror is used for offline/reproducible builds.  It must already
  # contain the exact pinned commit; no implicit network fetch is allowed.
  if [[ -d "${repo}/.git" || -f "${repo}/HEAD" ]]; then
    repo_dir="$(cd "${repo}" && pwd)"
    actual_commit="$(git -c safe.directory="${repo_dir}" -C "${repo_dir}" rev-parse "${commit}^{commit}")" || {
      echo "Local source mirror does not contain ${commit}: ${repo}" >&2
      exit 1
    }
    [[ "${actual_commit}" == "${commit}" ]] || {
      echo "Unexpected commit in local source mirror ${repo}" >&2
      exit 1
    }
    mkdir -p "${dir}"
    git -c safe.directory="${repo_dir}" -C "${repo_dir}" archive --format=tar "${commit}" | tar -xf - -C "${dir}"
    # Keep the extracted tree usable by git apply/diff without fabricating a
    # commit that could be mistaken for the pinned upstream revision.
    git init -q "${dir}"
    git -C "${dir}" add -A
  else
    git clone --filter=blob:none --no-checkout "${repo}" "${dir}"
    git -C "${dir}" fetch --depth 1 origin "${commit}"
    git -C "${dir}" checkout --detach FETCH_HEAD
    actual_commit="$(git -C "${dir}" rev-parse HEAD)"
  fi
  [[ "${actual_commit}" == "${commit}" ]] || {
    echo "Unexpected commit in ${dir}" >&2
    exit 1
  }
}

clone_at_commit "${XRAYR_REPO}" "${XRAYR_COMMIT}" "${XRAYR_DIR}"
clone_at_commit "${CORE_REPO}" "${CORE_COMMIT}" "${CORE_DIR}"
# Apply the existing custom xray-core patch first, then the online-device
# patch to the final XrayR source tree. Never build an unpatched upstream tree.
git -C "${CORE_DIR}" apply --whitespace=nowarn "${PATCH_FILE}"
git -C "${XRAYR_DIR}" apply --whitespace=nowarn "${ONLINE_PATCH_FILE}"
git -C "${XRAYR_DIR}" apply --whitespace=nowarn "${TEST_PATCH_FILE}"

"${GOFMT_BIN}" -w \
  "${CORE_DIR}/common/protocol/quic/sniff.go" \
  "${CORE_DIR}/common/protocol/quic/sniff_test.go" \
  "${XRAYR_DIR}/api/newV2board/v2board.go" \
  "${XRAYR_DIR}/api/newV2board/v2board_test.go" \
  "${XRAYR_DIR}/api/newV2board/v2board_online_test.go" \
  "${XRAYR_DIR}/api/bunpanel/bunpanel_test.go" \
  "${XRAYR_DIR}/api/gov2panel/gov2panel_test.go" \
  "${XRAYR_DIR}/api/pmpanel/pmpanel_test.go" \
  "${XRAYR_DIR}/api/proxypanel/proypanel_test.go" \
  "${XRAYR_DIR}/api/sspanel/sspanel_test.go" \
  "${XRAYR_DIR}/api/v2raysocks/v2raysocks_test.go" \
  "${XRAYR_DIR}/common/mylego/lego_test.go" \
  "${XRAYR_DIR}/service/controller/controller_test.go" \
  "${XRAYR_DIR}/service/controller/inboundbuilder_test.go"
git -C "${CORE_DIR}" diff --check
git -C "${XRAYR_DIR}" diff --check
grep -Fq "maxCryptoDataLength" "${CORE_DIR}/common/protocol/quic/sniff.go" || {
  echo "Existing QUIC sniff patch is missing from the final source tree" >&2
  exit 1
}
grep -Fq "Report online devices accepted" "${XRAYR_DIR}/api/newV2board/v2board.go" || {
  echo "Online device patch is missing from the final source tree" >&2
  exit 1
}
grep -Fq "XRAYR_RUN_PANEL_INTEGRATION" "${XRAYR_DIR}/api/sspanel/sspanel_test.go" || {
  echo "Offline test gate patch is missing from the final source tree" >&2
  exit 1
}

PATCH_SHA256="$(sed 's/\r$//' "${PATCH_FILE}" | sha256sum | awk '{print $1}')"
ONLINE_PATCH_SHA256="$(sed 's/\r$//' "${ONLINE_PATCH_FILE}" | sha256sum | awk '{print $1}')"
TEST_PATCH_SHA256="$(sed 's/\r$//' "${TEST_PATCH_FILE}" | sha256sum | awk '{print $1}')"
GO_VERSION="$("${GO_BIN}" version)"
if [[ -d "${XRAYR_REPO}/.git" || -f "${XRAYR_REPO}/HEAD" ]]; then
  XRAYR_SOURCE_DIR="$(cd "${XRAYR_REPO}" && pwd)"
  SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -c safe.directory="${XRAYR_SOURCE_DIR}" -C "${XRAYR_SOURCE_DIR}" show -s --format=%ct "${XRAYR_COMMIT}")}"
else
  SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${XRAYR_DIR}" show -s --format=%ct "${XRAYR_COMMIT}")}"
fi

(
  cd "${XRAYR_DIR}"
  # XRAYR_DIR and CORE_DIR may be relative to ROOT_DIR.  The replacement is
  # therefore expressed relative to the module directory, not the caller's
  # working directory.
  "${GO_BIN}" mod edit -replace="github.com/xtls/xray-core=../xray-core"
)

build_arch() {
  local arch="$1"
  local archive="${ROOT_DIR}/xrayr-0.9.4-linux-${arch}-default-config.tar.gz"
  local stage="${BUILD_ROOT}/stage-${arch}"
  local binary="${BUILD_ROOT}/XrayR-linux-${arch}"
  local binary_from_source="../../XrayR-linux-${arch}"
  local info="${stage}/usr/local/XrayR/BUILD-INFO"

  [[ -f "${archive}" ]] || { echo "Missing baseline archive: ${archive}" >&2; exit 1; }
  mkdir -p "${stage}"
  tar -xzf "${archive}" -C "${stage}"

  (
    cd "${XRAYR_DIR}"
    GOOS=linux GOARCH="${arch}" CGO_ENABLED="${CGO_ENABLED:-0}" \
      "${GO_BIN}" build -trimpath -ldflags='-s -w' -o "${binary_from_source}" .
  )

  file "${binary}"
  ldd "${binary}" || true
  install -m 0755 "${binary}" "${stage}/usr/local/XrayR/XrayR"
  cat > "${info}" <<EOF
Build ID: ${BUILD_ID}
XrayR commit: ${XRAYR_COMMIT}
xray-core commit: ${CORE_COMMIT}
Patch SHA256: ${PATCH_SHA256}
Online patch SHA256: ${ONLINE_PATCH_SHA256}
Offline test patch SHA256: ${TEST_PATCH_SHA256}
${GO_VERSION}
Build time UTC: ${BUILD_TIME_UTC}
SOURCE_DATE_EPOCH: ${SOURCE_DATE_EPOCH}
EOF
  chmod 0644 "${info}"

  tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner \
    -czf "${archive}.new" -C "${stage}" etc usr
  mv -- "${archive}.new" "${archive}"
  sha256sum "${archive}"
  tar -tzf "${archive}" >/dev/null
}

build_arch amd64
build_arch arm64

AMD64_SHA256="$(sha256sum "${ROOT_DIR}/xrayr-0.9.4-linux-amd64-default-config.tar.gz" | awk '{print $1}')"
ARM64_SHA256="$(sha256sum "${ROOT_DIR}/xrayr-0.9.4-linux-arm64-default-config.tar.gz" | awk '{print $1}')"

# Keep install.sh's existing architecture detection and commands; only replace
# the two package digests immediately following their archive selections.
sed -i -E \
  "/xrayr-0\\.9\\.4-linux-amd64-default-config\\.tar\\.gz/{n;s/(SHA256=\")[0-9a-f]+/\\1${AMD64_SHA256}/;}" \
  "${ROOT_DIR}/install.sh"
sed -i -E \
  "/xrayr-0\\.9\\.4-linux-arm64-default-config\\.tar\\.gz/{n;s/(SHA256=\")[0-9a-f]+/\\1${ARM64_SHA256}/;}" \
  "${ROOT_DIR}/install.sh"

grep -Fq "SHA256=\"${AMD64_SHA256}\"" "${ROOT_DIR}/install.sh" || {
  echo "Failed to update the amd64 installer checksum" >&2
  exit 1
}
grep -Fq "SHA256=\"${ARM64_SHA256}\"" "${ROOT_DIR}/install.sh" || {
  echo "Failed to update the arm64 installer checksum" >&2
  exit 1
}

{
  printf '%s  %s\n' "${AMD64_SHA256}" "xrayr-0.9.4-linux-amd64-default-config.tar.gz"
  printf '%s  %s\n' "${ARM64_SHA256}" "xrayr-0.9.4-linux-arm64-default-config.tar.gz"
} > "${ROOT_DIR}/SHA256SUMS"
(
  cd "${ROOT_DIR}"
  sha256sum -c SHA256SUMS
)

echo "Built ${BUILD_ID}"
echo "amd64: ${AMD64_SHA256}"
echo "arm64: ${ARM64_SHA256}"
