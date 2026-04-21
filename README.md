# meta-ebaz4205

Yocto/OpenEmbedded BSP layer for the **Ebang EBAZ4205** — a Xilinx Zynq-7010
board originally sold as a cryptominer controller and widely recycled as a
cheap Zynq-7000 development platform.

Targets **Yocto scarthgap** with `linux-xlnx` 6.6 LTS and `u-boot-xlnx` 2024.01
from the meta-xilinx scarthgap branch. No Vivado / XSA dependency — the
device tree is mainline-style and the U-Boot SPL is built from source using
board-specific `ps7_init_gpl.[ch]` checked into this layer.

**Status:** boots to a Poky 5.0 userland login over UART1 from SD card
(NAND-boot is not feasible with the current upstream — see below), with:

- **Ethernet** via a shipped FPGA bitstream that routes PS GEM0 through
  EMIO to the on-board IP101GA PHY (the PHY is wired to PL pins, not
  MIO — so no bitstream, no Ethernet).
- **Two on-board LEDs** (W13, W14 in PL bank 34) wired to the same EMIO
  GPIO passthrough and exposed through the kernel `gpio-leds` driver,
  with heartbeat + CPU-load triggers on by default.
- **NAND flash** partitioned for raw-boot (boot / uboot / dtb /
  bitstream / kernel) plus a 107 MiB UBI/UBIFS rootfs, programmable
  from SD-booted Linux via `flash-nand` or from the u-boot prompt via
  TFTP / HTTP / Y-Kermit.

See `docs/scarthgap-fixes.md` for the full list of workarounds applied
against upstream meta-xilinx scarthgap regressions, `docs/flashing-nand.md`
for the tested SD → NAND → boot flow, and `hardware/README.md` for the
Vivado project that produces the bitstream.

---

## Supported Hardware

| Board | SoC | RAM | Flash | Status |
|-------|-----|-----|-------|--------|
| EBAZ4205 | Zynq 7Z010 (dual Cortex-A9 + Artix-7 PL) | 256 MB DDR3 | 128 MB SLC NAND | Supported (SD-boot only) |

### Board notes

- Two hardware variants exist: one with a populated PHY oscillator, one
  without. Tested on the **variant without** the PHY oscillator (the PHY
  is clocked from FCLK0 at 25 MHz — see the `assigned-clocks` entry in
  the device tree).
- The FPGA side (PL) carries a minimal bitstream
  (`recipes-bsp/bitstream/files/ebaz4205-base.bit`, GPL-3.0-or-later,
  imported from `nightseas/ebit_z7010`). It routes GEM0 EMIO to the
  Ethernet PHY pins; no user logic in PL.
- Early debug UART is enabled (`CONFIG_DEBUG_UART=y`) so SPL prints a
  `<debug_uart>` banner as soon as the ps7_init finishes — useful when
  diagnosing DDR or clock problems on a board revision that doesn't match
  the checked-in `ps7_init_gpl`.

---

## Quick Start

### Step 1 — Host dependencies

Scarthgap's host requirements, verified on Ubuntu 22.04 / 24.04:

```bash
sudo apt update
sudo apt install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    python3-subunit zstd liblz4-tool file locales libacl1 \
    u-boot-tools bmap-tools

sudo locale-gen en_US.UTF-8
```

### Step 2 — Directory structure

```bash
mkdir -p ~/yocto
cd ~/yocto
```

### Step 3 — Clone the required layers (all on `scarthgap`)

```bash
cd ~/yocto

git clone -b scarthgap git://git.yoctoproject.org/poky
git clone -b scarthgap git://git.openembedded.org/meta-openembedded   poky/meta-openembedded
git clone -b scarthgap https://github.com/Xilinx/meta-xilinx.git      poky/meta-xilinx-core  --config advice.detachedHead=false
git clone -b scarthgap https://github.com/Xilinx/meta-xilinx.git      poky/meta-xilinx-bsp

# meta-ebaz4205 itself
git clone -b scarthgap <this-repo>                                    poky/meta-ebaz4205
```

*(Note: `meta-xilinx-core` and `meta-xilinx-bsp` are sibling directories
within the `meta-xilinx` monorepo. Either clone the monorepo once into
`poky/meta-xilinx/` and reference both sub-layers in `bblayers.conf`, or —
as above — two shallow clones.)*

Final layout:

