# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Yocto/OpenEmbedded BSP meta-layer (`meta-ebaz4205`) for the **Ebang EBAZ4205** — a Xilinx Zynq-7010 board originally sold as a cryptominer controller. Targets **Yocto scarthgap** (5.0) with `linux-xlnx` 6.6 LTS and `u-boot-xlnx` 2024.01 from meta-xilinx-core / meta-xilinx-bsp `scarthgap`.

Sits inside a full Poky tree at `../poky/` alongside sibling layers: `meta-xilinx-core`, `meta-xilinx-bsp`, `meta-openembedded` (meta-oe, meta-python, meta-networking). Work here almost never stands alone — cross-reference those siblings when a recipe's behavior isn't obvious.

**Branches**:
- `master` / `scarthgap` — legacy (zeus-era, Vivado/XSA flow, PL PWM demo). Historical.
- `scarthgap-refresh` — current work, SD boot only, mainline-style kernel DTS. This is what boots to Linux today.

## Build commands

scarthgap templateconf layout is `conf/templates/<name>/`, not the old `conf/` directly. First-time setup from the Poky root:

```bash
cd /home/mw/yocto/poky
TEMPLATECONF=meta-ebaz4205/conf/templates/default source oe-init-build-env ~/yocto/build/ebaz4205-zynq7
bitbake ebaz4205-image-minimal       # 229 MB wic, boots to login
```

Output: `~/yocto/tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7/ebaz4205-image-minimal-ebaz4205-zynq7.rootfs.wic`. `TMPDIR` is per-machine, `DL_DIR` and `SSTATE_DIR` are shared via `~/yocto/` (see `local.conf.sample`).

Images: `ebaz4205-image-minimal` (boots to login) and `ebaz4205-image` (adds SSH + debug tools). Default credentials: `root` / empty password.

Flash: `scripts/flash-sdcard.sh -d /dev/sdX` (uses bmaptool if available, falls back to dd).

## Hardware gotcha

The board ships configured to boot from NAND. To boot from SD you must move one 0-Ω resistor on the PCB:
- **Remove R2584** (pulls MIO4 low → NAND boot)
- **Populate R2577** (pulls MIO4 high → SD boot)

Without this mod, the BootROM ignores the SD card entirely and the board appears dead.

## Serial console

UART1 PS on MIO24 (TX) / MIO25 (RX), exposed on a 4-pin header near the Ethernet jack. **3.3 V TTL only** — do not connect RS-232. 115200 8N1.

```bash
picocom -b 115200 /dev/ttyUSB0
```

SPL prints a `<debug_uart>` banner as soon as ps7_init completes — useful for diagnosing DDR/clock problems. This is `CONFIG_DEBUG_UART=y` in the u-boot bbappend; keep it on until a more stable board revision is confirmed.

## Architecture — the non-obvious bits

**Machine / distro split.** `conf/machine/ebaz4205-zynq7.conf` pulls in meta-xilinx-core's `zynq-generic.conf` then overrides things worth knowing:

- `KERNEL_DEVICETREE = "xilinx/zynq-ebaz4205.dtb"` — linux-xlnx 6.6 LTS *already ships* this DTS. We don't patch the kernel tree.
- `SPL_BINARY = "spl/boot.bin"` + `PREFERRED_PROVIDER_virtual/boot-bin = "u-boot-xlnx"` + `EXTRA_IMAGEDEPENDS:remove = "virtual/fsbl"` — u-boot SPL acts as FSBL (so we don't need meta-xilinx-standalone's `fsbl-firmware` recipe).
- `FORCE_PLATFORM_INIT = "1"` — our `ps7_init_gpl.[ch]` from `recipes-bsp/platform-init/files/` overwrites u-boot's default (zc706) ps7_init during `do_configure`.
- `PREFERRED_PROVIDER_virtual/dtb = ""` — no XSA/meta-xilinx-tools DT generator; DTB comes from the kernel package.
- `BOOTMODE = "ebaz4205"` — u-boot-xlnx-scr picks `boot.cmd.ebaz4205` from our bbappend instead of the stock `boot.cmd.generic.root` (which hardcodes `system.dtb` and requires a ramdisk).

