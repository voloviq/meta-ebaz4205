# Programming the EBAZ4205 NAND

The on-board 128 MiB Winbond W29N01HV NAND can be programmed in four
ways (SD + mtd-utils / TFTP / HTTP / X-Y-Kermit over UART). JTAG is
possible too but needs an external probe and is out of scope here.

This guide walks through the **SD-first + NAND-boot** flow end to end —
that's the path we actually tested on the user's hardware. TFTP, HTTP
and X/Y-Kermid procedures are covered later as alternatives.

## Partition layout

Declared in both the u-boot and kernel device trees:

| mtd# | Offset      | Size     | Label       | Content                                |
|------|-------------|----------|-------------|----------------------------------------|
| 0    | 0x00000000  | 4 MiB    | `boot`      | `boot.bin` (SPL + FSBL wrapper)        |
| 1    | 0x00400000  | 4 MiB    | `uboot`     | `u-boot.img` (FIT)                     |
| 2    | 0x00800000  | 1 MiB    | `dtb`       | `zynq-ebaz4205.dtb`                    |
| 3    | 0x00900000  | 4 MiB    | `bitstream` | `ebaz4205-base.bit` (Ethernet routing) |
| 4    | 0x00D00000  | 8 MiB    | `kernel`    | `uImage`                               |
| 5    | 0x01500000  | 107 MiB  | `ubi`       | UBI container — volume `rootfs` (UBIFS)|

---

## Method 1 — SD → NAND → reboot (the tested path)

### Step 1 — build the NAND image on the host

```bash
cd ~/yocto/build/ebaz4205-zynq7
bitbake ebaz4205-image-nand
```

Outputs land in `~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7/`:

```
ebaz4205-image-nand-ebaz4205-zynq7.rootfs.wic       # SD-card image
ebaz4205-image-nand-ebaz4205-zynq7.rootfs.ubi       # UBI container for mtd5
boot.bin  u-boot.img  uImage  zynq-ebaz4205.dtb
ebaz4205-base.bit  boot.scr
```

### Step 2 — flash the SD card and boot the board

This is standard-SD flow, just with the NAND image instead of the
minimal one (the NAND image ships `flash-nand` and `mtd-utils` on the
rootfs):

```bash
sudo dd if=~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7/ebaz4205-image-nand-ebaz4205-zynq7.rootfs.wic \
        of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Boot the board (with R2584→R2577 SD-boot resistor mod in place). Log in
over UART or SSH.

### Step 3 — get the UBI container and boot artefacts onto the target

The `.wic` already put `boot.bin`, `u-boot.img`, `uImage`,
`zynq-ebaz4205.dtb`, `ebaz4205-base.bit` and `boot.scr` on the FAT
`/boot` partition (visible at `/media/mmcblk0p1` on the running
system — that's what `IMAGE_BOOT_FILES` does). **The UBI container is
not there by default** because it's ~45–80 MiB and IMAGE_BOOT_FILES
isn't the right place for it.

Easiest way to get it on target:

```bash
# host, once the board has an IP over DHCP:
scp ~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7/ebaz4205-image-nand-ebaz4205-zynq7.rootfs.ubi \
    root@<board-ip>:/tmp/rootfs.ubi
```

### Step 4 — flash NAND from the running SD system

The `flash-nand` helper is already in `$PATH` on this image. It reads
labels from `/proc/mtd`, so DTS renames stay compatible.

```bash
# On target, via SSH or UART, still booted from SD:
cat /proc/mtd
# mtd0..mtd5 with labels: boot, uboot, dtb, bitstream, kernel, ubi

