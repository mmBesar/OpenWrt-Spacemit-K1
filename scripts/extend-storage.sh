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
# This has NOT been end-to-end tested on real hardware as a script (only
# the equivalent manual steps have been, on an RV2 SD card). Review the
# echoed disk/partition info carefully before typing "yes".
#
# Usage: sh extend-storage.sh

set -e

echo "=== extend-storage.sh ==="
echo ""

# 0. Sanity check required tools are present
for tool in block parted mkfs.ext4; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: '$tool' not found. This image doesn't have the needed" >&2
    echo "packages baked in. Rebuild from the current workflow rather than" >&2
    echo "trying to 'apk add' it live — see README's Known Caveats." >&2
    exit 1
  }
done

# 1. Identify the root device (the disk backing /rom) and its base disk
ROOTDEV=$(block info | sed -n -e '/MOUNT="\/rom"/s/:.*//p')
if [ -z "$ROOTDEV" ]; then
  echo "ERROR: could not detect root device automatically. Aborting." >&2
  exit 1
fi
case "$ROOTDEV" in
  *mmcblk*p*) DISK=$(echo "$ROOTDEV" | sed 's/p[0-9]*$//') ;;
  *[0-9])     DISK=$(echo "$ROOTDEV" | sed 's/[0-9]*$//') ;;
  *)          DISK="$ROOTDEV" ;;
esac

echo "Detected root partition: $ROOTDEV"
echo "Detected disk:           $DISK"
echo ""

# 2. Fix a stale/corrupt backup GPT if present (normal for any OS image
#    written to bigger media than it was built for — non-destructive,
#    uses the known-good primary table as the source of truth)
parted -s "$DISK" ---pretend-input-tty print <<EOF
OK
Fix
EOF

# 3. Find the end of the last existing partition
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

# 4. Create and format the new partition
parted -s "$DISK" unit s mkpart extroot ext4 "${STARTSEC}s" 100%
sleep 1

NEWNUM=$(parted -s "$DISK" print | awk '/extroot/ {print $1}')
case "$DISK" in
  *mmcblk*) NEWDEV="${DISK}p${NEWNUM}" ;;
  *)        NEWDEV="${DISK}${NEWNUM}" ;;
esac

echo "New partition created: $NEWDEV"
mkfs.ext4 -L extroot "$NEWDEV"

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

# 6. THE STEP MISSED IN AN EARLIER MANUAL ATTEMPT — copy existing overlay
#    data across BEFORE switching fstab over, so config isn't lost.
echo "Copying current overlay contents to new partition..."
mkdir -p /mnt/extroot-new
mount "$NEWDEV" /mnt/extroot-new
tar -C "${MOUNT}" -cf - . | tar -C /mnt/extroot-new -xf -
umount /mnt/extroot-new
echo "Copy complete."
echo ""

# 7. Configure extroot, preserving access to the original overlay as a
#    fallback (in case anything ever needs recovering from it directly)
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

echo "=== Done ==="
echo "fstab configured. Config copied. Reboot to switch over:"
echo "  reboot"
echo ""
echo "After reboot, verify with:"
echo "  grep -e /overlay /etc/mtab"
echo "  df -h /overlay /"