```
~/yocto/
└── poky/
    ├── meta/
    ├── meta-poky/
    ├── meta-yocto-bsp/
    ├── meta-openembedded/
    │   ├── meta-oe/
    │   ├── meta-python/
    │   └── meta-networking/
    ├── meta-xilinx-core/
    ├── meta-xilinx-bsp/
    └── meta-ebaz4205/           # this layer
```

### Step 4 — Initialise the build environment

This layer ships a `conf/.templateconf`, so:

```bash
cd ~/yocto/poky
TEMPLATECONF=meta-ebaz4205/conf source oe-init-build-env ~/yocto/build
```

The first invocation seeds `~/yocto/build/conf/{local.conf,bblayers.conf}`
from the samples in `meta-ebaz4205/conf/templates/default/`.

`local.conf` points `DL_DIR` and `SSTATE_DIR` at `~/yocto/downloads` and
`~/yocto/sstate-cache` so they are shared with any other Yocto machines
you may be building under `~/yocto/`. `TMPDIR` is per-machine
(`~/yocto/tmp-ebaz4205-zynq7/`) to avoid collisions with parallel builds.

### Step 5 — Build

```bash
cd ~/yocto/build
bitbake ebaz4205-image
```

Common targets:

- `ebaz4205-image-minimal` — boots to a serial login, nothing else.
- `ebaz4205-image` — minimal + SSH, package manager, common debug tools.

First build takes 1–3 h depending on the host; subsequent builds use sstate.

### Step 6 — Flash to SD card

> Before the first SD boot, one 0-Ω resistor must be moved on the PCB —
> see `docs/flashing.md`. Stock boards boot from NAND.

```bash
# script picks up the latest wic from tmp/deploy/images/ebaz4205-zynq7/
~/yocto/poky/meta-ebaz4205/scripts/flash-sdcard.sh -d /dev/sdX

# or manual:
sudo dd if=~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7/ebaz4205-image-ebaz4205-zynq7.wic \
        of=/dev/sdX bs=4M status=progress conv=fsync
```

### Step 7 — First boot

Serial console on **MIO24 (TX) / MIO25 (RX)**, 3.3 V TTL, **115200 8N1**.

```bash
picocom -b 115200 /dev/ttyUSB0
```

Default login: `root` with empty password. Drop the empty password by
removing `debug-tweaks` / `empty-root-password` from the image recipe.

### LEDs

The two on-board LEDs (green, red) are wired to PL pins W13 and W14
and routed through EMIO by the shipped bitstream. The kernel exposes
them as:

```
/sys/class/leds/ebaz4205:green:heartbeat   # default trigger: heartbeat
/sys/class/leds/ebaz4205:red:cpu           # default trigger: cpu
```

They start pulsing / blinking immediately on boot — no user-space
setup required. To change triggers, for example ethernet activity on
the red LED:

```bash
cat /sys/class/leds/ebaz4205:red:cpu/trigger           # see all triggers
echo netdev > /sys/class/leds/ebaz4205:red:cpu/trigger
echo eth0   > /sys/class/leds/ebaz4205:red:cpu/device_name
echo 1      > /sys/class/leds/ebaz4205:red:cpu/link
echo 1      > /sys/class/leds/ebaz4205:red:cpu/tx
echo 1      > /sys/class/leds/ebaz4205:red:cpu/rx
```

Drive them directly by disabling the trigger:

```bash
echo none > /sys/class/leds/ebaz4205:green:heartbeat/trigger
echo 1    > /sys/class/leds/ebaz4205:green:heartbeat/brightness    # on
echo 0    > /sys/class/leds/ebaz4205:green:heartbeat/brightness    # off
```

LEDs are active-low on the board; the DTS sets `GPIO_ACTIVE_LOW` so
brightness `1` means physically lit.

### SSH access

Both image targets ship an OpenSSH server. Once the board is up and has
pulled an IP via DHCP:

```bash
ssh root@<board-ip>        # empty password
scp file root@<board-ip>:/  # also works out-of-the-box (sftp-server installed)
```

Root login and empty passwords are enabled in both images for development;
production builds should strip `empty-root-password` / `allow-root-login`
from `IMAGE_FEATURES` and create a proper user via a custom recipe.

---

## Partition Layout (SD card)

| # | Size | FS | Label | Contents |
|---|------|-----|-------|----------|
| 1 | 64 MiB | VFAT | `boot` | `boot.bin`, `u-boot.img`, `boot.scr`, `uImage`, `system.dtb` |
| 2 | rest | ext4 | `root` | Root filesystem |

