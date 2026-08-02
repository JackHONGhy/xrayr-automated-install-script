# XrayR automated install script

This repository provides ready-to-install Linux packages for XrayR `v0.9.4`.
It is a packaged runtime repository, not the upstream XrayR source repository.

## QUIC-sniff panic fix release

The current packages are `xrayr-0.9.4-quicfix.1`. They retain XrayR
`v0.9.4` at commit `944e8cd6a8376d6daa86e9e445b8afb8264c0b33` and retain
xray-core `v1.8.20` at commit `8deb953aec3c194300150bb57d858819ed2c9966`.

Only the QUIC sniffer's malformed-packet safety checks were backported. The
packages reject unsafe QUIC lengths and CRYPTO-frame ranges instead of allowing
a malformed Initial packet to panic the process. Routing, panels, inbound and
outbound protocols, configuration formats, the systemd service, and the
manager script are unchanged.

Each package contains `usr/local/XrayR/BUILD-INFO` with the release marker,
source revisions, patch digest, Go version, and build timestamp.

## Supported architectures

- Linux amd64 / x86_64: `xrayr-0.9.4-linux-amd64-default-config.tar.gz`
- Linux arm64 / aarch64: `xrayr-0.9.4-linux-arm64-default-config.tar.gz`

The installer keeps its existing automatic architecture detection and SHA-256
verification.

## Install

On the target Linux server, run the existing installation command as root:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/JackHONGhy/xrayr-automated-install-script/master/install.sh)
```

The script downloads the matching archive, verifies its SHA-256 digest,
extracts `/usr/local/XrayR` and `/etc/XrayR`, installs `XrayR.service`, and
installs the existing `xrayr` manager command.

## Package checksums

- amd64: `b4d7f1994d90978b1d2554f41f65a4faee6fd17ad4a25c21e769ddd3a10d3c60`
- arm64: `af28b0e703e4b977d1a116c01091383ff867c7ef2b75b640c287bd7851eac91a`

## Configuration and management

The default configuration remains `/etc/XrayR/config.yml`; this release does
not overwrite a user's configuration beyond the installer's original behavior.
After configuring the node, use the existing `xrayr` command or normal systemd
commands on that server to manage the service.

## Rebuild

See [BUILDING.md](BUILDING.md) for the fixed source revisions, the checked-in
QUIC patch, Linux build requirements, and reproducible rebuild command. The
release build script is [scripts/build-xrayr.sh](scripts/build-xrayr.sh).
