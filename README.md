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

The script downloads the matching archive, verifies its SHA-256 digest and
custom build marker before it stops an existing service, then backs up the
binary, `/etc/XrayR/config.yml`, and systemd unit. It reloads, enables, and
restarts `XrayR`, polling `systemctl is-active --quiet XrayR` with a timeout.
If the new service fails, it restores the previous files and attempts to bring
the previous service back. An existing `/etc/XrayR/config.yml` is preserved.

## Package checksums

- amd64: `f771409273e716aa821db42011343d3ac4a2b3465c986073a8dbe081147bcd9b`
- arm64: `31f1499429ae1a587566fd44291c402614faadda1176bdfd9430a1156645998b`

```bash
sha256sum -c SHA256SUMS
```

`SHA256SUMS` is committed as LF-only text. On Linux, verify both its line
endings and package contents with `file SHA256SUMS`, `grep -n $'\r'
SHA256SUMS`, and the checksum command above; the `grep` command must produce
no output.

## Configuration and management

The default configuration remains `/etc/XrayR/config.yml`; this release does
not overwrite a user's configuration during install or update. The manager's
install, update, and self-update paths download only this repository's custom
packages and refuse missing or unmarked packages. `XrayR update x.x.x` is
explicitly rejected: this repository installs only the fixed customized build.

## Rebuild

See [BUILDING.md](BUILDING.md) for the fixed source revisions, all checked-in
patches, Linux build requirements, and reproducible rebuild command. The
release build script is [scripts/build-xrayr.sh](scripts/build-xrayr.sh), and
the update-path check is [scripts/check-update-protection.sh](scripts/check-update-protection.sh).
