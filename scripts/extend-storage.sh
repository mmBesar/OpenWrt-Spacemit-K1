#!/bin/sh
# extend-storage.sh — OpenWrt-Spacemit-K1 project
#
# Extends usable storage by creating a new ext4 partition in whatever free
# space exists after the last existing partition, and configuring it as
# OpenWrt's extroot (the proper, built-in mechanism — not a hack).
#
# Safe by design:
#   - NEVER runs `parted mklabel` (which wipes the entire partition table).
#     Only ever creates ONE new partition in trailing free space.
#   - Detects your root disk automatically rather than assuming a device
#     name, but ECHOES what it found and PAUSES for explicit confirmation
#     before writing anything.
#   - Copies your current overlay's contents to the new partition BEFORE
#     switching over, so existing config (LuCI, network, etc.) isn't lost.
#   - Requires network-provided tools (block-mount, kmod-fs-ext4, e2fsprogs,
#     parted) to already be present — these are baked into builds from this
#     workflow. If `which block` comes back empty, stop and rebuild instead
#     of trying to `apk add` them — live installs of kernel/target-specific
#     packages don't work on this unmerged target (see README).
#
# CONFIRMED working end-to-end (script form, zero manual intervention)
# on a fresh RV2 SD card as of 2026-08-24. The underlying mechanism
# (GPT-staleness fix, extroot) should apply identically to eMMC/USB/NVMe
# and to the R2S, since it's not board- or media-specific — but those
# exact combinations haven't been separately tested yet. Treat a first
# run on any NEW board/media combo with the same care as before.
#
# Usage: sh extend-storage.sh

set -e

echo "=== extend-storage.sh ==="
echo ""

echo "[1/6] Checking required tools..."
for tool in block parted mkfs.ext4; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: '$tool' not found. This image doesn't have the needed" >&2
    echo "packages baked in. Rebuild from the current workflow rather than" >&2
    echo "trying to 'apk add' it live — see README's Known Caveats." >&2
    exit 1
  }
done
echo "  OK — block, parted, mkfs.ext4 all present."
echo ""

echo "[2/6] Detecting root disk..."
ROOTDEV=$(block info | sed -n -e '/MOUNT="\/rom"/s/:.*//p')
if [ -z "$ROOTDEV" ]; then
  echo "ERROR: could not detect root device automatically. Aborting." >&2
  exit 1
fi
case "$ROOTDEV" in
  *mmcblk*p*) DISK=$(echo "$ROOTDEV" | sed 's/p[0-9]*$//') ;;
  *nvme*p*)   DISK=$(echo "$ROOTDEV" | sed 's/p[0-9]*$//') ;;
  *[0-9])     DISK=$(echo "$ROOTDEV" | sed 's/[0-9]*$//') ;;
  *)          DISK="$ROOTDEV" ;;
esac

echo "Detected root partition: $ROOTDEV"
echo "Detected disk:           $DISK"
echo ""

# 2. Find the end of the last existing partition (works correctly even
#    with a stale GPT — the existing partitions' own data is accurate
#    regardless of the disk-size bookkeeping issue fixed in step 3)
echo "[3/6] Reading current partition layout..."
LASTLINE=$(parted -s "$DISK" unit s print | awk '/^ *[0-9]+/ {line=$0} END {print line}')
LASTEND=$(echo "$LASTLINE" | awk '{gsub("s","",$3); print $3}')
STARTSEC=$((LASTEND + 1))

if [ -z "$LASTEND" ] || [ "$LASTEND" -le 0 ] 2>/dev/null; then
  echo "ERROR: could not determine last partition's end sector. Aborting" >&2
  echo "before touching the partition table. Run 'parted -s $DISK unit s print'" >&2
  echo "yourself and check what went wrong." >&2
  exit 1
fi

echo "Last existing partition ends at sector: $LASTEND"
echo "New partition will start at sector:     $STARTSEC"
echo ""
echo "This will create ONE new ext4 partition on $DISK using all remaining"
echo "free space, then copy your current overlay config onto it. Existing"
echo "partitions (including your OS) are not touched."
echo ""
printf "Type 'yes' to continue, anything else aborts: "
read CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Aborted — nothing changed."; exit 1; }

