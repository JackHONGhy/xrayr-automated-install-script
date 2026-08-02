#!/usr/bin/env bash
set -euo pipefail

REPO="${XRAYR_REPO:-JackHONGhy/xrayr-automated-install-script}"
BRANCH="${XRAYR_BRANCH:-master}"
MANAGER="xrayr-manager.sh"
BASE_URL="${XRAYR_BASE_URL:-https://raw.githubusercontent.com/${REPO}/${BRANCH}}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
  echo "This installer must be run as root." >&2
  exit 1
fi

SYSTEM_ARCH="$(uname -m)"

case "${SYSTEM_ARCH}" in
  x86_64|amd64)
    ARCHIVE="xrayr-0.9.4-linux-amd64-default-config.tar.gz"
    SHA256="b4d7f1994d90978b1d2554f41f65a4faee6fd17ad4a25c21e769ddd3a10d3c60"
    ARCH_NAME="linux-amd64"
    ;;
  aarch64|arm64)
    ARCHIVE="xrayr-0.9.4-linux-arm64-default-config.tar.gz"
    SHA256="af28b0e703e4b977d1a116c01091383ff867c7ef2b75b640c287bd7851eac91a"
    ARCH_NAME="linux-arm64"
    ;;
  *)
    echo "Unsupported architecture: ${SYSTEM_ARCH}" >&2
    echo "Supported architectures: x86_64/amd64, aarch64/arm64" >&2
    exit 1
    ;;
esac

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd tar
need_cmd sha256sum
need_cmd systemctl

echo "System architecture detected: ${SYSTEM_ARCH}"
echo "Matched XrayR package architecture: ${ARCH_NAME}"
echo "Selected package: ${ARCHIVE}"
echo "Starting installation for ${ARCH_NAME}..."
echo
echo "Downloading XrayR runtime package..."
curl -fL --retry 3 --connect-timeout 15 \
  -o "${TMP_DIR}/${ARCHIVE}" \
  "${BASE_URL}/${ARCHIVE}"
curl -fL --retry 3 --connect-timeout 15 \
  -o "${TMP_DIR}/${MANAGER}" \
  "${BASE_URL}/${MANAGER}"

echo "${SHA256}  ${TMP_DIR}/${ARCHIVE}" | sha256sum -c -

if systemctl is-active --quiet XrayR 2>/dev/null; then
  echo "Stopping existing XrayR service..."
  systemctl stop XrayR
fi

echo "Installing files..."
tar -xzf "${TMP_DIR}/${ARCHIVE}" -C /
chmod +x /usr/local/XrayR/XrayR
install -m 0755 "${TMP_DIR}/${MANAGER}" /usr/bin/XrayR
ln -sf /usr/bin/XrayR /usr/bin/xrayr
ln -sf /usr/bin/XrayR /usr/local/bin/XrayR
ln -sf /usr/bin/XrayR /usr/local/bin/xrayr

systemctl daemon-reload
systemctl enable XrayR

echo
echo "XrayR installed for ${ARCH_NAME}."
echo "Edit /etc/XrayR/config.yml before starting the service:"
echo "  nano /etc/XrayR/config.yml"
echo
echo "Then start it with:"
echo "  systemctl start XrayR"