# Point flash-nand at the UBI file and go:
SRC_UBI=/tmp/rootfs.ubi flash-nand
```

What flash-nand does under the hood (for each raw partition):

```
flash_erase /dev/mtdN 0 0          # erase ENTIRE partition — MANDATORY
nandwrite  -p /dev/mtdN /tmp/nand/<artefact>
```

For the UBI partition it runs `ubiformat /dev/mtd5 -y -f rootfs.ubi`,
which does the erase internally and then writes the UBI container
including volume table.

> **Always erase before `nandwrite`.** NAND flash can only transition
> bits 1→0 on write; you need every bit at 1 (i.e. erased) before the
> data can land. `flash-nand` does this for you; if you ever run
> `nandwrite` manually, `flash_erase` has to come first or writes will
> silently corrupt.

**Expected output** (trimmed):

```
== boot → /dev/mtd0  (from /tmp/nand/boot.bin) ==
+ flash_erase /dev/mtd0 0 0
+ nandwrite -p /dev/mtd0 /tmp/nand/boot.bin
Writing data to block 0 at offset 0x0
...
== ubi → /dev/mtd5  (UBI image: /tmp/rootfs.ubi) ==
+ ubiformat /dev/mtd5 -y -f /tmp/rootfs.ubi
ubiformat: mtd5 (nand), size 112197632 bytes ...
ubiformat: formatting eraseblock 855 -- 100 % complete
Done. Contents of /proc/mtd:
mtd0 ... boot
...
mtd5 ... ubi
```

Run `flash-nand -n` first if you want a dry run, or `flash-nand --only
boot,uboot` to refresh just the bootloader pair.

### Step 5 — boot the kernel from NAND (smoke-test, before flipping boot mode)

At this point NAND is fully programmed **but the board still boots
from SD** (resistors unchanged). We want to verify NAND artefacts by
manually booting from them inside the u-boot prompt — without touching
the resistors yet.

Reset the board. During the autoboot countdown, **hit any key** to
drop into the `Zynq>` prompt. Our `CONFIG_USE_PREBOOT` has already
loaded the bitstream from SD (you'll see `fatload mmc 0 ...` +
`fpga loadb 0 ...` in the banner), so Ethernet and PL routing are
alive before you even type anything.

Type these **one line at a time** (don't paste the whole block —
some terminals split/coalesce lines weirdly and you end up with
unmatched quotes hanging on a `>` continuation prompt):

```
Zynq> mtdparts
```

Should list 6 partitions with labels `boot / uboot / dtb / bitstream /
kernel / ubi`. If it says "mtdparts variable not set", the label-based
syntax below won't work — jump straight to the hex-offset variant
below.

#### 5a. Label-based (preferred)

```
Zynq> nand read 0x100000 bitstream 0x400000
Zynq> fpga loadb 0 0x100000 ${filesize}
Zynq> nand read 0x2000000 dtb 0x100000
Zynq> nand read 0x2080000 kernel 0x800000
Zynq> setenv bootargs console=ttyPS0,115200 earlyprintk ubi.mtd=5 root=ubi0:rootfs rootfstype=ubifs rw rootwait
Zynq> bootm 0x2080000 - 0x2000000
```

#### 5b. Hex-offset fallback (if 5a complains about mtdparts)

```
Zynq> nand read 0x100000 0x900000 0x400000
Zynq> fpga loadb 0 0x100000 ${filesize}
Zynq> nand read 0x2000000 0x800000 0x100000
Zynq> nand read 0x2080000 0xD00000 0x800000
Zynq> setenv bootargs console=ttyPS0,115200 earlyprintk ubi.mtd=5 root=ubi0:rootfs rootfstype=ubifs rw rootwait
Zynq> bootm 0x2080000 - 0x2000000
```

**Key detail about `setenv`:** no quotes around the bootargs value.
u-boot's `setenv` concatenates all arguments after the variable name;
adding `'...'` or `"..."` works too, *if* the paste survives round-trip
through the serial line, but it often doesn't. Bare `setenv bootargs
console=... root=...` never gets mis-quoted.

**Memory addresses at a glance:**

| DDR address | What loads there     | Why                                             |
|-------------|----------------------|-------------------------------------------------|
| `0x0100000` | bitstream            | standard FPGA load address                      |
| `0x2000000` | DTB                  | `DEVICETREE_ADDRESS` from `zynq-generic.conf`   |
| `0x2080000` | kernel (uImage)      | `KERNEL_LOAD_ADDRESS` from `zynq-generic.conf`  |

Third `bootm` arg is DTB address; middle `-` means "no ramdisk".

#### 5c. Save as env macro for repeat use

After a successful boot you can come back to u-boot and save the whole
sequence as a single macro:

```
Zynq> setenv nandboot 'nand read 0x100000 bitstream 0x400000 && fpga loadb 0 0x100000 ${filesize} && nand read 0x2000000 dtb 0x100000 && nand read 0x2080000 kernel 0x800000 && setenv bootargs console=ttyPS0,115200 earlyprintk ubi.mtd=5 root=ubi0:rootfs rootfstype=ubifs rw rootwait && bootm 0x2080000 - 0x2000000'
Zynq> saveenv
Zynq> run nandboot
```

Note the outer `'...'` around the whole `nandboot` definition is
u-boot's "keep this as one argument" syntax — it *is* needed because
the macro contains `&&` and `setenv` with its own arguments. Inside
the macro, `setenv bootargs console=...` still has no quotes.

### Step 6 — expected boot log

```
NAND read: device 0 offset 0x900000, size 0x400000
 4194304 bytes read: OK
