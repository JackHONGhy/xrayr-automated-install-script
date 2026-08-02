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
BUILD_ID="xrayr-0.9.4-quicfix.1"
GO_BIN="${GO_BIN:-go}"
BUILD_TIME_UTC="${BUILD_TIME_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

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
[[ -f "${PATCH_FILE}" ]] || { echo "Missing patch: ${PATCH_FILE}" >&2; exit 1; }

mkdir -p "${BUILD_ROOT}/src" "${BUILD_ROOT}/out"
XRAYR_DIR="${BUILD_ROOT}/src/XrayR"
CORE_DIR="${BUILD_ROOT}/src/xray-core"

clone_at_commit() {
  local repo="$1"
  local commit="$2"
  local dir="$3"
  git clone --filter=blob:none --no-checkout "${repo}" "${dir}"
  git -C "${dir}" fetch --depth 1 origin "${commit}"
  git -C "${dir}" checkout --detach FETCH_HEAD
  [[ "$(git -C "${dir}" rev-parse HEAD)" == "${commit}" ]] || {
    echo "Unexpected commit in ${dir}" >&2
    exit 1
  }
}

clone_at_commit "${XRAYR_REPO}" "${XRAYR_COMMIT}" "${XRAYR_DIR}"
clone_at_commit "${CORE_REPO}" "${CORE_COMMIT}" "${CORE_DIR}"
git -C "${CORE_DIR}" apply --whitespace=nowarn "${PATCH_FILE}"

PATCH_SHA256="$(sha256sum "${PATCH_FILE}" | awk '{print $1}')"
GO_VERSION="$("${GO_BIN}" version)"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${XRAYR_DIR}" show -s --format=%ct "${XRAYR_COMMIT}")}"

(
  cd "${XRAYR_DIR}"
  "${GO_BIN}" mod edit -replace="github.com/xtls/xray-core=${CORE_DIR}"
)

build_arch() {
  local arch="$1"
  local archive="${ROOT_DIR}/xrayr-0.9.4-linux-${arch}-default-config.tar.gz"
  local stage="${BUILD_ROOT}/stage-${arch}"
  local binary="${BUILD_ROOT}/XrayR-linux-${arch}"
  local info="${stage}/usr/local/XrayR/BUILD-INFO"

  [[ -f "${archive}" ]] || { echo "Missing baseline archive: ${archive}" >&2; exit 1; }
  mkdir -p "${stage}"
  tar -xzf "${archive}" -C "${stage}"

  (
    cd "${XRAYR_DIR}"
    GOOS=linux GOARCH="${arch}" CGO_ENABLED="${CGO_ENABLED:-0}" \
      "${GO_BIN}" build -trimpath -ldflags='-s -w' -o "${binary}" .
  )

  file "${binary}"
  ldd "${binary}" || true
  install -m 0755 "${binary}" "${stage}/usr/local/XrayR/XrayR"
  cat > "${info}" <<EOF
Build ID: ${BUILD_ID}
XrayR commit: ${XRAYR_COMMIT}
xray-core commit: ${CORE_COMMIT}
Patch SHA256: ${PATCH_SHA256}
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

echo "Built ${BUILD_ID}"
echo "amd64: ${AMD64_SHA256}"
echo "arm64: ${ARM64_SHA256}"
