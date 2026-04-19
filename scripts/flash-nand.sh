#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Flash an EBAZ4205 NAND from a running (SD-booted) system.
#
# Expected layout (must match the device tree in the running kernel):
#   mtd0 boot       4 MiB    boot.bin
#   mtd1 uboot      4 MiB    u-boot.img
#   mtd2 dtb        1 MiB    zynq-ebaz4205.dtb
#   mtd3 bitstream  4 MiB    ebaz4205-base.bit
#   mtd4 kernel     8 MiB    uImage
#   mtd5 ubi      107 MiB    UBI container (rootfs volume)
#
# Source files default to /boot (where the FAT partition is mounted at
# /media/mmcblk0p1 OR the image files were copied). Override per-file
# via environment variables or pass an alternate source directory as the
# first argument.
#
# Usage:
#   flash-nand.sh                        # use defaults
#   flash-nand.sh /path/to/boot-files    # override source dir
#   flash-nand.sh -n                     # dry run (print commands only)
#   flash-nand.sh --skip-rootfs          # flash only boot partitions
#   flash-nand.sh --only boot,uboot      # flash selected partitions only

set -eu

DRY_RUN=0
SKIP_ROOTFS=0
ONLY=""
SRC_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run)   DRY_RUN=1; shift ;;
        --skip-rootfs)  SKIP_ROOTFS=1; shift ;;
        --only)         ONLY="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,28p' "$0"; exit 0 ;;
        -*)
            echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            SRC_DIR="$1"; shift ;;
    esac
done

# Source-file locations. Callers can override any of them via env.
: "${SRC_DIR:=/media/mmcblk0p1}"
: "${SRC_BOOT:=${SRC_DIR}/boot.bin}"
: "${SRC_UBOOT:=${SRC_DIR}/u-boot.img}"
: "${SRC_DTB:=${SRC_DIR}/zynq-ebaz4205.dtb}"
: "${SRC_BITSTREAM:=${SRC_DIR}/ebaz4205-base.bit}"
: "${SRC_KERNEL:=${SRC_DIR}/uImage}"
# UBI image — default looks in /srv/nand or the SD boot partition.
: "${SRC_UBI:=${SRC_DIR}/ebaz4205-image-minimal-ebaz4205-zynq7.rootfs.ubi}"
if [ ! -f "$SRC_UBI" ] && [ -f /srv/nand/rootfs.ubi ]; then
    SRC_UBI=/srv/nand/rootfs.ubi
fi

# MTD node names — pulled from /proc/mtd labels, so layout renames
# don't break the script.
mtd_for() {
    awk -v label="$1" '
        /^mtd/ {
            gsub(/[:]/, "", $1)
            gsub(/["]/, "", $4)
            if ($4 == label) { print "/dev/" $1; exit }
        }' /proc/mtd
}

run() {
    echo "+ $*"
    if [ "$DRY_RUN" -eq 0 ]; then
        "$@"
    fi
}

flash_raw() {
    label="$1"
    src="$2"
    dev=$(mtd_for "$label")
    if [ -z "$dev" ]; then
        echo "ERROR: no MTD partition labelled '$label' — wrong DTS?" >&2
        exit 1
    fi
    if [ ! -f "$src" ]; then
        echo "ERROR: source file '$src' not found" >&2
        exit 1
    fi
    echo "== $label → $dev  (from $src) =="
    run flash_erase "$dev" 0 0
    run nandwrite -p "$dev" "$src"
}

flash_ubi() {
    label="$1"
    src="$2"
    dev=$(mtd_for "$label")
    if [ -z "$dev" ]; then
        echo "ERROR: no MTD partition labelled '$label' — wrong DTS?" >&2
        exit 1
    fi
    if [ ! -f "$src" ]; then
        echo "ERROR: UBI image '$src' not found" >&2
        exit 1
    fi
    echo "== $label → $dev  (UBI image: $src) =="
    run ubiformat "$dev" -y -f "$src"
}

should_flash() {
    if [ -z "$ONLY" ]; then return 0; fi
    case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

echo "Source dir : $SRC_DIR"
echo "Dry run    : $DRY_RUN"
echo "Skip rootfs: $SKIP_ROOTFS"
echo "Only       : ${ONLY:-<all>}"
echo

should_flash boot      && flash_raw boot      "$SRC_BOOT"
should_flash uboot     && flash_raw uboot     "$SRC_UBOOT"
should_flash dtb       && flash_raw dtb       "$SRC_DTB"
should_flash bitstream && flash_raw bitstream "$SRC_BITSTREAM"
should_flash kernel    && flash_raw kernel    "$SRC_KERNEL"

if [ "$SKIP_ROOTFS" -eq 0 ] && should_flash ubi; then
    flash_ubi ubi "$SRC_UBI"
fi

echo
echo "Done. Contents of /proc/mtd:"
cat /proc/mtd
