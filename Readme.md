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
- [Adding packages](#-adding-packages)
- [Expanding storage](#-expanding-storage)
- [Known caveats](#-known-caveats)
- [Disclaimer](#-disclaimer)

## What this is

This repo holds **no OpenWrt source** — just a GitHub Actions workflow that checks out PR #23231 fresh, cross-compiles it, and publishes the images as a GitHub Release each run. Both the R2S and RV2 are covered by the **same `generic` device image**: a multi-DTB FIT file that u-boot auto-matches to whichever board it's booted on, so there's nothing board-specific to pick at download time.

> [!IMPORTANT]
> **R2S has no SD card slot** — it boots from USB only. RV2 has an SD slot. Pick your file/method per-board using the table below, not by copying the other board's steps.

## 🚀 Quick start

**RV2:**
```text
1. Actions tab → Run workflow → wait for it to finish
2. Releases page → download the *-sdcard.img.gz
3. zcat file.img.gz | sudo dd of=/dev/<SD_DEVICE> bs=4M conv=fsync status=progress
4. Insert SD card into RV2 → power on
5. ssh root@192.168.1.1   (no password on first boot)
```

**R2S:** no SD slot — use the USB fastboot path in [Installing](#-installing) instead.

Full detail on each step below.

## 📦 Which file do I flash?

One build run produces all of these — pick based on **how**, not **which board**:

| File | Use this when... |
|---|---|
| `*-sdcard.img.gz` | **RV2 only** — simplest, fully-reversible. **Start here if you have an RV2.** |
| `*-emmc.img.gz` | You've tested and want a persistent install on eMMC (either board). |
| `*-other.img.gz` | Same, but installing to NVMe/USB instead of eMMC — **read the NVMe warning in [Expanding storage](#-expanding-storage) first if you plan to resize it.** |
| `*-initramfs.itb` | RAM-only test boot over USB fastboot — nothing touches the board's storage. **R2S's only entry point**, since it has no SD slot. |
| `u-boot-spacemit_k1.tar.gz` | Contains the bootloader plus `update-bootloader.sh` / `bootstrap.sh` helper scripts, needed for the eMMC/USB/fastboot paths. |

## 💽 Installing

<details>
<summary><strong>Option A — SD card (RV2 only — start here if you have one)</strong></summary>

```sh
zcat openwrt-spacemit-k1-generic-*-sdcard.img.gz | \
  sudo dd of=/dev/<SD_DEVICE> bs=4M conv=fsync status=progress
```

Insert and power on — the board boots entirely from the card, nothing on the board itself is touched. Safest way to test any build.

**R2S has no SD slot — skip straight to the USB fastboot path below.**

</details>

<details>
<summary><strong>Option B — eMMC / NVMe / USB (persistent, both boards)</strong></summary>

The boot ROM can only load the first-stage bootloader from SD, NOR, or eMMC's boot partition — never straight from USB/NVMe. So the bootloader has to land on NOR/eMMC first, even if the rootfs itself ends up on USB/NVMe.

**Recommended path (RV2):**
1. Boot the SD card (Option A) and confirm it works.
2. From that shell, run `update-bootloader.sh` (from `u-boot-spacemit_k1.tar.gz`) to write the bootloader to NOR/eMMC.
3. Flash the target rootfs:
   ```sh
   sudo dd if=openwrt-spacemit-k1-generic-*-emmc.img of=/dev/<EMMC_DEVICE> bs=4M conv=fsync status=progress
   # or NVMe/USB:
   sudo dd if=openwrt-spacemit-k1-generic-*-other.img of=/dev/<TARGET_DEVICE> bs=4M conv=fsync status=progress
   ```
4. Eject the SD card, power-cycle.

**Required path for R2S (no SD slot) — USB fastboot recovery:**
1. Hold **FDL**, connect USB to the board's OTG port, power on, release FDL once serial output appears.
2. `./bootstrap.sh openwrt-spacemit-k1-generic-initramfs.itb` — boots RAM-only, nothing persistent touched.
3. Once satisfied, run `update-bootloader.sh` from that shell, then flash eMMC/NVMe/USB as in step 3 above.

> ⚠️ Some R2S units appear to lack a SPI NOR flash chip (the RV2 has one) — if yours does too, eMMC's boot partition is your only bootloader target; skip NOR-based instructions.

</details>

## ✅ First steps after flashing

- [ ] After first boot (either board) → `ssh root@192.168.1.1` (no password yet)
- [ ] Set a root password: `passwd`
- [ ] Reach it from your PC by connecting **directly** (point-to-point, or an isolated VM bridge) — plugging straight into your existing LAN risks a second DHCP server fighting yours at `192.168.1.1`
- [ ] Web UI: `luci` is baked into new builds; if using an older image, `apk update && apk add luci` (needs a working WAN first — see below)
- [ ] Set up internet: convention is **`eth0` = WAN (DHCP client)**, **`eth1` = LAN** — but confirm with `ip a` first, since naming isn't guaranteed on a target this new:
  ```sh
  # from a SECOND ssh session — keep your first one open in case of typos
  ip a   # confirm eth0/eth1 actually match what's below before running anything
  uci del_list network.@device[0].ports='eth0'
  uci set network.wan=interface
  uci set network.wan.device='eth0'
  uci set network.wan.proto='dhcp'
  uci commit network && uci commit firewall
  /etc/init.d/network restart
  ```
  Then plug the uplink into `eth0`, connected to your **main router's LAN side** (not the ISP router directly). Verify from your original session before closing it.
- [ ] Need a package not already in the image? See [Adding packages](#-adding-packages) below.
- [ ] Storage not using the full SD/eMMC/USB capacity? See [Expanding storage](#-expanding-storage) below.

## 📦 Adding packages

The workflow's `.config` step includes only `luci` by default — its full dependency tree gets pulled in automatically (same resolution `apk` does live), so you don't need to list dependencies yourself. To add more, edit the `.config` block in `build-openwrt-spacemit-k1.yml`:

```
CONFIG_PACKAGE_<exact-name>=y
```

Find the exact name before a long build wastes your time: `apk search <keyword>` live on the board (same index the build uses), or browse `https://downloads.openwrt.org/snapshots/packages/riscv64_generic/`.

## 💽 Expanding storage

OpenWrt's default rootfs partition is a fixed ~100MB, regardless of your card/eMMC/USB drive's real size — the build doesn't know how big your storage will be ahead of time. This is a **manual, post-install step** — not baked into the image, deliberately, since it touches your live partition table and is worth doing with your eyes open rather than automatically on first boot.

> [!CAUTION]
> **Do not run this on an NVMe install.** There's a confirmed, still-open OpenWrt bug where this exact script bricks NVMe installs with `failed to execute /usr/libexec/login` after the first reboot. If you're on `*-other.img.gz` via NVMe, skip this entirely for now.

Tools (`parted`, `losetup`, `resize2fs`, `blkid`) are already baked into new builds. Once your WAN is up:

```sh
apk update
apk add parted losetup resize2fs blkid   # only needed on older images without these baked in

wget -U "" -O expand-root.sh "https://openwrt.org/_export/code/docs/guide-user/advanced/expand_root?codeblock=1"
chmod +x expand-root.sh

# Creates /etc/uci-defaults/70-rootpt-resize and 80-rootfs-resize, and
# registers them in /etc/sysupgrade.conf so they survive a sysupgrade
. ./expand-root.sh

# Actually triggers it — resizes the partition, reboots, resizes the
# filesystem, reboots again. Don't skip this step; sourcing the script
# above only creates the scripts, it doesn't run them.
sh /etc/uci-defaults/70-rootpt-resize
```

**If it doesn't seem to do anything** (reported on an RV2 SD card so far — cause not yet confirmed): check `parted /dev/mmcblk1 print` (substitute your actual root device from `lsblk`) to see whether the root partition is actually the *last* partition on the disk. `parted resizepart` can only grow a partition into trailing free space — if anything follows the root partition on this image's layout, that would explain a silent no-op. Also check `dmesg` right after running `70-rootpt-resize` for any error, and confirm the reboot it triggers actually happened rather than the session just dropping.

**To re-run** after a failed or partial attempt:
```sh
rm -f /etc/rootpt-resize /etc/rootfs-resize
```
then remove the two `/etc/uci-defaults/...` lines from `/etc/sysupgrade.conf` if present, before retrying — otherwise the script assumes it already ran and does nothing.

## ⚠️ Known caveats

| Area | Note |
|---|---|
| R2S Ethernet (2.5GbE) | Uses upstream `kmod-r8169`, not vendor `r8125` — newer, less battle-tested than the SD boot path itself |
| **R2S has no SD card slot** | USB fastboot is the only entry point — see [Installing](#-installing) |
| R2S SPI NOR | Some units may lack the chip entirely — eMMC-only bootloader target on those |
| **Root expand + NVMe** | Confirmed open OpenWrt bug bricks NVMe installs after resize — see [Expanding storage](#-expanding-storage) |
| **RV2 onboard WiFi (AP6256)** | **Not enumerating at all** — `dmesg`/`/sys/class/mmc_host` show no SDIO host for it, meaning the devicetree doesn't expose it yet in this PR (matches OrangePi's own official images, which also reportedly lack working WiFi on RV2). No package fixes this — a USB WiFi dongle is the practical workaround for now |
| Package manager | This target builds on `apk` (25.x+), not legacy `opkg` |
| Reproducibility | PR #23231 is force-pushed regularly — pin a commit SHA via the `pin_commit` workflow input for a build you can reproduce later |

## 🔒 Disclaimer

Personal/hobby project for tracking an in-progress OpenWrt target. Not affiliated with the OpenWrt project, SpacemiT, or Xunlong/OrangePi. Flashing bootloaders and eMMC carries a small risk of needing board recovery — the SD and fastboot paths above exist specifically so you can test before committing to anything persistent.
