# Programming the EBAZ4205 NAND

The on-board 128 MiB Winbond W29N01HV NAND can be programmed in
four ways, all supported by this layer (JTAG is possible too but needs
an external probe and is outside the scope here). Pick the one that
matches what you already have wired up.

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

## Build the NAND image

```bash
cd ~/yocto/build/ebaz4205-zynq7
bitbake ebaz4205-image-nand
```

Outputs in `~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7/`:

```
ebaz4205-image-nand-ebaz4205-zynq7.rootfs.wic          # SD image
ebaz4205-image-nand-ebaz4205-zynq7.rootfs.ubi          # UBI (→ mtd5)
ebaz4205-image-nand-ebaz4205-zynq7.rootfs.ubifs        # raw UBIFS
boot.bin  u-boot.img  uImage  zynq-ebaz4205.dtb  ebaz4205-base.bit
```

## Method 1 — SD + `flash-nand` (recommended first time)

**Why:** no extra host setup, no risk of bricking the board (SD stays
bootable if NAND programming fails).

```bash
# host: write SD with the NAND image, which also ships flash-nand
sudo dd if=.../ebaz4205-image-nand-ebaz4205-zynq7.rootfs.wic of=/dev/sdX bs=4M conv=fsync
sync
```

Put the UBI container within reach of the running board — either drop
it on the FAT boot partition before unmounting, or `scp` it later:

```bash
# option A: copy to SD /boot partition on host (easy to find as /media/mmcblk0p1 on target)
sudo mount /dev/sdX1 /mnt && \
sudo cp .../ebaz4205-image-nand-ebaz4205-zynq7.rootfs.ubi /mnt/rootfs.ubi && \
sync && sudo umount /mnt

# option B: after boot, scp from host to running target
scp .../ebaz4205-image-nand-ebaz4205-zynq7.rootfs.ubi root@<board-ip>:/tmp/rootfs.ubi
```

On the target (booted from SD):

```
cat /proc/mtd                  # verify mtd0..mtd5 with labels

flash-nand                     # programs every partition from /media/mmcblk0p1
# or:
SRC_UBI=/tmp/rootfs.ubi flash-nand
flash-nand --only boot,uboot   # selective
flash-nand -n                  # dry run
```

The script reads labels from `/proc/mtd`, so renaming partitions in
the DTS doesn't break it.

## Method 2 — TFTP from u-boot (fastest over Ethernet)

**Why:** ~10 s for the whole NAND vs ~2 min SD copy + flash cycle.
Best for iterating on u-boot itself.

