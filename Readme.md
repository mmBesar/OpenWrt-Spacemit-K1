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

## 💾 Installing

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

  > [!WARNING]
  > **Don't connect both `eth0` and `eth1` to the same switch before this is done.** While both ports are still bridged together as one LAN (the default state), plugging both into the same switch creates a physical loop through the board — this can trigger a broadcast storm and take down your *entire* network, not just the board. Keep the board's second port unplugged (or point-to-point only) until *after* the `uci` commands below have split `eth0` off as WAN.

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
  Only *after* that restart, plug the uplink into `eth0`, connected to your **main router's LAN side** (not the ISP router directly). Verify from your original session before closing it.
- [ ] Need a package not already in the image? See [Adding packages](#-adding-packages) below.
- [ ] Storage not using the full SD/eMMC/USB capacity? See [Expanding storage](#-expanding-storage) below.

## 📦 Adding packages

The workflow's `.config` step includes only `luci` by default — its full dependency tree gets pulled in automatically (same resolution `apk` does live), so you don't need to list dependencies yourself. To add more, edit the `.config` block in `build-openwrt-spacemit-k1.yml`:

```
CONFIG_PACKAGE_<exact-name>=y
```

Find the exact name before a long build wastes your time: `apk search <keyword>` live on the board (same index the build uses), or browse `https://downloads.openwrt.org/snapshots/packages/riscv64_generic/`.

## 💽 Expanding storage

The rootfs partition uses this board profile's own default size (~230MB) — deliberately left as-is, so a single build stays safe on any storage size across the fleet, including smaller media in the future. Extending into free space is a **post-install, per-device step**, since how much free space exists depends entirely on the actual card/eMMC/USB drive in front of you, not something a build can know ahead of time.

The GPT-staleness issue below and the extroot approach aren't board- or media-specific — the same tiny image gets written to whatever storage you use, so this applies identically whether you're on RV2 or R2S, SD card, eMMC, USB, or NVMe.

**Use extroot — this is OpenWrt's real, built-in mechanism, not a workaround.** It's read natively by OpenWrt's own boot process before anything else starts, using a genuine ext4 partition with full journaling. The confusing-looking `overlayfs:/overlay` line you'll see in `mtab` is simply how OpenWrt layers a writable filesystem over a read-only base *everywhere* — the same technique the tiny default setup already uses, nothing special or hacky about the bigger version.

> [!NOTE]
> **The official `expand_root` resize script does NOT work on this board** and never will, regardless of any `.config` setting — this board's overlay lives inside the same partition as the read-only erofs content, which `parted resizepart` isn't built to handle. Use extroot below instead.

> [!CAUTION]
> **NVMe is unverified for this procedure.** There's a confirmed, still-open OpenWrt bug where a similar resize/first-boot flow bricks NVMe installs after reboot. Not confirmed against extroot specifically, but treat NVMe as untested until someone's actually done it.

### Automated (script)

[`scripts/extend-storage.sh`](scripts/extend-storage.sh) does the full procedure below automatically — detects your root disk, fixes a stale GPT if needed, creates one new partition in the free space, formats it, copies your existing config across, and configures `fstab`. It pauses for explicit confirmation before writing anything, and never touches existing partitions.

> [!NOTE]
> **Confirmed working end-to-end** (zero manual fixes needed) on a fresh RV2 SD card. The underlying mechanism isn't board- or media-specific, so it should work identically on eMMC/USB/NVMe and on the R2S — but those exact combinations haven't been separately tested yet. Treat a first run on any new board/media combo with the same care as any other first attempt.

The script lives in this repo, not in the flashed image — pull it onto the board first (needs working WAN/internet already set up). Swap `main` below if your repo's default branch is named differently:

```sh
wget -O extend-storage.sh "https://raw.githubusercontent.com/mmBesar/OpenWrt-Spacemit-K1/main/scripts/extend-storage.sh"
chmod +x extend-storage.sh
sh extend-storage.sh
```

Then, once it finishes:
```sh
reboot
```

After reboot, verify:
```sh
grep -e /overlay /etc/mtab
df -h /overlay /
```
You're looking for your new partition (not `loop0`) mounted at `/overlay`, sized close to your disk's actual free space.

### Manual (step by step)

If you'd rather do it by hand, or the script hits something it doesn't handle:

Tools needed (`block-mount`, `kmod-fs-ext4`, `e2fsprogs`, `parted`, `blkid`) are baked into new builds. **These can never be installed live via `apk add`** while this target stays unmerged — `downloads.openwrt.org` doesn't publish a package feed for an unmerged PR's target, so any kernel/target-specific package fails with "no such package" regardless of retries. Only arch-generic userspace packages (like `luci`) install live. If you're on an older image without these baked in, rebuild rather than fighting `apk`.

**Never run `parted mklabel`** on a disk with existing partitions — it wipes the *entire* table, including your OS. Only `mkpart` into free space after your last partition.

If `parted print` reports a corrupt/mismatched backup GPT, that's normal for any OS image written to bigger media than it was built for (same as Raspberry Pi OS, Armbian, etc.) — fix it interactively first:
```sh
parted /dev/<disk>
(parted) print
```
Answer `OK` then `Fix` to the two prompts, then `quit`.

Get your real layout before creating anything — never guess sector numbers:
```sh
parted -s /dev/<disk> unit s print
```

Create the partition using the real end-of-last-partition sector from that output:
```sh
parted /dev/<disk>
(parted) unit s
(parted) mkpart extroot ext4 <last_partition_end+1>s -1s
(parted) print   # confirm it landed correctly, existing partitions untouched
(parted) quit
```

Format and configure:
```sh
mkfs.ext4 -F -L extroot /dev/<disk>p<N>
```
`-F` matters here specifically: reflashing the small base image only overwrites the first ~268MB — anything you created further out on a previous attempt (like an earlier extroot partition) physically survives a reflash. Without `-F`, `mkfs` will stop and ask "proceed anyway?" if it finds old data at that offset.
```sh
eval $(block info /dev/<disk>p<N> | grep -o -e 'UUID="\S*"')
eval $(block info | grep -o -e 'MOUNT="\S*/overlay"')
echo "UUID=$UUID  MOUNT=$MOUNT"   # confirm both non-empty before continuing

uci -q delete fstab.extroot
uci set fstab.extroot="mount"
uci set fstab.extroot.uuid="${UUID}"
uci set fstab.extroot.target="${MOUNT}"
uci commit fstab

ORIG="$(block info | sed -n -e '/MOUNT="\S*\/overlay"/s/:\s.*$//p')"
uci -q delete fstab.rwm
uci set fstab.rwm="mount"
uci set fstab.rwm.device="${ORIG}"
uci set fstab.rwm.target="/rwm"
uci commit fstab
```

> [!IMPORTANT]
> **Copy your existing config across before rebooting** — skipping this switches to a blank overlay and looks like a full reset (hostname, WAN config, everything back to defaults), even though nothing is actually lost as long as you haven't rebooted again since:
> ```sh
> mkdir -p /mnt/extroot-new
> mount /dev/<disk>p<N> /mnt/extroot-new
> tar -C "${MOUNT}" -cf - . | tar -C /mnt/extroot-new -xf -
> umount /mnt/extroot-new
> ```

```sh
reboot
```

## ⚠️ Known caveats

| Area | Note |
|---|---|
| R2S Ethernet (2.5GbE) | Uses upstream `kmod-r8169`, not vendor `r8125` — newer, less battle-tested than the SD boot path itself |
| **R2S has no SD card slot** | USB fastboot is the only entry point — see [Installing](#-installing) |
| R2S SPI NOR | Some units may lack the chip entirely — eMMC-only bootloader target on those |
| **Root expand + NVMe** | Confirmed open OpenWrt bug bricks NVMe installs after resize — see [Expanding storage](#-expanding-storage) |
| **Reflashing doesn't wipe the whole card/drive** | Only the first ~268MB (partitions 1–5) gets overwritten — anything created further out on a previous attempt (e.g. an old extroot partition) physically survives a reflash. `extend-storage.sh` handles this (`mkfs -F`); doing it manually needs the same flag, see [Expanding storage](#-expanding-storage) |
| **RV2 onboard WiFi (AP6256)** | **Not enumerating at all** — `dmesg`/`/sys/class/mmc_host` show no SDIO host for it, meaning the devicetree doesn't expose it yet in this PR (matches OrangePi's own official images, which also reportedly lack working WiFi on RV2). No package fixes this — a USB WiFi dongle is the practical workaround for now |
| Package manager | This target builds on `apk` (25.x+), not legacy `opkg` |
| **Live `apk add` for kmods/target packages** | Will always fail while unmerged — `downloads.openwrt.org` only publishes a target-specific package feed for merged targets, and this PR isn't one. Anything kernel/target-specific (`kmod-*`, `block-mount`, etc.) must be baked into the `.config` and rebuilt; only arch-generic userspace packages (like `luci`) install live |
| Reproducibility | PR #23231 is force-pushed regularly — pin a commit SHA via the `pin_commit` workflow input for a build you can reproduce later |

## 🔒 Disclaimer

Personal/hobby project for tracking an in-progress OpenWrt target. Not affiliated with the OpenWrt project, SpacemiT, or Xunlong/OrangePi. Flashing bootloaders and eMMC carries a small risk of needing board recovery — the SD and fastboot paths above exist specifically so you can test before committing to anything persistent.
