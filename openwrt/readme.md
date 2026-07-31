# OpenWrt for the Cudy TR3000 v1 — 2026 recipe

Successor-in-spirit to `../legacy/make.tomato/` (Broadcom/Tomato era — nothing
there applies to a MediaTek device; kept only as history). Target: **Cudy
TR3000 v1** travel router. Facts below verified 2026-07 against
downloads.openwrt.org.

## Device

| | |
|---|---|
| SoC | MediaTek **MT7981** (Filogic 820, 2× Cortex-A53) |
| RAM / flash | 512 MB / 128 MB SPI-NAND (a 256 MB flash variant exists) |
| Network | 1× 2.5GbE WAN, 1× 1GbE LAN, WiFi 6 AX3000 2×2, USB 3 |
| OpenWrt target | `mediatek/filogic` |
| Profiles (25.12) | `cudy_tr3000-v1`, `cudy_tr3000-256mb-v1`, `cudy_tr3000-v1-ubootmod` |

Current stable: **OpenWrt 25.12** (latest point release **25.12.5** as of
2026-07). Release images ship with LuCI.

## First-time install (stock → OpenWrt) — one-off, manual

Cudy's stock firmware only accepts RSA-signed images, so the first flash goes
through Cudy's **signed intermediate OpenWrt build**:

1. Check the flash size on the device label (128 vs 256 MB → profile choice).
2. Download the intermediate firmware for TR3000 from Cudy's support page.
3. Flash it via the **stock** web UI (wrong file is rejected, not bricked).
4. The router comes back as barebones OpenWrt on `192.168.1.1` — now flash a
   real image: LuCI → System → Flash Firmware, or `xowrt flash`.

The `-ubootmod` profile replaces the bootloader (usable flash ~45 → ~95 MB) but
requires the `mtd-rw i_want_a_brick=1` dance + TFTP recovery — hard-brick risk,
serial/UART + `mtk_uartboot` is the rescue path. Skip it unless you need the
space. Reference: <https://openwrt.org/toh/cudy/tr3000>.

## Building the sysupgrade image: `xowrt`

Scripted in `~/Claude/bin/xowrt` (snapshot copy in this directory), in the
`xarm`/`xlab`/`xandroid` style. Default route is the official **ImageBuilder** —
prebuilt toolchain + package repo, produces a `…-squashfs-sysupgrade.bin` in
about a minute, no compilation:

```
xowrt fetch                               # ImageBuilder 25.12.5, sha256-verified
xowrt build luci-app-sqm ip-full tcpdump  # extra packages baked into the image
xowrt files                               # optional: files/ overlay (uci-defaults)
xowrt flash                               # scp + sysupgrade over ssh [confirm]
```

Work dir `/mnt/db5/openwrt` (~3 GB). Knobs:
`XOWRT_RELEASE/TARGET/PROFILE/ROUTER/PACKAGES/DIR`. `xowrt flash -n` wipes the
router config instead of keeping it. For the 256 MB unit:
`XOWRT_PROFILE=cudy_tr3000-256mb-v1 xowrt fetch|build|flash`.

When the ImageBuilder is not enough (kernel config, patches): `xowrt src-init`
clones the `v25.12.5` tag, seeds `.config` with the TR3000 profile and runs the
feeds + defconfig; `xowrt src-build` compiles (first run builds the toolchain,
1–2 h; ~30–50 GB).

## Prebuilt alternatives (no build at all)

- **Official firmware selector:** <https://firmware-selector.openwrt.org/> —
  pick 25.12.x → search `TR3000`; can also customize packages server-side (ASU).
- **eko.one.pl** (Cezary Jackiewicz's Polish OpenWrt portal): firmware selector
  at <https://dl.eko.one.pl/firmware/> building from their own snapshots —
  variants `25.12-SNAPSHOT` (no LuCI), `luci-25.12-SNAPSHOT`, plus Gargoyle;
  Polish guides on <https://eko.one.pl/forum/>. Their images track the release
  branch snapshot, not the tagged point release — flash the official build if
  you want reproducibility.

## Links

- Device page: <https://openwrt.org/toh/cudy/tr3000>
- Target downloads: <https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic/>
- ImageBuilder docs: <https://openwrt.org/docs/guide-user/additional-software/imagebuilder>
- Build-from-source docs: <https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem>
- Cudy TR3000 XDA / forum threads: <https://forum.openwrt.org/search?q=tr3000>
