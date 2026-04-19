# Flashing the EBAZ4205 (SD card)

This covers the SD-card boot path. NAND programming is a separate topic —
see the main README for background.

## Hardware prerequisite: boot-mode resistor

The board ships configured to boot from the on-board NAND flash. To make the
BootROM look at the SD card instead, you must move one resistor.

* **Remove `R2584`** (pulls MIO4 low → NAND boot).
* **Populate `R2577`** (pulls MIO4 high → SD boot).

Both are 0-Ω (or any small value) pads right next to each other on the
underside of the PCB near the Zynq. After the move, MIO5:MIO4 = 1:1, which
the Zynq BootROM decodes as *SD card boot*.

Once modified, the board will boot whatever is on the SD card.

## Build

From the Poky tree (assumes `meta-ebaz4205` and its dependencies are laid out
as described in the root README):

```bash
cd ~/yocto/poky
TEMPLATECONF=meta-ebaz4205/conf source oe-init-build-env ~/yocto/build
bitbake ebaz4205-image      # or ebaz4205-image-minimal
```

Output lands in `~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7/`:

| File | What it is |
|---|---|
| `ebaz4205-image-ebaz4205-zynq7.wic` | Full SD card image (boot + rootfs) |
| `ebaz4205-image-ebaz4205-zynq7.wic.bmap` | Sparse map for `bmaptool` |
| `boot.bin` | FSBL = U-Boot SPL + ps7_init |
| `u-boot.img` | U-Boot proper |
| `boot.scr` | U-Boot boot script (loads kernel/DTB, runs bootm) |
| `uImage` | Linux kernel (U-Boot-wrapped) |
| `zynq-ebaz4205.dtb` | Device tree for the board |

## Flash — script

```bash
~/yocto/poky/meta-ebaz4205/scripts/flash-sdcard.sh
# or with explicit device / image:
~/yocto/poky/meta-ebaz4205/scripts/flash-sdcard.sh -d /dev/sdX -i /path/to/image.wic -y
```

The script prefers `bmaptool` if available, falls back to `dd`.

## Flash — manual

```bash
DEPLOY=~/yocto/tmp/deploy/images/ebaz4205-zynq7
sudo dd if="$DEPLOY/ebaz4205-image-ebaz4205-zynq7.wic" of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

## Partition layout

Produced by `wic/ebaz4205-sdcard.wks.in`:

| # | Size | FS | Label | Contents |
|---|------|-----|-------|----------|
| 1 | 64 MiB | VFAT | `boot` | `boot.bin`, `u-boot.img`, `boot.scr`, `uImage`, `system.dtb` |
| 2 | rest | ext4 | `root` | Root filesystem |

The device tree is renamed from `zynq-ebaz4205.dtb` to `system.dtb` on the
boot partition because the stock `boot.scr` from meta-xilinx looks for that
name.

## Serial console

Three pins at the edge connector (near the Ethernet jack):

| Pin | Signal |
|---|---|
| GND | GND |
| TX  | PS MIO24 (board → host RX) |
| RX  | PS MIO25 (host → board TX) |

**115200 8N1**, 3.3 V TTL.

```bash
picocom -b 115200 /dev/ttyUSB0
```

The U-Boot banner appears ~1 second after power-up. To stop autoboot, hit
any key.

## First boot

Expected sequence:

1. Zynq BootROM loads `boot.bin` from SD → SPL runs.
2. SPL brings up DDR/MIO using our `ps7_init_gpl.[ch]` → loads `u-boot.img`.
3. U-Boot proper comes up, loads `boot.scr` from the FAT partition.
4. `boot.scr` loads `uImage` + `system.dtb` → `bootm`.
5. Kernel mounts `/dev/mmcblk0p2` as root.
6. systemd brings up the system → login prompt on `ttyPS0`.

Default login for `ebaz4205-image`: **`root`** with empty password.