FPGA loadb ... (re-programming PL with NAND copy)
...
## Booting kernel from Legacy Image at 02080000 ...
   Image Name:   Linux-6.6.10-xilinx-v2024.1-...
   Image Type:   ARM Linux Kernel Image (uncompressed)
   Verifying Checksum ... OK
## Flattened Device Tree blob at 02000000
   Booting using the fdt blob at 0x2000000
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 6.6.10-xilinx-v2024.1-...
...
[    X.XXXXXX] ubi0: attaching mtd5
[    X.XXXXXX] ubi0: attached mtd5 (name "ubi", size 107 MiB)
[    X.XXXXXX] ubi0: volume 0 ("rootfs") ...
[    X.XXXXXX] VFS: Mounted root (ubifs filesystem) readonly on device 0:15.
...
Poky (Yocto Project Reference Distro) 5.0.5 ebaz4205-zynq7 /dev/ttyPS0
ebaz4205-zynq7 login:
```

### Step 7 — switch to pure NAND boot (optional, flip the resistors)

Once Step 5 works end-to-end, you can cut the SD dependency entirely:

- **Remove R2577** (MIO4 no longer pulled high)
- **Populate R2584** (MIO4 pulled low → NAND boot mode)

Reverse of the mod you did to enable SD boot. BootROM then reads
`boot.bin` from NAND offset 0, SPL pulls `u-boot.img` from NAND offset
0x00400000, and u-boot starts.

The existing `boot.cmd.ebaz4205` is still MMC-flavoured, so after
SPL→u-boot, autoboot will fall through to the u-boot prompt. Either
type `run nandboot` manually each time, or set `bootcmd` to auto-run it:

```
Zynq> setenv bootcmd 'run nandboot'
Zynq> saveenv
```

A dedicated `boot.cmd.ebaz4205-nand` compiled into a NAND-specific
`boot.scr` partition is a future enhancement — tracked in "Open items"
below.

### Common gotchas during the above

| Symptom | Cause / fix |
|---|---|
| `Zynq> >` continuation prompt after a pasted setenv | Unbalanced quote from a paste. Press `Ctrl-C` or Enter a few times, try again typing one line at a time, or bare `setenv bootargs ...` without quotes. |
| `mtdparts variable not set, see 'help mtdparts'` | MTDPARTS_DEFAULT either not compiled in (use recent u-boot from this layer) or `mtdparts` command has not run yet. `mtdparts default` re-initialises, or use hex offsets (5b). |
| `Bad Magic Number` from `bootm` | Kernel didn't land at 0x2080000 — usually `nand read` target offset or size mismatch. `iminfo 0x2080000` should show a valid uImage header. |
| Kernel panics with `Cannot open root device "ubi0:rootfs" ... error -19` | Kernel built without `CONFIG_MTD_UBI=y` / `CONFIG_UBIFS_FS=y`. Rebuild; these are enabled via `recipes-kernel/linux/config/bsp/fs/mtd.cfg` in this layer. |
| `macb: Could not attach PHY (-22)` after NAND boot | Bitstream not loaded, or the `fpga loadb` step was skipped / out of order. Make sure the bitstream load runs **before** `bootm`. |

---

## Method 2 — TFTP from u-boot

Faster than SD (seconds vs minutes) once the TFTP infrastructure is
up. See the existing TFTP section below; the u-boot side of the flash
sequence replaces `SRC_UBI=... flash-nand` with `tftpboot` +
`nand erase.part <label>` + `nand write 0x<ddr-addr> <label> ${filesize}`.

### Host setup

```bash
sudo apt install dnsmasq
# /etc/dnsmasq.d/tftp.conf:
#   enable-tftp
#   tftp-root=/home/you/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7
#   tftp-no-blocksize
sudo systemctl restart dnsmasq
```

### Target side (u-boot prompt)

```
Zynq> setenv serverip 192.168.1.10
Zynq> setenv ipaddr   192.168.1.50    # or: dhcp
Zynq> ping 192.168.1.10

