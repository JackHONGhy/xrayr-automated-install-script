# Customized build verification

This record compares the repository baseline at commit
`291155ca78af25b9a2038351c93204e1dad536f4` with the online-device build.
The source baseline remains XrayR `944e8cd6a8376d6daa86e9e445b8afb8264c0b33`
and xray-core `8deb953aec3c194300150bb57d858819ed2c9966`; neither was upgraded
or replaced.

The final source tree applies, in order:

1. `patches/xray-core-quic-sniff.patch`
   (`53902ba907ce4796fd4de8d66880f847ffb8daec27916b89ce885c3fe81b529d`)
2. `patches/xrayr-newv2board-online-device.patch`
   (`b6bdde269c74514aff497b893d9ba57f68a3137a66374709305f71263b9ed013`)
3. `patches/xrayr-offline-test-gates.patch`
   (`859142d4b59a8b58384150a3e80e893a057dde538a16a3c51e79427cfec78f49`)

The first patch's `maxCryptoDataLength` marker and the second patch's
`Report online devices accepted` marker were both verified in the final source
tree before cross-compiling. The third patch is test-only and gates historical
external integrations without changing runtime code. The package marker changed from
`xrayr-0.9.4-quicfix.1` to `xrayr-0.9.4-quicfix.1-online.1`.

| Architecture | Baseline archive SHA256 | Online build archive SHA256 | Baseline binary SHA256 | Online build binary SHA256 |
| --- | --- | --- | --- | --- |
| amd64 | `b4d7f1994d90978b1d2554f41f65a4faee6fd17ad4a25c21e769ddd3a10d3c60` | `ac6ec12d69c745ad9054b3866b531539781736cb29f12905d615a938f260e580` | `eaed7b7e2ff1e520e8741dcf226d1686e73819ee809b2cba7bd010fcc929932c` | `5bc628d609287aae1b31fb23b18e5bd475f31a2565500e71bdd975532a614ec4` |
| arm64 | `af28b0e703e4b977d1a116c01091383ff867c7ef2b75b640c287bd7851eac91a` | `b2685a9b2c78065830a6e0dabcfb575ff055a6e0e76bb85d5a3b3b54334421a5` | `14567ffd4c60ea6077627bb17b2e2c07c9f571a66dc9736acfe4cfd917722d76` | `b9363fff75f9be734908cf6af01e1db3e6b9c746846ed635a602614cb2604711` |

`cmp` reports that the baseline and online-build amd64 executable differ at
byte 209. The final packages contain Linux x86-64 and Linux ARM aarch64 ELF
executables respectively, and each contains the fixed source revisions plus
all patch digests in `usr/local/XrayR/BUILD-INFO`.