The DTB is renamed `zynq-ebaz4205.dtb → system.dtb` on the boot partition so
the stock `boot.scr` from meta-xilinx finds it.

Full boot chain: Zynq BootROM → `boot.bin` (SPL with our `ps7_init_gpl`) →
`u-boot.img` (U-Boot proper) → `boot.scr` → `uImage` + `system.dtb` → Linux.

See `docs/flashing.md` for details, offsets and troubleshooting.

---

## Rebuild after changes

```bash
cd ~/yocto/build

# Full image
bitbake ebaz4205-image

# Just the kernel
bitbake linux-xlnx -c cleansstate && bitbake ebaz4205-image

# Just U-Boot
bitbake u-boot-xlnx -c cleansstate && bitbake ebaz4205-image

# Edit kernel config interactively
bitbake linux-xlnx -c menuconfig
```

---

## Layer Structure

```
meta-ebaz4205/
├── conf/
│   ├── layer.conf
│   ├── .templateconf
│   ├── local.conf.sample
│   ├── bblayers.conf.sample
│   └── machine/ebaz4205-zynq7.conf
├── docs/flashing.md
├── scripts/flash-sdcard.sh
├── wic/ebaz4205-sdcard.wks.in
├── recipes-bsp/
│   ├── platform-init/              # ps7_init_gpl.[ch] — DDR/MIO/PLL setup
│   └── u-boot/                     # U-Boot DTS + defconfig tweaks
├── recipes-core/
│   ├── base-files/                 # /etc/fstab override (mounts /boot)
│   └── images/
│       ├── ebaz4205-image-minimal.bb
│       └── ebaz4205-image.bb
└── recipes-kernel/
    └── linux/
        ├── linux-xlnx_%.bbappend
        └── config/bsp/             # kernel config fragments (eth, mtd)
```

---

## Software Versions

