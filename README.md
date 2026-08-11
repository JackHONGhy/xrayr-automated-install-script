# XrayR automated install script

This repository provides ready-to-install Linux packages for XrayR `v0.9.4`.
It is a packaged runtime repository, not the upstream XrayR source repository.

## QUIC-sniff and online-device fix release

The current packages are `xrayr-0.9.4-quicfix.1-online.1`. They retain XrayR
`v0.9.4` at commit `944e8cd6a8376d6daa86e9e445b8afb8264c0b33` and retain
xray-core `v1.8.20` at commit `8deb953aec3c194300150bb57d858819ed2c9966`.

The packages retain the existing QUIC sniffer's malformed-packet safety checks
and add the independent `patches/xrayr-newv2board-online-device.patch`. The
NewV2board client posts validated, deduplicated online IPs to
`/api/v1/server/UniProxy/alive` and requires the XBoard business response
`{"data":true}`. Device-limit enforcement, routing, panels, inbound and
outbound protocols, configuration formats, and the systemd service remain
unchanged.

Each package contains `usr/local/XrayR/BUILD-INFO` with the release marker,
source revisions, all patch digests, Go version, and build timestamp. The
offline test-gate patch only changes tests and is never part of runtime behavior.

## Supported architectures

- Linux amd64 / x86_64: `xrayr-0.9.4-linux-amd64-default-config.tar.gz`
- Linux arm64 / aarch64: `xrayr-0.9.4-linux-arm64-default-config.tar.gz`

The installer keeps its existing automatic architecture detection and SHA-256
verification. `SHA256SUMS` provides the same two release digests for manual
verification.

## Install

On the target Linux server, run the existing installation command as root:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/JackHONGhy/xrayr-automated-install-script/master/install.sh)
```

The script downloads the matching archive, verifies its SHA-256 digest,
extracts `/usr/local/XrayR` and `/etc/XrayR`, installs `XrayR.service`, and
installs the existing `xrayr` manager command. It refuses packages without the
custom build marker and preserves an existing `/etc/XrayR/config.yml`.

## Package checksums

- amd64: `ac6ec12d69c745ad9054b3866b531539781736cb29f12905d615a938f260e580`
- arm64: `b2685a9b2c78065830a6e0dabcfb575ff055a6e0e76bb85d5a3b3b54334421a5`

```bash
sha256sum -c SHA256SUMS
```

## Configuration and management

The default configuration remains `/etc/XrayR/config.yml`; this release does
not overwrite a user's configuration during install or update. The manager's
install, update, and self-update paths download only this repository's custom
packages and refuse missing or unmarked packages.

## Rebuild

See [BUILDING.md](BUILDING.md) for the fixed source revisions, all checked-in
patches, Linux build requirements, and reproducible rebuild command. The
release build script is [scripts/build-xrayr.sh](scripts/build-xrayr.sh), and
the update-path check is [scripts/check-update-protection.sh](scripts/check-update-protection.sh).