Zynq> nand erase.part boot
Zynq> tftpboot 0x100000 boot.bin
Zynq> nand write 0x100000 boot ${filesize}

# repeat for u-boot.img / zynq-ebaz4205.dtb / ebaz4205-base.bit / uImage

Zynq> nand erase.part ubi
Zynq> tftpboot 0x100000 ebaz4205-image-nand-ebaz4205-zynq7.rootfs.ubi
Zynq> nand write 0x100000 ubi ${filesize}
```

Reminder: TFTP in u-boot requires the **FPGA bitstream to already be
loaded**, because the PHY sits on PL pins. Our PREBOOT fetches it from
SD at every u-boot start, so this works out of the box — you'll see
`fpga loadb ... ${filesize}` in the banner before the autoboot timer.

## Method 3 — HTTP (`wget`) from u-boot

Same shape as TFTP, simpler host side. Any web server exposing the
deploy directory will do:

```bash
cd ~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7
python3 -m http.server 8080
```

In u-boot:

```
Zynq> setenv ipaddr 192.168.1.50
Zynq> wget 0x100000 http://192.168.1.10:8080/boot.bin
Zynq> nand erase.part boot
Zynq> nand write 0x100000 boot ${filesize}
# repeat
```

Requires `CONFIG_CMD_WGET=y` — set in our u-boot bbappend.

## Method 4 — UART only (X / Y / Kermit), no network

If both SD and Ethernet are unavailable (e.g. recovery from a bricked
boot partition where `boot.cmd.ebaz4205-nand` doesn't yet do the
PREBOOT-equivalent).

### picocom + Ymodem example

```bash
picocom -b 115200 /dev/ttyUSB0 --send-cmd "sb -vv"
```

u-boot:

```
Zynq> loady 0x100000
## Ready for binary (ymodem) download to 0x00100000...
```

In picocom: `Ctrl-A Ctrl-S`, choose file (`boot.bin`), Enter. Wait.
Then flash as usual:

```
Zynq> nand erase.part boot
Zynq> nand write 0x100000 boot ${filesize}
```

`loadx` (Xmodem) and `loadb` (Kermit) are also available. Avoid doing
the rootfs this way — at 115200, 80 MiB takes ~2 h. Use SD / TFTP / HTTP
for the UBI partition; serial is for tiny partitions in recovery only.

---

## Verifying NAND contents

```bash
# on the target, booted from anywhere:
cat /proc/mtd                              # labels + sizes
nanddump -l 64 /dev/mtd0 | hexdump -C -n 64  # first 64 B of boot.bin
# ...should start 00 09 0f f0 0f f0 0f f0 0f f0 00 00 01 61 ...
ubiattach -p /dev/mtd5
ls /dev/ubi0_*                             # volumes after attach
mount -t ubifs ubi0:rootfs /mnt
ls /mnt                                    # sanity-check rootfs
```

---

## Open items

- [ ] `boot.cmd.ebaz4205-nand` — u-boot script that loads kernel / DTB
      / bitstream from NAND instead of MMC, so a pure NAND boot
      (R2584 populated / R2577 removed) runs without the user having
      to `run nandboot` at the u-boot prompt.
- [ ] SPL-side `CONFIG_SPL_NAND_SUPPORT` + `CONFIG_SYS_NAND_U_BOOT_OFFS
      = 0x00400000` so SPL can fetch `u-boot.img` from the `uboot` NAND
      partition after BootROM loads `boot.bin` from offset 0.
- [ ] JTAG flashing (OpenOCD / XSCT) — deferred, not needed for the
      SD-first flow.