> **Ethernet in u-boot requires the FPGA bitstream** (the PHY is wired
> to PL, not MIO — see `docs/scarthgap-fixes.md` #18). This layer
> handles that for you: `CONFIG_USE_PREBOOT` is set so the very first
> thing u-boot does on every start is
> ```
> if test -e mmc 0:1 /ebaz4205-base.bit; then
>     fatload mmc 0 0x100000 /ebaz4205-base.bit && \
>     fpga loadb 0 0x100000 ${filesize}
> fi
> ```
> ...which loads the bitstream from the FAT partition regardless of
> whether autoboot proceeds to the kernel or you break into the u-boot
> prompt. You'll see one or two lines of FPGA programming output in
> the u-boot banner.
>
> If you're booting from NAND (no SD) and the bitstream is already in
> its own NAND partition, the preboot needs rewriting to `nand read`
> instead — not yet wired up, file under "Open items".

### Host side

Install a TFTP server, pointed at the Yocto deploy directory:

```bash
# Debian/Ubuntu
sudo apt install dnsmasq
# /etc/dnsmasq.d/tftp.conf:
#   enable-tftp
#   tftp-root=/home/you/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7
#   tftp-no-blocksize    # some Zynq u-boots dislike large blocks
sudo systemctl restart dnsmasq

# alternative: atftpd (no DHCP involvement)
sudo apt install atftpd
sudo atftpd --daemon --no-fork --port 69 \
    /home/you/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7
```

### Target side (u-boot console)

Interrupt autoboot (any key during the 3-second window):

```
Zynq> setenv serverip 192.168.1.10     # your host IP
Zynq> setenv ipaddr 192.168.1.50       # target IP (or use dhcp)
Zynq> ping 192.168.1.10

# boot partition
Zynq> nand erase.part boot
Zynq> tftpboot 0x100000 boot.bin
Zynq> nand write 0x100000 boot ${filesize}

# u-boot proper
Zynq> nand erase.part uboot
Zynq> tftpboot 0x100000 u-boot.img
Zynq> nand write 0x100000 uboot ${filesize}

# DTB
Zynq> nand erase.part dtb
Zynq> tftpboot 0x100000 zynq-ebaz4205.dtb
Zynq> nand write 0x100000 dtb ${filesize}

# bitstream
Zynq> nand erase.part bitstream
Zynq> tftpboot 0x100000 ebaz4205-base.bit
Zynq> nand write 0x100000 bitstream ${filesize}

# kernel
Zynq> nand erase.part kernel
Zynq> tftpboot 0x100000 uImage
Zynq> nand write 0x100000 kernel ${filesize}

# rootfs (UBI container)
Zynq> nand erase.part ubi
Zynq> tftpboot 0x100000 ebaz4205-image-nand-ebaz4205-zynq7.rootfs.ubi
Zynq> nand write 0x100000 ubi ${filesize}
```

> `nand erase.part` and `nand write ... <label>` use partition labels
> from the DTS, not hex offsets — safer than hard-coding offsets.

### Save env for next time

```
Zynq> setenv serverip 192.168.1.10
Zynq> setenv ipaddr 192.168.1.50
Zynq> saveenv
```

## Method 3 — HTTP (wget) from u-boot

**Why:** simpler host setup than TFTP — any web server works.

### Host side

```bash
cd ~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7
python3 -m http.server 8080
```

### Target side (u-boot console)

```
Zynq> setenv ipaddr 192.168.1.50
Zynq> setenv serverip 192.168.1.10

Zynq> wget 0x100000 http://192.168.1.10:8080/boot.bin
Zynq> nand erase.part boot
Zynq> nand write 0x100000 boot ${filesize}

# repeat for u-boot.img, uImage, zynq-ebaz4205.dtb, ebaz4205-base.bit, rootfs.ubi
```

Needs `CONFIG_CMD_WGET=y` — enabled in this layer's u-boot bbappend.

## Method 4 — Serial only (X/Y/Kermit), no network

**Why:** the only option if both SD and Ethernet are unavailable —
typically when debugging a partially bricked board.

Our u-boot ships three variants: **Kermit** (`loadb`, default serial
speed), **Xmodem** (`loadx`), **Ymodem** (`loady`). Ymodem is the
friendliest — most terminal programs support it and it verifies CRC.

### Xmodem with `picocom`

Host: start `picocom`, then press `Ctrl-A, Ctrl-S` to start a send
and pick `sx` (Xmodem) or `sb` (Ymodem):

```bash
picocom -b 115200 /dev/ttyUSB0 --send-cmd "sx -vv"
```

On target (u-boot console):

```
Zynq> loadx 0x100000 115200
## Ready for binary (xmodem) download to 0x00100000 at 115200 bps...
```

Back in picocom: `Ctrl-A Ctrl-S`, type `boot.bin`, press Enter. Wait
(~3 min for 2 MiB at 115200).

```
Zynq> nand erase.part boot
Zynq> nand write 0x100000 boot ${filesize}
```

Repeat for every partition. **Avoid** doing the 80 MiB rootfs this way —
at 115200 baud it takes ~2 h. Use this method for boot/uboot/dtb/kernel
only; flash rootfs via TFTP/HTTP/SD.

### Higher serial baud rates

If the host UART supports it and you need to push more data, bump the
console on both sides (u-boot end via `setenv baudrate 921600 && saveenv
&& reset`, host via `picocom -b 921600`). Some adapters are flaky above
921600; most FT232 can do 3 Mbaud.

## Switching to NAND boot (optional, later)

The board currently boots from SD (R2577 populated, R2584 empty).
To flip to NAND boot once the NAND is programmed:

- **Remove R2577**
- **Populate R2584**

Reverse of the mod you did to enable SD boot. Zynq BootROM then reads
`boot.bin` from NAND offset 0, SPL pulls `u-boot.img` from offset
0x00400000, and u-boot runs.

> **Not yet implemented in this layer:** the u-boot boot script
> (`boot.cmd.ebaz4205`) is hard-coded to MMC. A NAND-boot variant
> needs a dedicated `boot.cmd.ebaz4205-nand` that does
> `nand read`s instead of `fatload mmc`s. Track this in
> `docs/scarthgap-fixes.md` "Open items".

## Verifying the flash

```bash
# on the target, regardless of flashing method
cat /proc/mtd
nanddump -l 64 /dev/mtd0 | hexdump -C -n 64    # should show Xilinx boot header

# UBI
ubiattach -p /dev/mtd5
ls /dev/ubi0_*        # rootfs volume
mount -t ubifs ubi0:rootfs /mnt
ls /mnt               # sanity-check rootfs
```

`nanddump` header on mtd0 should start with the Xilinx ROM magic
bytes `00 09 0f f0 ... 00 00 01 61` (the boot.bin format header) —
same bytes you see on `xxd /boot/boot.bin`.
