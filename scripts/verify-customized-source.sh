#!/usr/bin/env bash
set -euo pipefail

# Verify the exact pinned upstream trees after every repository patch has been
# applied.  This script is intentionally read-only with respect to the release
# repository: all source trees live under a temporary directory.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XRAYR_COMMIT="944e8cd6a8376d6daa86e9e445b8afb8264c0b33"
CORE_COMMIT="8deb953aec3c194300150bb57d858819ed2c9966"
BUILD_ROOT="${BUILD_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/xrayr-source-verify.XXXXXX")}"
KEEP_BUILD_ROOT="${KEEP_BUILD_ROOT:-0}"
GO_BIN="${GO_BIN:-go}"

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

for cmd in git mktemp grep sed "${GO_BIN}" "${GOFMT_BIN}"; do
  need_cmd "${cmd}"
done

clone_at_commit() {
  local url="$1"
  local commit="$2"
  local dir="$3"

  git init -q "${dir}"
  git -C "${dir}" config core.autocrlf false
  git -C "${dir}" remote add origin "${url}"
  git -C "${dir}" fetch --depth 1 origin "${commit}"
  git -C "${dir}" checkout --detach -q FETCH_HEAD
  [[ "$(git -C "${dir}" rev-parse HEAD)" == "${commit}" ]] || {
    echo "Pinned source checkout mismatch: ${url}" >&2
    exit 1
  }
}

normalize_patch() {
  local patch="$1"
  local normalized="${BUILD_ROOT}/$(basename "${patch}").lf"
  sed 's/\r$//' "${patch}" > "${normalized}"
  printf '%s\n' "${normalized}"
}

mkdir -p "${BUILD_ROOT}/src"
XRAYR_DIR="${BUILD_ROOT}/src/XrayR"
CORE_DIR="${BUILD_ROOT}/src/xray-core"

clone_at_commit "https://github.com/XrayR-project/XrayR.git" "${XRAYR_COMMIT}" "${XRAYR_DIR}"
clone_at_commit "https://github.com/XTLS/Xray-core.git" "${CORE_COMMIT}" "${CORE_DIR}"

CORE_PATCH="$(normalize_patch "${ROOT_DIR}/patches/xray-core-quic-sniff.patch")"
ONLINE_PATCH="$(normalize_patch "${ROOT_DIR}/patches/xrayr-newv2board-online-device.patch")"
TEST_PATCH="$(normalize_patch "${ROOT_DIR}/patches/xrayr-offline-test-gates.patch")"

git -C "${CORE_DIR}" apply --check "${CORE_PATCH}"
git -C "${CORE_DIR}" apply --whitespace=nowarn "${CORE_PATCH}"
git -C "${XRAYR_DIR}" apply --check "${ONLINE_PATCH}"
git -C "${XRAYR_DIR}" apply --whitespace=nowarn "${ONLINE_PATCH}"
git -C "${XRAYR_DIR}" apply --check "${TEST_PATCH}"
git -C "${XRAYR_DIR}" apply --whitespace=nowarn "${TEST_PATCH}"

echo "Checking gofmt and patch-chain whitespace"
gofmt_files=(
  "${CORE_DIR}/common/protocol/quic/sniff.go"
  "${CORE_DIR}/common/protocol/quic/sniff_test.go"
  "${XRAYR_DIR}/api/newV2board/v2board.go"
  "${XRAYR_DIR}/api/newV2board/v2board_test.go"
  "${XRAYR_DIR}/api/newV2board/v2board_online_test.go"
  "${XRAYR_DIR}/api/bunpanel/bunpanel_test.go"
  "${XRAYR_DIR}/api/gov2panel/gov2panel_test.go"
  "${XRAYR_DIR}/api/pmpanel/pmpanel_test.go"
  "${XRAYR_DIR}/api/proxypanel/proypanel_test.go"
  "${XRAYR_DIR}/api/sspanel/sspanel_test.go"
  "${XRAYR_DIR}/api/v2raysocks/v2raysocks_test.go"
  "${XRAYR_DIR}/common/mylego/lego_test.go"
  "${XRAYR_DIR}/service/controller/controller_test.go"
  "${XRAYR_DIR}/service/controller/inboundbuilder_test.go"
)
"${GOFMT_BIN}" -w "${gofmt_files[@]}"
gofmt_diff="$("${GOFMT_BIN}" -d "${gofmt_files[@]}")"
[[ -z "${gofmt_diff}" ]] || {
  echo "gofmt check failed" >&2
  printf '%s\n' "${gofmt_diff}" >&2
  exit 1
}

git -C "${CORE_DIR}" diff --check
git -C "${XRAYR_DIR}" diff --check
grep -Fq "maxCryptoDataLength" "${CORE_DIR}/common/protocol/quic/sniff.go"
grep -Fq "Report online devices accepted" "${XRAYR_DIR}/api/newV2board/v2board.go"
grep -Fq "XRAYR_RUN_PANEL_INTEGRATION" "${XRAYR_DIR}/api/sspanel/sspanel_test.go"

(
  cd "${XRAYR_DIR}"
  "${GO_BIN}" mod edit -replace="github.com/xtls/xray-core=../xray-core"
  echo "Running NewV2board offline unit tests and vet"
  "${GO_BIN}" test -count=1 ./api/newV2board/...
  "${GO_BIN}" vet -structtag=false ./api/newV2board/...
  # Verbose output makes each opt-in external integration skip and its reason
  # visible while offline unit tests continue to run.
  echo "Listing opt-in integration skips and offline unit-test results"
  "${GO_BIN}" test -v -count=1 \
    ./api/bunpanel ./api/gov2panel ./api/pmpanel ./api/proxypanel \
    ./api/sspanel ./api/v2raysocks ./common/mylego ./service/controller
  echo "Running full offline XrayR test suite"
  "${GO_BIN}" test -count=1 -timeout=120s ./...
  if command -v gcc >/dev/null 2>&1; then
    echo "Running NewV2board race test"
    CGO_ENABLED=1 "${GO_BIN}" test -race -count=1 ./api/newV2board/...
  else
    echo "SKIP race test: gcc is unavailable" >&2
  fi
  mkdir -p "${BUILD_ROOT}/out"
  echo "Building Linux amd64 and arm64 binaries"
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 "${GO_BIN}" build -trimpath -ldflags='-s -w' \
    -o "${BUILD_ROOT}/out/XrayR-linux-amd64" .
  GOOS=linux GOARCH=arm64 CGO_ENABLED=0 "${GO_BIN}" build -trimpath -ldflags='-s -w' \
    -o "${BUILD_ROOT}/out/XrayR-linux-arm64" .
)

(
  cd "${CORE_DIR}"
  echo "Running patched QUIC unit tests and vet"
  "${GO_BIN}" test -count=1 ./common/protocol/quic
  "${GO_BIN}" vet ./common/protocol/quic
)

file "${BUILD_ROOT}/out/XrayR-linux-amd64"
file "${BUILD_ROOT}/out/XrayR-linux-arm64"

echo "Customized source verification passed"
