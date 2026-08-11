#!/usr/bin/env bash
set -euo pipefail

REPO="${XRAYR_REPO:-JackHONGhy/xrayr-automated-install-script}"
BRANCH="${XRAYR_BRANCH:-master}"
MANAGER="xrayr-manager.sh"
BASE_URL="${XRAYR_BASE_URL:-https://raw.githubusercontent.com/${REPO}/${BRANCH}}"
BUILD_ID="xrayr-0.9.4-quicfix.1-online.1"
TMP_DIR="$(mktemp -d)"
CONFIG_FILE="/etc/XrayR/config.yml"
CONFIG_BACKUP="${TMP_DIR}/config.yml"
CONFIG_WAS_PRESENT=0

cleanup() {
	if [ "${CONFIG_WAS_PRESENT}" -eq 1 ] && [ -f "${CONFIG_BACKUP}" ]; then
		cp -p "${CONFIG_BACKUP}" "${CONFIG_FILE}"
	fi
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
    SHA256="ac6ec12d69c745ad9054b3866b531539781736cb29f12905d615a938f260e580"
    ARCH_NAME="linux-amd64"
    ;;
  aarch64|arm64)
    ARCHIVE="xrayr-0.9.4-linux-arm64-default-config.tar.gz"
    SHA256="b2685a9b2c78065830a6e0dabcfb575ff055a6e0e76bb85d5a3b3b54334421a5"
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
need_cmd cp
need_cmd grep
need_cmd systemctl

echo "System architecture detected: ${SYSTEM_ARCH}"
echo "Matched XrayR package architecture: ${ARCH_NAME}"
echo "Selected package: ${ARCHIVE}"
echo "Starting installation for ${ARCH_NAME}..."
echo
echo "Downloading XrayR runtime package..."
if ! curl -fL --retry 3 --connect-timeout 15 \
  -o "${TMP_DIR}/${ARCHIVE}" \
  "${BASE_URL}/${ARCHIVE}"; then
	 echo "Customized XrayR package is unavailable: ${ARCHIVE}" >&2
	 exit 1
fi
if ! curl -fL --retry 3 --connect-timeout 15 \
  -o "${TMP_DIR}/${MANAGER}" \
  "${BASE_URL}/${MANAGER}"; then
	 echo "Customized XrayR manager is unavailable: ${MANAGER}" >&2
	 exit 1
fi

echo "${SHA256}  ${TMP_DIR}/${ARCHIVE}" | sha256sum -c -

if ! BUILD_INFO="$(tar -xOf "${TMP_DIR}/${ARCHIVE}" usr/local/XrayR/BUILD-INFO 2>/dev/null)"; then
	 echo "Customized XrayR package is missing BUILD-INFO: ${ARCHIVE}" >&2
	 exit 1
fi
if ! printf '%s\n' "${BUILD_INFO}" | grep -Fq "Build ID: ${BUILD_ID}"; then
	 echo "Refusing a package without build ID ${BUILD_ID}: ${ARCHIVE}" >&2
	 exit 1
fi

if [ -f "${CONFIG_FILE}" ]; then
	cp -p "${CONFIG_FILE}" "${CONFIG_BACKUP}"
	CONFIG_WAS_PRESENT=1
fi

if systemctl is-active --quiet XrayR 2>/dev/null; then
  echo "Stopping existing XrayR service..."
  systemctl stop XrayR
fi

echo "Installing files..."
tar -xzf "${TMP_DIR}/${ARCHIVE}" -C /
if [ "${CONFIG_WAS_PRESENT}" -eq 1 ]; then
	cp -p "${CONFIG_BACKUP}" "${CONFIG_FILE}"
fi
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