| Component | Version | Source |
|-----------|---------|--------|
| Yocto | Scarthgap (5.0) | [yoctoproject.org](https://www.yoctoproject.org/) |
| Linux kernel | 6.6.10 (`xlnx_rebase_v6.6_LTS`) | [Xilinx/linux-xlnx](https://github.com/Xilinx/linux-xlnx) |
| U-Boot | v2024.01 (`xlnx_rebase_v2024.01`) | [Xilinx/u-boot-xlnx](https://github.com/Xilinx/u-boot-xlnx) |
| Compiler | GCC 13.x | Yocto scarthgap toolchain |

Device tree: `arch/arm/boot/dts/xilinx/zynq-ebaz4205.dts` — upstream kernel,
originally contributed by Michael Walle.

`ps7_init_gpl.[ch]` was exported by Vivado for the EBAZ4205 and is checked
into `recipes-bsp/platform-init/files/`. It encodes DDR timings, clocks and
MIO pinmux for this specific board; needed because U-Boot's stock
`xilinx_zynq_virt_defconfig` targets ZC706 and its PS7 init does not match.

---

## Board Modification for SD Boot

Stock EBAZ4205 boots from NAND. Changing the boot-mode resistors lets the
Zynq BootROM load from SD:

- **Remove R2584** (pulls MIO4 low → NAND)
- **Populate R2577** (pulls MIO4 high → SD)

Both resistors are 0-Ω pads adjacent to each other on the underside of the
PCB near the Zynq. No other modification needed.

---

## NAND boot (not feasible with upstream u-boot-xlnx 2024.01)

Enabling `CONFIG_SPL_NAND_SUPPORT=y` on this tree produces a clean Kconfig
build but fails SPL link with undefined references to `nand_spl_load_image`,
`nand_spl_adjust_offset`, `nand_init`, `nand_register`, `nand_calculate_ecc`,
`nand_correct_data`, `nand_deselect`. Reason: **u-boot-xlnx 2024.01 does not
ship an SPL NAND loader for Zynq 7000.** `nand_spl_load_image()` is provided
only for Denali / DaVinci / FSL / MXC / MXS / Sunxi / LPC / MT7621; `zynq_nand.c`
has only the full-u-boot driver, no SPL variant. `meta-xilinx` does not add
one either — the canonical Xilinx path for NAND boot is FSBL (not u-boot SPL),
via `meta-xilinx-standalone`'s `fsbl-firmware` recipe, which this layer
explicitly opts out of (`EXTRA_IMAGEDEPENDS:remove = "virtual/fsbl"`).

Three realistic paths if true NAND-boot is required later:

1. **FSBL** — add `meta-xilinx-standalone` to `bblayers.conf`, stop removing
   `virtual/fsbl`, arrange a baremetal (`arm-none-eabi`) multilib / TCLIBC
   so `fsbl-firmware_generic.inc` can compile. Largest setup cost, canonical.
2. **Write a Zynq SPL NAND loader** — provide `nand_spl_load_image()`,
   `nand_init()`, etc. against the zynq NAND controller. ~200–400 lines of
   C, chip-specific (Micron/Hynix variant + geometry + timings must be
   known for the exact board revision).
3. **Keep the hybrid** — boot via SD (SPL + u-boot.img on the FAT partition),
   use NAND only as rootfs storage (UBIFS on the `ubi` partition). `flash-nand`
   on the target already does the userspace programming; no boot-mode resistor
   change needed on the board. This is the currently-shipped path.

Until one of 1/2 lands, this layer only produces SD images.

---

## Expected boot output

Serial console at 115200 8N1 after power-on:

```
<debug_uart>
U-Boot SPL 2024.01 (May 14 2024 - ...)
Silicon version:        3
Trying to boot from MMC1
spl_load_image_fat_os: error reading image system.dtb, err - -2    ← harmless

<debug_uart>
U-Boot 2024.01 (May 14 2024 - ...)
CPU:   Zynq 7z010
Silicon: v3.1
Model: Ebang EBAZ4205
DRAM:  ECC disabled 256 MiB
NAND:  128 MiB
MMC:   mmc@e0100000: 0
...
Hit any key to stop autoboot:  0
== EBAZ4205 boot.scr ==
## Booting kernel from Legacy Image at 00200000 ...
...
Booting Linux on physical CPU 0x0
Linux version 6.6.10-xilinx-v2024.1 ...
OF: fdt: Machine model: Ebang EBAZ4205
...
Poky (Yocto Project Reference Distro) 5.0.5 ebaz4205-zynq7 /dev/ttyPS0
ebaz4205-zynq7 login: root
root@ebaz4205-zynq7:~#
```

Total time from power-on to login: about 5 seconds.

## Troubleshooting

### Board does not show serial output

- Did you move R2584 → R2577? Without this the Zynq BootROM still goes to
  NAND. Only a scope on the MIO pins or u-boot on NAND can say otherwise.
- Check 3.3 V TTL polarity. Signals on board are CMOS-level from the PS, not
  RS-232.

### U-Boot stalls right after "U-Boot SPL 2024.01-xilinx-v2024.1"

Means SPL ran but DDR init failed. Almost always a mismatch between
`ps7_init_gpl.c` and the actual DDR chip on *your* board revision. Two known
hardware variants exist (with/without populated PHY oscillator) — if yours
differs, re-export `ps7_init_gpl` from Vivado and overwrite the files in
`recipes-bsp/platform-init/files/`.

### Kernel panic — cannot mount root fs

- Check the SD card actually has partition 2 populated (`lsblk`, `fdisk -l`).
- `boot.scr` passes `root=/dev/mmcblk0p2` — kernel needs MMC + ext4 support.
  Both are in the default linux-xlnx config; if you've been cutting down
  the kernel, verify `CONFIG_MMC_SDHCI_OF_ARASAN` and `CONFIG_EXT4_FS`.

### `bitbake` fails with `LAYERSERIES_COMPAT` errors

Make sure every layer you've cloned is on the `scarthgap` branch — poky,
meta-openembedded, meta-xilinx-core, meta-xilinx-bsp, meta-ebaz4205.

---

## License

- Layer: MIT
- Linux kernel: GPL-2.0-only
- U-Boot: GPL-2.0-or-later
- `ps7_init_gpl.[ch]`: GPL-2.0-or-later (exported by Vivado under the GPL
  variant of the licensing terms).

---

## References

- [Yocto Project Documentation](https://docs.yoctoproject.org/)
- [meta-xilinx (scarthgap)](https://github.com/Xilinx/meta-xilinx/tree/scarthgap)
- [linux-xlnx](https://github.com/Xilinx/linux-xlnx)
- [u-boot-xlnx](https://github.com/Xilinx/u-boot-xlnx)
- [EBAZ4205 hardware notes (Tom's computer pages)](http://cholla.mmto.org/ebaz4205/)
- [FPGA Zero to Hero Vol 5 — EBAZ4205 SD boot walkthrough](https://www.codeembedded.com/blog/fpga_zero_to_hero_vol_5/)