**SPL/U-Boot — 7 knobs added via bbappend** (`recipes-bsp/u-boot/u-boot-xlnx_%.bbappend`). They are all listed in `docs/scarthgap-fixes.md`; the short version:
1. Our `zynq-ebaz4205.dts` is copied into `${S}/arch/arm/dts/` and added to the CONFIG_ARCH_ZYNQ build list via a patch file.
2. `CONFIG_DEFAULT_DEVICE_TREE` + `CONFIG_OF_LIST` are sed-patched to include `zynq-ebaz4205`.
3. `CONFIG_DEBUG_UART*` — early UART print at 100 MHz APB clock (the default 50 MHz guess was wrong on this board).
4. `CONFIG_SPL_SYS_MALLOC_F_LEN=0x8000` — bigger SPL heap (default 8 KiB is too small for DM+MMC).
5. `do_deploy:append` — meta-xilinx-core's u-boot recipe doesn't deploy `u-boot.img` (the FIT that SPL actually loads); we copy it manually.
6. Our `boot.cmd.ebaz4205` is shipped via `u-boot-xlnx-scr.bbappend` (note: no `_%` in filename — base recipe has no version).
7. Our DTS has `bootph-all;` on `&uart1` and `&sdhci0` — without it, fdtgrep strips those nodes out of the SPL DTB and SPL crashes with "No serial driver found" in a BootROM reload loop.

**local.conf BBMASKs that are not optional.** `conf/templates/default/local.conf.sample` ships three BBMASKs that work around meta-xilinx-core scarthgap regressions:
- `meta-xilinx-core/recipes-devtools/qemu/qemu-xilinx.*_2023\.` — 2023.x QEMU recipes reference a missing patch file.
- `meta-xilinx-core/recipes-graphics/` — the whole xilinx graphics bbappend set (libdrm, mesa, weston…) carries patches that don't apply against scarthgap upstream. EBAZ is headless, so safe to drop.
- `BB_DANGLINGAPPENDS_WARNONLY = "1"` — weston 10.0.2 bbappend and fsbl-firmware bbappend have no matching base recipe in scarthgap.

**Known remaining warnings at boot** (documented in `docs/scarthgap-fixes.md` "Known remaining warnings"):
- SPL's optional `system.dtb` probe fails — harmless, our boot.scr path doesn't use it.
- u-boot "No Valid Environment Area" — we don't ship `u-boot.env`, defaults are fine.
- `macb: invalid hw address, using random` — no MAC in DTS, random MAC assigned per boot. For production, set `local-mac-address = [xx xx xx xx xx xx];` on `&gem0`.

**Ethernet requires an FPGA bitstream.** EBAZ4205's IP101GA PHY is wired to PL pins, not PS MIO. The layer ships `recipes-bsp/bitstream/ebaz4205-bitstream.bb` which deploys `ebaz4205-base.bit` (vendored from `nightseas/ebit_z7010`, GPL-3.0-or-later). `boot.cmd.ebaz4205` runs `fatload mmc 0 0x100000 /ebaz4205-base.bit && fpga loadb 0` **before** the kernel load, so Linux probes the PHY with signals actually reaching the chip. Vivado sources for regenerating the bitstream live under `hardware/ebit-z7010/` — see `hardware/README.md`.

**LEDs on W13/W14 also come from the bitstream.** The same bitstream routes the first two EMIO GPIO bits to the two on-board LEDs. They're exposed as `gpio-leds` via `recipes-kernel/linux/linux-xlnx/0002-arm-dts-zynq-ebaz4205-add-gpio-leds-via-EMIO.patch` — GPIO 54/55 on `gpio0`, active-low, heartbeat and cpu triggers on by default. Kernel support is pulled in by `recipes-kernel/linux/config/bsp/leds/leds.cfg`.

**NAND partitions are in BOTH device trees.** Kernel DTS is patched via `0001-arm-dts-zynq-ebaz4205-add-nand-mtd-partitions.patch`. U-boot DTS has them inline in `recipes-bsp/u-boot/files/zynq-ebaz4205.dts`. Layout: boot/uboot/dtb/bitstream/kernel (raw) + ubi (UBIFS rootfs). `CONFIG_MTDIDS_DEFAULT` + `CONFIG_MTDPARTS_DEFAULT` in u-boot so label-based `nand read ... uboot ...` works at the u-boot prompt without `setenv mtdparts`. `flash-nand` on target (in `ebaz4205-image-nand`) does the userspace flashing from SD-booted Linux.

## Editing rules of thumb

- If u-boot stops booting after a config change, `bitbake u-boot-xlnx -c cleansstate` forces a full rebuild — sstate often carries stale SPL state across bbappend edits.
- If SPL starts printing but output is unreadable garbage: it's a baud mismatch. The real UART APB clock on this board is **100 MHz**, not the 50 MHz u-boot defaults assume. Adjust `CONFIG_DEBUG_UART_CLOCK` if needed.
- The kernel DTS lives in linux-xlnx (upstream). The u-boot DTS lives in our `recipes-bsp/u-boot/files/` (we have our own copy). When editing the DT, **edit both** — they are not the same file and can drift.
- ps7_init files are hardware-revision-specific. Three versions are preserved in git history under `recipes-bsp/platform-init/files/`. If SPL hangs silently with ~100 mA power draw and visible current spikes, you likely have a different board revision — try swapping to one of the other ps7_init versions from history (see the first part of `docs/scarthgap-fixes.md` troubleshooting guide).
