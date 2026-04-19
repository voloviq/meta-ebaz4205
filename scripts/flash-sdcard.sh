#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Write an EBAZ4205 .wic image to an SD card.
#
# Usage:
#   flash-sdcard.sh [-d /dev/sdX] [-i <image.wic>] [-y]
#
# Defaults to looking for the image under
#   $TMPDIR/deploy/images/ebaz4205-zynq7/ebaz4205-image-ebaz4205-zynq7.wic
# where $TMPDIR defaults to ~/yocto/tmp.

set -euo pipefail

TMPDIR_DEFAULT="${HOME}/yocto/tmp-ebaz4205-zynq7"
DEPLOY_DEFAULT="${TMPDIR_DEFAULT}/deploy/images/ebaz4205-zynq7"

IMAGE=""
DEV=""
ASSUME_YES=0

usage() {
    sed -n '2,11p' "$0"
    exit "${1:-0}"
}

while getopts ":d:i:yh" opt; do
    case "$opt" in
        d) DEV="$OPTARG" ;;
        i) IMAGE="$OPTARG" ;;
        y) ASSUME_YES=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

if [ -z "$IMAGE" ]; then
    IMAGE="${DEPLOY_DEFAULT}/ebaz4205-image-ebaz4205-zynq7.wic"
    if [ ! -f "$IMAGE" ]; then
        IMAGE="${DEPLOY_DEFAULT}/ebaz4205-image-minimal-ebaz4205-zynq7.wic"
    fi
fi

if [ ! -f "$IMAGE" ]; then
    echo "Image not found. Pass -i <path> or build with:" >&2
    echo "    bitbake ebaz4205-image" >&2
    exit 1
fi

if [ -z "$DEV" ]; then
    echo "Available removable block devices:"
    lsblk -dno NAME,SIZE,MODEL,TRAN | awk '$4=="usb" || $4=="mmc"{printf "  /dev/%s  %s  %s  (%s)\n",$1,$2,$3,$4}'
    echo
    read -r -p "Target device (e.g. /dev/sdX or /dev/mmcblk0): " DEV
fi

if [ ! -b "$DEV" ]; then
    echo "'$DEV' is not a block device." >&2
    exit 1
fi

if grep -qE "^${DEV//\//\\/}[0-9p]* " /proc/mounts; then
    echo "Partitions of $DEV are mounted. Unmount them first." >&2
    exit 1
fi

echo
echo "About to write:  $IMAGE"
echo "           to:   $DEV  ($(lsblk -dno SIZE "$DEV"))"
echo
echo "This will DESTROY all data on $DEV."
if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Type 'yes' to continue: " ans
    if [ "$ans" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
fi

BMAP="${IMAGE}.bmap"
if command -v bmaptool >/dev/null 2>&1 && [ -f "$BMAP" ]; then
    echo "Using bmaptool (with $BMAP)"
    sudo bmaptool copy --bmap "$BMAP" "$IMAGE" "$DEV"
else
    echo "Using dd"
    sudo dd if="$IMAGE" of="$DEV" bs=4M status=progress conv=fsync
fi

sudo sync
echo
echo "Done. You can now remove the SD card and boot the board."
