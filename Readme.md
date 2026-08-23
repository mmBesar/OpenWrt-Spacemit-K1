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

**Already solved for normal use.** This build's `.config` sets `CONFIG_TARGET_ROOTFS_PARTSIZE=7000` (MiB), which directly sizes the rootfs partition — and on this board's overlay design (an F2FS region living inside the same partition as the read-only erofs content), the writable overlay scales proportionally with it. Confirmed on a real flash: overlay went from ~228MB (default) to **6.8GB**, matching the config exactly. Nothing else to do — this is already in every image built from the current workflow.

> [!NOTE]
> This value is a single shared setting across `sdcard`/`emmc`/`other` images in one build run — it's set conservatively to fit R2S's real ~7.3GB eMMC ceiling (confirmed via `lsblk` on real hardware), since that's the tightest constraint across the fleet. RV2's much larger SD/eMMC capacity stays underused as a result — a limitation of the shared knob, not a bug. Splitting into separate per-board builds with different values is possible later if that ever matters.

**The official OpenWrt resize script does NOT work on this board** — worth knowing so you don't retry it. It assumes a plain ext4 rootfs partition; this target's overlay is a loop-mounted region inside the same partition as the erofs content, which `parted resizepart` doesn't touch meaningfully. Confirmed not working on a real RV2 SD card.

<details>
<summary><strong>If you ever need MORE than the built-in ~7GB (extroot)</strong></summary>

For using RV2's much larger eMMC/SD capacity, or a big NVMe/USB drive, beyond what the built-in partition size gives you — [OpenWrt's extroot](https://openwrt.org/docs/guide-user/additional-software/extroot_configuration) mounts a separate, bigger partition over `/overlay` instead of resizing the built-in one.

> [!CAUTION]
> **Do not attempt this on an NVMe install.** There's a confirmed, still-open OpenWrt bug where a similar resize/first-boot flow bricks NVMe installs with `failed to execute /usr/libexec/login` after reboot. Not confirmed against extroot specifically, but treat NVMe as unverified until tested.

Tools needed (`block-mount`, `kmod-fs-ext4`, `e2fsprogs`, `parted`, `blkid`) are baked into new builds — **critically, these can never be installed live via `apk add`** while this target stays unmerged. `downloads.openwrt.org` doesn't publish a package feed for an unmerged PR's target, so any kernel/target-specific package (`kmod-*`, `block-mount`) fails with "no such package" no matter what — only arch-generic userspace packages (like `luci`) install live. If you're on an older image without these baked in, rebuild rather than trying to `apk add` your way out of it.

**On an SD card with existing partitions (not a blank disk):** never run `parted mklabel` — that wipes the *entire* partition table, including your OS. Only `mkpart` into the free space after your last existing partition. If `parted print` reports a corrupt/mismatched backup GPT, that's normal for any OS image written to bigger media than it was built for (same as Raspberry Pi OS, Armbian, etc.) — fix it interactively (`parted /dev/<disk>` → `print` → answer `Fix` to both prompts) before creating anything.

```sh
apk update
apk add block-mount kmod-fs-ext4 e2fsprogs

# Find your disk's real layout first — never guess sector numbers
parted -s /dev/<disk> unit s print

# Create the new partition using free space AFTER your last existing
# partition's end sector (substitute real numbers from print above)
parted /dev/<disk>
(parted) mkpart extroot ext4 <last_partition_end+1>s -1s
(parted) print   # confirm it landed correctly before continuing
(parted) quit

mkfs.ext4 -L extroot /dev/<disk>p<N>

# Configure fstab to use the new partition as extroot
eval $(block info /dev/<disk>p<N> | grep -o -e 'UUID="\S*"')
eval $(block info | grep -o -e 'MOUNT="\S*/overlay"')
echo "UUID=$UUID  MOUNT=$MOUNT"   # confirm both non-empty before continuing

uci -q delete fstab.extroot
uci set fstab.extroot="mount"
uci set fstab.extroot.uuid="${UUID}"
uci set fstab.extroot.target="${MOUNT}"
uci commit fstab

# Preserve access to the original (small) overlay too
ORIG="$(block info | sed -n -e '/MOUNT="\S*\/overlay"/s/:\s.*$//p')"
uci -q delete fstab.rwm
uci set fstab.rwm="mount"
uci set fstab.rwm.device="${ORIG}"
uci set fstab.rwm.target="/rwm"
uci commit fstab

# Copy existing config across before switching over
mount /dev/<disk>p<N> /mnt
tar -C "${MOUNT}" -cvf - . | tar -C /mnt -xf -

reboot
```

</details>

## ⚠️ Known caveats

| Area | Note |
|---|---|
| R2S Ethernet (2.5GbE) | Uses upstream `kmod-r8169`, not vendor `r8125` — newer, less battle-tested than the SD boot path itself |
| **R2S has no SD card slot** | USB fastboot is the only entry point — see [Installing](#-installing) |
| R2S SPI NOR | Some units may lack the chip entirely — eMMC-only bootloader target on those |
| **Root expand + NVMe** | Confirmed open OpenWrt bug bricks NVMe installs after resize — see [Expanding storage](#-expanding-storage) |
| **RV2 onboard WiFi (AP6256)** | **Not enumerating at all** — `dmesg`/`/sys/class/mmc_host` show no SDIO host for it, meaning the devicetree doesn't expose it yet in this PR (matches OrangePi's own official images, which also reportedly lack working WiFi on RV2). No package fixes this — a USB WiFi dongle is the practical workaround for now |
| Package manager | This target builds on `apk` (25.x+), not legacy `opkg` |
| **Live `apk add` for kmods/target packages** | Will always fail while unmerged — `downloads.openwrt.org` only publishes a target-specific package feed for merged targets, and this PR isn't one. Anything kernel/target-specific (`kmod-*`, `block-mount`, etc.) must be baked into the `.config` and rebuilt; only arch-generic userspace packages (like `luci`) install live |
| Reproducibility | PR #23231 is force-pushed regularly — pin a commit SHA via the `pin_commit` workflow input for a build you can reproduce later |

## 🔒 Disclaimer

Personal/hobby project for tracking an in-progress OpenWrt target. Not affiliated with the OpenWrt project, SpacemiT, or Xunlong/OrangePi. Flashing bootloaders and eMMC carries a small risk of needing board recovery — the SD and fastboot paths above exist specifically so you can test before committing to anything persistent.
