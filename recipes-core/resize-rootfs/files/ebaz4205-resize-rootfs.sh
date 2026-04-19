#!/bin/sh
# SPDX-License-Identifier: MIT
#
# First-boot rootfs resizer for EBAZ4205 SD-card images.
#
# The SD image ships with the rootfs sized to whatever Yocto decided
# at build time (~200 MiB), regardless of how big the actual card is.
# This script extends mmcblk0p2 to the end of the card and grows the
# filesystem into it. Then it tears down its own init hook (sysvinit
# symlinks and/or systemd unit) and removes itself, so subsequent
# boots skip the whole path.
#
# Idempotent: if partition 2 already reaches the end of the device,
# the resize is skipped cleanly but the self-destruct still runs.

set -e

DEV=/dev/mmcblk0
PART_NUM=2
ROOT_PART=${DEV}p${PART_NUM}
SCRIPT_PATH=/usr/bin/ebaz4205-resize-rootfs

log() { echo "[resize-rootfs] $*"; }

self_destruct() {
    log "tearing down init hooks and removing self"

    # sysvinit: remove runlevel symlinks + the init script itself.
    if [ -x /usr/sbin/update-rc.d ]; then
        update-rc.d -f ebaz4205-resize-rootfs remove >/dev/null 2>&1 || true
    fi
    rm -f /etc/rc*.d/S*ebaz4205-resize-rootfs
    rm -f /etc/rc*.d/K*ebaz4205-resize-rootfs
    rm -f /etc/init.d/ebaz4205-resize-rootfs

    # systemd: disable and drop the unit.
    if [ -x /bin/systemctl ] || [ -x /usr/bin/systemctl ]; then
        systemctl disable ebaz4205-resize-rootfs.service >/dev/null 2>&1 || true
    fi
    rm -f /lib/systemd/system/ebaz4205-resize-rootfs.service
    rm -f /etc/systemd/system/multi-user.target.wants/ebaz4205-resize-rootfs.service

    # Finally the script itself. We're past the last read of the file,
    # so deleting it while running is safe on ext4.
    rm -f "${SCRIPT_PATH}"
}

# If partition already reaches the end of the device (minus a 1 MiB
# rounding slop), we're done — nothing to resize, just clean up.
DEV_SECTORS=$(blockdev --getsz "${DEV}")
PART_END=$(parted -ms "${DEV}" unit s print 2>/dev/null \
    | awk -F: -v n="${PART_NUM}" '$1 == n { gsub("s","",$3); print $3 }')

if [ -n "${PART_END}" ] && [ "${PART_END}" -ge "$((DEV_SECTORS - 2048))" ]; then
    log "rootfs already fills the card (part end ${PART_END} / device ${DEV_SECTORS})"
    self_destruct
    exit 0
fi

# Read the starting offset of the root partition — we keep it and push
# the end outward.
PART_START=$(parted -ms "${DEV}" unit s print 2>/dev/null \
    | awk -F: -v n="${PART_NUM}" '$1 == n { gsub("s","",$2); print $2 }')
if [ -z "${PART_START}" ]; then
    log "ERROR: could not find partition ${PART_NUM} on ${DEV}"
    exit 1
fi
log "resizing ${ROOT_PART} starting at sector ${PART_START}"

# fdisk complains about reloading the partition table (rootfs is mounted)
# — expected; partprobe below nudges the kernel.
fdisk "${DEV}" <<EOF || true
p
d
${PART_NUM}
n
p
${PART_NUM}
${PART_START}

p
w
N
EOF

sync
log "notifying kernel about the new table"
partprobe "${DEV}" || true

log "growing the ext4 filesystem"
resize2fs -f "${ROOT_PART}"

log "done"
self_destruct
exit 0
