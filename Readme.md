# OpenWrt-Spacemit-K1 (personal build repo)

This is a **personal-use** GitHub Actions pipeline that builds OpenWrt firmware
for the RISC-V SpacemiT K1 target — covering the **OrangePi R2S** and
**OrangePi RV2** — directly from [openwrt/openwrt PR #23231](https://github.com/openwrt/openwrt/pull/23231)
(`dhewg:spacemit`), since that target isn't merged into mainline OpenWrt yet.

It doesn't contain any OpenWrt source itself. It just holds the workflow that
checks out the PR fresh, builds it, and publishes the resulting images as a
GitHub Release each time you run it.

> ⚠️ **Not an official OpenWrt build.** PR #23231 is still open, actively
> force-pushed, and not fully reviewed/approved upstream. Treat every release
> here as a personal testing build, not production firmware. Things can and
> do change between runs as the PR evolves.

## What one build produces

Both boards share the **same `generic` device image** — a multi-DTB FIT file
that u-boot reads and auto-matches to whichever board it's booted on. So a
single run gives you one set of files that work on *either* board:

| File | What it's for |
|---|---|
| `*-sdcard.img.gz` | Full self-contained SD card image (bootloader + rootfs) |
| `*-emmc.img.gz` | Rootfs image for eMMC install |
| `*-other.img.gz` | Rootfs image for NVMe/USB install |
| `*-initramfs.itb` | RAM-only image for USB/fastboot test-booting |
| `u-boot-spacemit_k1.tar.gz` | Bootloader + `update-bootloader.sh` + `bootstrap.sh` (fastboot helper) |

## How to use this repo

1. Go to the **Actions** tab → select the build workflow → **Run workflow**.
   - Leave `pin_commit` blank to build the PR's current tip, or paste a
     specific commit SHA from the PR for a reproducible build.
2. Wait for the run to finish (OpenWrt full builds typically take 1–3+ hours
   on a hosted runner).
3. Grab the files from the **Releases** page (not the Actions artifact list —
   the workflow publishes a proper Release each run, tagged by date/run number).

## Installing on the R2S or RV2

### Option A — SD card (easiest, fully reversible)

1. Write the sdcard image to a card:
   ```
   zcat openwrt-spacemit-k1-generic-*-sdcard.img.gz | sudo dd of=/dev/<SD_DEVICE> bs=4M conv=fsync status=progress
   ```
2. Insert it and power on. The board boots entirely from the card — nothing
   on the board itself is touched. This is the safest way to test a build.

### Option B — eMMC / NVMe / USB (persistent, touches the board's bootloader)

The board's boot ROM can only load the first-stage bootloader from an SD
card, NOR flash, or the eMMC boot partition — it can't boot straight off a
USB stick or NVMe drive. So installing to USB/NVMe means the bootloader
still has to be committed to NOR or eMMC first.

**Recommended path (test before you commit anything):**

1. Boot the SD card from Option A first and confirm it works properly.
2. From that SD-booted shell, run the included `update-bootloader.sh` to
   write the bootloader to NOR and/or eMMC's boot partition.
3. Write the target rootfs image to eMMC or your USB/NVMe drive:
   ```
   sudo dd if=openwrt-spacemit-k1-generic-*-emmc.img of=/dev/<EMMC_DEVICE> bs=4M conv=fsync status=progress
   # or for NVMe/USB:
   sudo dd if=openwrt-spacemit-k1-generic-*-other.img of=/dev/<TARGET_DEVICE> bs=4M conv=fsync status=progress
   ```
4. Eject the SD card and power-cycle — it should now boot from eMMC/NVMe/USB.

**Alternative — USB fastboot recovery** (if you don't want to touch a working
SD setup, or the board won't boot from SD for some reason):

1. Power off, hold the board's **FDL** button, connect a USB cable to the
   board's USB-device/OTG port, power on, then release FDL once you see
   serial output.
2. From `u-boot-spacemit_k1.tar.gz`, run:
   ```
   ./bootstrap.sh openwrt-spacemit-k1-generic-initramfs.itb
   ```
   This boots a RAM-only OpenWrt shell without touching NOR/eMMC at all —
   good for test-driving a build safely.
3. Once satisfied, run `update-bootloader.sh` from that shell, then `scp`
   over and `dd` the eMMC/other image as in step 3 above.

### ⚠️ Board-specific note

Testing on the PR so far suggests the **R2S may not have a SPI NOR flash
chip** on some units (the RV2 does). If yours doesn't, the bootloader can
only go to eMMC's boot partition — NOR won't be an option, so stick to the
eMMC path above rather than NOR-based install instructions.

### Ethernet on the R2S

The R2S's two 2.5GbE ports use the upstream `kmod-r8169` driver in this
build (rather than Realtek's vendor `r8125` driver). This is recent work in
the PR — expect it to be less battle-tested than the SD-card boot path
itself.

## Disclaimer

This is a hobby/personal setup for tracking an in-progress OpenWrt target.
It is not affiliated with the OpenWrt project, SpacemiT, or Xunlong/OrangePi.
Flashing bootloaders and eMMC always carries a small risk of needing board
recovery — the SD-card and fastboot paths above are there specifically to
let you test before you commit to anything persistent.