# 3. Fix the stale/corrupt backup GPT AND create the new partition in ONE
#    continuous session — the GPT fix only actually commits to disk when
#    something in the SAME session performs a real write (like creating a
#    partition); done as two separate parted invocations, the fix silently
#    doesn't persist. This matches the exact sequence proven working live.
#    The "Yes"/"Ignore" answers cover the rounding/alignment prompts seen
#    live; if they don't occur this run, parted just reports them as
#    unrecognized commands and continues harmlessly (nothing is written by
#    an unrecognized command, so this is safe either way).
echo "[4/6] Creating partition (fixing stale GPT sizing first if needed)..."
parted "$DISK" ---pretend-input-tty <<EOF
print
OK
Fix
mkpart extroot ext4 ${STARTSEC}s 100%
Yes
Ignore
print
quit
EOF
sleep 1

NEWNUM=$(parted -s "$DISK" print | awk '/extroot/ {print $1}')
if [ -z "$NEWNUM" ]; then
  echo "ERROR: could not find the newly created 'extroot' partition in" >&2
  echo "'parted print' output. Stopping before mkfs — run" >&2
  echo "'parted -s $DISK print' yourself to see what actually happened." >&2
  exit 1
fi
case "$DISK" in
  *mmcblk*) NEWDEV="${DISK}p${NEWNUM}" ;;
  *nvme*)   NEWDEV="${DISK}p${NEWNUM}" ;;
  *)        NEWDEV="${DISK}${NEWNUM}" ;;
esac

echo "New partition created: $NEWDEV"
echo ""
echo "Formatting $NEWDEV as ext4 (-F: this card/drive may carry a filesystem"
echo "signature left over from a previous attempt at the same disk offset —"
echo "reflashing the small base image does NOT wipe space beyond ~268MB, so"
echo "old test data can persist there across reflashes. You already confirmed"
echo "'yes' above, so this proceeds without a second interactive prompt.)"
mkfs.ext4 -F -L extroot "$NEWDEV"

# 5. Detect the new partition's UUID and current overlay mount point
eval "$(block info "$NEWDEV" | grep -o -e 'UUID="\S*"')"
eval "$(block info | grep -o -e 'MOUNT="\S*/overlay"')"

if [ -z "$UUID" ] || [ -z "$MOUNT" ]; then
  echo "ERROR: failed to detect UUID/MOUNT — stopping before touching fstab." >&2
  echo "The new partition ($NEWDEV) exists but is NOT yet configured as" >&2
  echo "extroot. Nothing is broken; investigate before re-running." >&2
  exit 1
fi

echo "New partition UUID: $UUID"
echo "Current overlay:     $MOUNT"
echo ""

# 6. Configure fstab BEFORE copying data — this must happen first so the
#    copied snapshot includes the extroot config itself. Writing this
#    while the OLD overlay is still active is correct: mount_root reads
#    fstab from whichever overlay is active at boot time to decide
#    whether to switch to extroot, so this has to land there now.
echo "[5/6] Configuring fstab..."
uci -q delete fstab.extroot || true
uci set fstab.extroot="mount"
uci set fstab.extroot.uuid="${UUID}"
uci set fstab.extroot.target="${MOUNT}"
uci commit fstab

ORIG="$(block info | sed -n -e '/MOUNT="\S*\/overlay"/s/:\s.*$//p')"
uci -q delete fstab.rwm || true
uci set fstab.rwm="mount"
uci set fstab.rwm.device="${ORIG}"
uci set fstab.rwm.target="/rwm"
uci commit fstab
echo "  fstab.extroot and fstab.rwm both written."
echo ""

# 7. THE STEP MISSED IN AN EARLIER MANUAL ATTEMPT — copy existing overlay
#    data across, NOW THAT fstab is already configured, so the copy
#    includes the extroot config itself (not a pre-config snapshot).
echo "[6/6] Copying current overlay config (including fstab) to new partition..."
mkdir -p /mnt/extroot-new
umount /mnt/extroot-new 2>/dev/null || true   # clean up a stale mount if a previous run was interrupted here
mount "$NEWDEV" /mnt/extroot-new
tar -C "${MOUNT}" -cf - . | tar -C /mnt/extroot-new -xf -
umount /mnt/extroot-new
echo "Copy complete."
echo ""

echo "=================================================="
echo " DONE — verify before rebooting:"
echo "   uci show fstab"
echo " Confirm fstab.extroot.uuid matches: $UUID"
echo "=================================================="
echo ""
echo "Then reboot to switch over:"
echo "  reboot"
echo ""
echo "After reboot, verify the switch actually took effect:"
echo "  grep -e /overlay /etc/mtab"
echo "  df -h /overlay /"
