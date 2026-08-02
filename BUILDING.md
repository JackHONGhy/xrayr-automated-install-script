# Building the XrayR 0.9.4 QUIC-sniff fix

This repository publishes XrayR `0.9.4` packages with a narrowly scoped patch to
the bundled xray-core QUIC sniffer. It does not upgrade xray-core.

Fixed source revisions:

- XrayR: `944e8cd6a8376d6daa86e9e445b8afb8264c0b33`
- xray-core: `8deb953aec3c194300150bb57d858819ed2c9966` (`v1.8.20`)
- Patch marker: `xrayr-0.9.4-quicfix.1`

The patch is based on the safety changes in these official commits:

- `1ffb8a92cd38c7ee2e8909f5dec6f5832d3bf520` — panic recovery in the QUIC sniffer.
- `d9ebb9b2dc1fd41a013eb4006522234e5c4326e1` — bounded crypto buffering and safe header sampling.
- `ef1c165cc595aa122d284eb92547c9f5dab513fb` — reject impossible/short packet lengths.
- `e5a9fb752e0dcc127dd1740316c853571c16052f` — short varints for length-related fields.
- `8f15190c230fe6975c9b18e31316c6bc494f3863` — validate encrypted-header sampling length.

The `d9ebb9b2dc` refactor introduced newer buffer ownership APIs that are not
present in v1.8.20. `patches/xray-core-quic-sniff.patch` therefore keeps the
v1.8.20 API and implements equivalent safety with the existing `bytespool` and
explicit bounds. The later dispatcher change is not copied into XrayR's
`app/mydispatcher`: XrayR 0.9.4 uses the older fixed-size `buf.Size` cache path.

## Rebuild

Run on a Linux build host (or WSL) with official Go, Git, GNU tar, `sha256sum`,
`file`, `ldd`, `install`, `sed`, and Bash available:

```bash
BUILD_TIME_UTC=2026-08-02T00:00:00Z \
SOURCE_DATE_EPOCH=1754092800 \
bash scripts/build-xrayr.sh
```

The script clones the two fixed commits, verifies their commit IDs, applies the
checked-in patch, adds a temporary local `replace` for the patched xray-core,
cross-builds Linux `amd64` and `arm64`, and replaces only the binary in the
existing package layouts. It adds `usr/local/XrayR/BUILD-INFO` containing the
build ID, source revisions, Go version, patch SHA256, and build timestamp. The
original configuration, database/geo files, systemd unit, manager script, and
archive filenames are retained. It also updates the two package SHA256 values
in `install.sh`.

Set `KEEP_BUILD_ROOT=1` to retain temporary cloned sources for inspection.
Set `GO_BIN=/path/to/go` to select a specific official Go toolchain.

## Verification

Before publishing, run from the XrayR source checkout with the same patched
local replacement used by the build script:

```bash
go test ./common/protocol/quic
go test ./app/mydispatcher
go test ./...
go test -fuzz=FuzzSniffQUIC -fuzztime=30s ./common/protocol/quic
go vet ./...
git diff --check
```

The repository's historical `service/controller/TestController` waits for an
OS signal indefinitely; if an unfiltered `go test ./...` reaches that test, its
timeout must be reported rather than described as a pass. The focused tests and
fuzz target must pass before package publication.
