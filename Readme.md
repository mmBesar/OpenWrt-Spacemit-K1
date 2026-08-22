<div align="center">

# OpenWrt-Spacemit-K1

**Personal OpenWrt build pipeline for the OrangePi R2S and OrangePi RV2**
(SpacemiT K1 / RISC-V), built from an unmerged upstream PR.

[![Build](https://img.shields.io/github/actions/workflow/status/mmBesar/OpenWrt-Spacemit-K1/build-openwrt-spacemit-k1.yml?label=build&logo=githubactions&logoColor=white)](https://github.com/mmBesar/OpenWrt-Spacemit-K1/actions)
[![Release](https://img.shields.io/github/v/release/mmBesar/OpenWrt-Spacemit-K1?label=latest%20release&logo=github)](https://github.com/mmBesar/OpenWrt-Spacemit-K1/releases/latest)
[![Target](https://img.shields.io/badge/target-spacemit%2Fk1-blue?logo=riscv&logoColor=white)](https://github.com/openwrt/openwrt/pull/23231)
[![Source PR](https://img.shields.io/badge/upstream-PR%20%2323231-orange?logo=github)](https://github.com/openwrt/openwrt/pull/23231)
[![Status](https://img.shields.io/badge/status-unmerged%20%2F%20unofficial-red)](#-disclaimer)
[![Use](https://img.shields.io/badge/use-personal-lightgrey)](#-disclaimer)

</div>

---

> [!WARNING]
> This builds from **[openwrt/openwrt PR #23231](https://github.com/openwrt/openwrt/pull/23231)** (`dhewg:spacemit`), which is **not merged** and still actively force-pushed upstream. Every release here is a personal testing build — not production firmware. See [Disclaimer](#-disclaimer).

## Contents

- [What this is](#what-this-is)
- [Quick start](#-quick-start)
- [Which file do I flash?](#-which-file-do-i-flash)
- [Installing](#-installing)
- [First steps after flashing](#-first-steps-after-flashing)
- [Known caveats](#-known-caveats)
- [Disclaimer](#-disclaimer)

## What this is

This repo holds **no OpenWrt source** — just a GitHub Actions workflow that checks out PR #23231 fresh, cross-compiles it, and publishes the images as a GitHub Release each run. Both the R2S and RV2 are covered by the **same `generic` device image**: a multi-DTB FIT file that u-boot auto-matches to whichever board it's booted on, so there's nothing board-specific to pick at download time.

## 🚀 Quick start

```text
1. Actions tab → Run workflow → wait for it to finish
2. Releases page → download the *-sdcard.img.gz
3. zcat file.img.gz | sudo dd of=/dev/<SD_DEVICE> bs=4M conv=fsync status=progress
4. Insert SD card into R2S or RV2 → power on
5. ssh root@192.168.1.1   (no password on first boot)
```

Full detail on each step below.

## 📦 Which file do I flash?

One build run produces all of these — pick based on **how**, not **which board**:

| File | Use this when... |
|---|---|
| `*-sdcard.img.gz` | You want the simplest, fully-reversible option. **Start here.** |
| `*-emmc.img.gz` | You've tested via SD and want a persistent install on eMMC. |
| `*-other.img.gz` | Same, but installing to NVMe/USB instead of eMMC. |
| `*-initramfs.itb` | RAM-only test boot over USB fastboot — nothing touches the board's storage. |
| `u-boot-spacemit_k1.tar.gz` | Contains the bootloader plus `update-bootloader.sh` / `bootstrap.sh` helper scripts, needed for the eMMC/USB/fastboot paths. |

## 💽 Installing

<details>
<summary><strong>Option A — SD card (start here)</strong></summary>

```sh
zcat openwrt-spacemit-k1-generic-*-sdcard.img.gz | \
  sudo dd of=/dev/<SD_DEVICE> bs=4M conv=fsync status=progress
```

Insert and power on — the board boots entirely from the card, nothing on the board itself is touched. Safest way to test any build.

</details>

<details>
<summary><strong>Option B — eMMC / NVMe / USB (persistent)</strong></summary>

The boot ROM can only load the first-stage bootloader from SD, NOR, or eMMC's boot partition — never straight from USB/NVMe. So the bootloader has to land on NOR/eMMC first, even if the rootfs itself ends up on USB/NVMe.

**Recommended path:**
1. Boot the SD card (Option A) and confirm it works.
2. From that shell, run `update-bootloader.sh` (from `u-boot-spacemit_k1.tar.gz`) to write the bootloader to NOR/eMMC.
3. Flash the target rootfs:
   ```sh
   sudo dd if=openwrt-spacemit-k1-generic-*-emmc.img of=/dev/<EMMC_DEVICE> bs=4M conv=fsync status=progress
   # or NVMe/USB:
   sudo dd if=openwrt-spacemit-k1-generic-*-other.img of=/dev/<TARGET_DEVICE> bs=4M conv=fsync status=progress
   ```
4. Eject the SD card, power-cycle.

**Alternative — USB fastboot recovery** (no working SD boot needed):
1. Hold **FDL**, connect USB to the board's OTG port, power on, release FDL once serial output appears.
2. `./bootstrap.sh openwrt-spacemit-k1-generic-initramfs.itb` — boots RAM-only, nothing persistent touched.
3. Once satisfied, run `update-bootloader.sh` from that shell, then flash as in step 3 above.

> ⚠️ Some R2S units appear to lack a SPI NOR flash chip (the RV2 has one) — if yours does too, eMMC's boot partition is your only bootloader target; skip NOR-based instructions.

</details>

## ✅ First steps after flashing

- [ ] **SD boot** → `ssh root@192.168.1.1` (no password yet)
- [ ] Set a root password: `passwd`
- [ ] Reach it from your PC by connecting **directly** (point-to-point, or an isolated VM bridge) — plugging straight into your existing LAN risks a second DHCP server fighting yours at `192.168.1.1`
- [ ] Web UI: `luci` is baked into new builds; if using an older image, `apk update && apk add luci` (needs a working WAN first — see below)
- [ ] Set up internet: convention is **`eth0` = WAN (DHCP client)**, **`eth1` = LAN**:
  ```sh
  # from a SECOND ssh session — keep your first one open in case of typos
  uci del_list network.@device[0].ports='eth0'
  uci set network.wan=interface
  uci set network.wan.device='eth0'
  uci set network.wan.proto='dhcp'
  uci commit network && uci commit firewall
  /etc/init.d/network restart
  ```
  Then plug the uplink into `eth0`, connected to your **main router's LAN side** (not the ISP router directly). Verify from your original session before closing it.

## ⚠️ Known caveats

| Area | Note |
|---|---|
| R2S Ethernet (2.5GbE) | Uses upstream `kmod-r8169`, not vendor `r8125` — newer, less battle-tested than the SD boot path itself |
| R2S SPI NOR | Some units may lack the chip entirely — eMMC-only bootloader target on those |
| Package manager | This target builds on `apk` (25.x+), not legacy `opkg` |
| Reproducibility | PR #23231 is force-pushed regularly — pin a commit SHA via the `pin_commit` workflow input for a build you can reproduce later |

## 🔒 Disclaimer

Personal/hobby project for tracking an in-progress OpenWrt target. Not affiliated with the OpenWrt project, SpacemiT, or Xunlong/OrangePi. Flashing bootloaders and eMMC carries a small risk of needing board recovery — the SD and fastboot paths above exist specifically so you can test before committing to anything persistent.
