# Scarthgap migration — fix log

Running record of what broke and what was changed to make `bitbake
ebaz4205-image-minimal` succeed on Yocto scarthgap with meta-xilinx-core /
meta-xilinx-bsp scarthgap and `XILINX_RELEASE_VERSION = "v2024.1"`.

Each entry: symptom → root cause → fix (file).

---

## 1. Template layout — `conf/.templateconf` rejected

**Symptom:** `oe-init-build-env` errored with
`TEMPLATECONF value must point to meta-some-layer/conf/templates/template-name`.

**Cause:** scarthgap enforces the new templateconf directory layout.

**Fix:** moved samples into `conf/templates/default/`
(`local.conf.sample`, `bblayers.conf.sample`, `conf-notes.txt`) and removed
the old `conf/.templateconf`.

## 2. `qemu-xilinx` 2023.x recipes reference a missing patch file

**Symptom:** `Unable to get checksum for qemu-xilinx-native SRC_URI entry
0002-chardev-connect-socket-to-a-spawned-command.patch` during parse.

**Cause:** meta-xilinx-core's 2023.1/2023.2 QEMU recipes still on the
scarthgap branch look for a patch file path that does not exist. We pin
`XILINX_RELEASE_VERSION = "v2024.1"` so those recipes are never selected.

**Fix:** `conf/templates/default/local.conf.sample`
```
BBMASK += "meta-xilinx-core/recipes-devtools/qemu/qemu-xilinx.*_2023\."
```

## 3. Dangling bbappends break parsing

**Symptom:** `No recipes in default available for:
weston_10.0.2.bbappend` and `fsbl-firmware_%.bbappend` — fatal in scarthgap.

**Cause:** meta-xilinx ships bbappends whose base recipes either do not
exist in scarthgap (weston 10.0.2) or are only present when building with
meta-xilinx-standalone (fsbl-firmware, which we don't use).

**Fix:** `conf/templates/default/local.conf.sample`
```
BB_DANGLINGAPPENDS_WARNONLY = "1"
```

## 4. meta-xilinx-core graphics bbappends — patches don't apply

**Symptom:** `do_patch` failures on libdrm 2.4.120 and mesa 24.0.7 —
hunks rejected.

**Cause:** Xilinx's XV15/XV20/HDR patches target earlier upstream
versions; scarthgap's `libdrm`/`mesa` are newer. EBAZ4205 is headless, so
the patches are not needed.

**Fix:** `conf/templates/default/local.conf.sample`
```
BBMASK += "meta-xilinx-core/recipes-graphics/"
```

## 5. `virtual/dtb` pulled via `system.dtb` in IMAGE_BOOT_FILES

**Symptom:** `Nothing PROVIDES 'virtual/dtb'` — `device-tree` recipe
skipped because `CONFIG_DTFILE` not set.

**Cause:** default `PREFERRED_PROVIDER_virtual/dtb = "device-tree"` from
meta-xilinx-core wants a DTS generated from an XSA file (meta-xilinx-tools
flow). We don't use XSA — our DTB comes from the kernel package. The
auto-rdepends machinery in `machine-xilinx-default.inc` pulls virtual/dtb
whenever `IMAGE_BOOT_FILES_INSTALLED` contains `system.dtb`.

**Fix:** `conf/machine/ebaz4205-zynq7.conf`
```
PREFERRED_PROVIDER_virtual/dtb = ""
```
Also stopped renaming the DTB to `system.dtb` — we keep it as
`zynq-ebaz4205.dtb` and ship our own `boot.scr` (see #7) that looks for
that name.

## 6. `virtual/fsbl` requires meta-xilinx-standalone

**Symptom:** `Nothing PROVIDES 'fsbl-firmware'`, then
`Nothing PROVIDES 'virtual/boot-bin'`.

**Cause:** `zynq-generic.conf` pulls `virtual/fsbl` into
`EXTRA_IMAGEDEPENDS`; its only provider (`fsbl-firmware`) lives in
meta-xilinx-standalone which we're not using. And the default
`PREFERRED_PROVIDER_virtual/boot-bin = "xilinx-bootbin"` in turn depends
on `virtual/fsbl`.

**Fix:** `conf/machine/ebaz4205-zynq7.conf` — u-boot SPL acts as FSBL
and produces `boot.bin` on its own when `SPL_BINARY = "spl/boot.bin"`.
```
SPL_BINARY = "spl/boot.bin"
PREFERRED_PROVIDER_virtual/boot-bin = "u-boot-xlnx"
EXTRA_IMAGEDEPENDS:remove = "virtual/fsbl"
```

## 7. Stock `boot.cmd.generic.root` hardcodes `system.dtb`

**Symptom:** `boot.scr` would try to load `/system.dtb` from the FAT
partition; we ship `zynq-ebaz4205.dtb`. Plus the template requires a
ramdisk which we don't have.

**Fix:** ship our own boot script template:
- `recipes-bsp/u-boot/files/boot.cmd.ebaz4205` — minimal SD boot flow.
- `recipes-bsp/u-boot/u-boot-xlnx-scr.bbappend` — adds it to the recipe's
  SRC_URI.
- Machine conf sets `BOOTMODE = "ebaz4205"` so u-boot-xlnx-scr picks that
  `boot.cmd.<BOOTMODE>` at build time.

Note the recipe filename has no `_%` — base recipe is `u-boot-xlnx-scr.bb`
(no version), so `u-boot-xlnx-scr.bbappend` is the right form.

## 8. `platform-init.bb` references GPL-2.0 license file that was renamed

**Symptom:** `LIC_FILES_CHKSUM points to an invalid file:
/home/mw/yocto/poky/meta/files/common-licenses/GPL-2.0` — fatal QA error.

**Cause:** scarthgap-poky renamed `common-licenses/GPL-2.0` →
`GPL-2.0-only`. meta-xilinx-core's `platform-init.bb` has not caught up.

**Fix:** `recipes-bsp/platform-init/platform-init.bbappend`
```
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"
```

## 9. Kernel `.scc` feature fragments rejected by linux-xlnx 6.6 kmeta

**Symptom:** `Feature 'bsp/net/eth.scc' not found`.

**Cause:** scarthgap `linux-xlnx` runs a stricter `kernel-yocto` feature
resolver. Even with `KFEATURE_COMPATIBILITY all`, the custom
`bsp/<subdir>/*.scc` path isn't found reliably via `KERNEL_FEATURES`.

**Fix:** since SD boot on mainline DTS doesn't need ICPLUS_PHY nor UBI
(those are only for the NAND flow, which is deferred), drop the fragments
from the kernel bbappend:
- `recipes-kernel/linux/linux-xlnx_%.bbappend` — reduced to a comment.
- `recipes-kernel/linux/config/bsp/` — kept on disk for the future NAND
  flow but no longer referenced.

## 10. u-boot Makefile corruption — `sed -i` wrote `\\` instead of `\`

**Symptom:** `arch/arm/dts/Makefile:395: *** recipe commences before first
target.  Stop.` — the line `zynq-ebaz4205.dtb \\` (literal double
backslash) broke the continuation.

**Cause:** bash/sed escaping of the `\` line continuation through nested
quoting. The sed expression `'/pattern/i\\t...\\\\\\\\'` did not survive
round trip.

**Fix:** replaced the sed-on-Makefile hack with a real patch file.
- `recipes-bsp/u-boot/files/0001-arm-dts-add-zynq-ebaz4205-to-dtb-list.patch`
- `recipes-bsp/u-boot/u-boot-xlnx_%.bbappend` now only copies the DTS and
  sed-tweaks the defconfig (simple string substitutions, no continuation
  character problem).

## 11. `u-boot.img` is built but not deployed

**Symptom:** `do_image_wic` → `install: cannot stat
'.../deploy/images/ebaz4205-zynq7/u-boot.img'`.

**Cause:** meta-xilinx-core's u-boot-xlnx-blob.inc deploys only `.bin`,
`.elf`, `.dtb`. `u-boot.img` is built (`build/u-boot.img`) but not copied
to DEPLOY_DIR.

**Fix:** `conf/machine/ebaz4205-zynq7.conf` — use `u-boot.bin` instead
(u-boot SPL on xilinx_zynq_virt_defconfig can load raw `u-boot.bin` just
as well).
```
IMAGE_BOOT_FILES = "boot.bin u-boot.bin boot.scr uImage zynq-ebaz4205.dtb"
```

## 12. wic wks-file not found — `WKS_FILE` vs `WKS_FILES`

**Symptom:** `No kickstart files from WKS_FILES were found:
xilinx-default-sd.wks`.

**Cause:** meta-xilinx-core uses plural `WKS_FILES` (default
`xilinx-default-sd.wks`). Setting only `WKS_FILE` leaves the default
plural in place, which points at a filename our layer doesn't ship.

**Fix:** `conf/machine/ebaz4205-zynq7.conf` — set both for safety.
```
WKS_FILE  = "ebaz4205-sdcard.wks.in"
WKS_FILES = "ebaz4205-sdcard.wks.in"
```

## 13. `wic.qemu-sd` conversion — filename extension mismatch

**Symptom:** `cp: cannot stat 'ebaz4205-image-minimal-…rootfs.wic'` — the
stock `wic` ends with `.wic`, but `image-types-xilinx-qemu.bbclass`
expects `.rootfs.wic`.

**Cause:** meta-xilinx-core's qemu conversion class has not been updated
for the scarthgap image_types_wic rename. `zynq-generic.conf` appends
`wic.qemu-sd` to `IMAGE_FSTYPES`.

**Fix:** `conf/machine/ebaz4205-zynq7.conf` — we don't run EBAZ4205 under
qemu, drop the conversion.
```
IMAGE_FSTYPES:remove = "wic.qemu-sd"
```

## 14. SPL "No serial driver found" — missing `bootph-all` in DTS

**Symptom:** `<debug_uart>` banner appears (so ps7_init and UART clock are
both OK) but is immediately followed by:
```
No serial driver found
resetting ...
```
...in a tight loop, BootROM reload cycle.

**Cause:** scarthgap u-boot runs `fdtgrep` on the SPL DTB to strip out
nodes that are not explicitly needed at SPL stage. The heuristic is the
DT property `bootph-all;` (or the older `u-boot,dm-pre-reloc;`). Our
DTS — copied straight from the kernel source — has neither, so fdtgrep
removed the `uart1` node entirely. Driver-model SPL could not bind the
UART driver and panicked.

Confirmed by `strings u-boot-spl.dtb` showing `uart1` as a clock-output
name only, with no `serial@e0001000` node under `/axi`.

**Fix:** `recipes-bsp/u-boot/files/zynq-ebaz4205.dts` — add `bootph-all;`
to the nodes that must be present at SPL stage:
```
&sdhci0  { bootph-all; status = "okay"; ... };
&uart1   { bootph-all; status = "okay"; ... };
```
The kernel ignores this property, so it does not need to be stripped for
the linux-xlnx DTS.

## 15. DEBUG_UART clock was wrong (50 vs 100 MHz)

**Symptom:** After SPL actually started running, readable output came out
at 230400 baud with target set to 115200. Classic ratio-of-2 mismatch.

**Cause:** `CONFIG_DEBUG_UART_CLOCK=50000000` was guessed from the
"typical" IO-PLL-divided-by-20 assumption. BootROM on EBAZ4205 actually
leaves the UART APB clock at 100 MHz.

**Fix:** `recipes-bsp/u-boot/u-boot-xlnx_%.bbappend`:
```
CONFIG_DEBUG_UART_CLOCK=100000000
```

## 16. SPL `alloc space exhausted` when bringing up MMC

**Symptom:**
```
U-Boot SPL 2024.01 ...
Silicon version:        3
Trying to boot from MMC1
alloc space exhausted
alloc space exhausted
spl: could not initialize mmc. error: -12
```

**Cause:** default SPL early-malloc pool is too small once driver-model
UART + DM MMC are both pulled in.

**Fix:** `recipes-bsp/u-boot/u-boot-xlnx_%.bbappend`:
```
CONFIG_SPL_SYS_MALLOC_F_LEN=0x8000   # 32 KiB early heap
```

## 17. `u-boot.img` is built but not deployed

**Symptom:** After SPL reads the SD card successfully, it errors with
```
spl_load_image_fat: error reading image u-boot.img, err - -2
```
(ENOENT — file not present on FAT partition).

**Cause:** meta-xilinx-core's `u-boot-xlnx_2024.1.bb` deploys `u-boot.bin`,
`u-boot.elf`, `u-boot.dtb`, but skips `u-boot.img` — the FIT wrapper that
SPL actually tries to read. Earlier we worked around by substituting
`u-boot.bin`, but SPL's `CONFIG_SPL_FS_LOAD_PAYLOAD_NAME` is fixed to
`"u-boot.img"` in the virt defconfig.

**Fix:** `recipes-bsp/u-boot/u-boot-xlnx_%.bbappend`:
```
do_deploy:append:ebaz4205-zynq7() {
    if [ -f ${B}/u-boot.img ]; then
        install -m 0644 ${B}/u-boot.img ${DEPLOYDIR}/u-boot.img
    fi
}
```
And put `u-boot.img` back into `IMAGE_BOOT_FILES`.

---

## Final result

`bitbake ebaz4205-image-minimal` produces
`tmp-ebaz4205-zynq7/deploy/images/ebaz4205-zynq7/ebaz4205-image-minimal-ebaz4205-zynq7.rootfs.wic`
(~229 MB) + bmap. After `dd` to an SD card and a one-resistor board mod
(R2584 → R2577), the board boots all the way to a Poky (Yocto 5.0)
userland login prompt over UART1 at 115200 8N1:

```
<debug_uart>
U-Boot SPL 2024.01 ...
U-Boot 2024.01 ...
Model: Ebang EBAZ4205
DRAM: ECC disabled 256 MiB
MMC:   mmc@e0100000: 0
...
== EBAZ4205 boot.scr ==
## Booting kernel from Legacy Image ...
Linux version 6.6.10-xilinx-v2024.1 ...
OF: fdt: Machine model: Ebang EBAZ4205
...
Poky (Yocto Project Reference Distro) 5.0.5 ebaz4205-zynq7 /dev/ttyPS0
ebaz4205-zynq7 login: root
root@ebaz4205-zynq7:~#
```

## 18. Ethernet requires an FPGA bitstream (PL routing)

**Symptom:** even after adding `CONFIG_ICPLUS_PHY=y` to the kernel,
`eth0` appears in `/sys/class/net/` but stays `DOWN`, with:
```
macb e000b000.ethernet eth0: validation of ... failed: -EINVAL
macb e000b000.ethernet eth0: Could not attach PHY (-22)
```

**Cause** (hardware, not software): EBAZ4205's on-board IP101GA PHY is
wired to **PL pins**, not to PS MIO. PS GEM0 therefore needs its
signals (MDC, MDIO, RXD[3:0], TXD[3:0], RX/TX_CLK, RX_DV, TX_EN, COL,
CRS) routed through **EMIO** to those PL pins. Without a bitstream
loaded, the PL is blank and MDIO reads return 0xFFFF → PHY advertises
nothing → `phylink_validate` fails.

**Fix:** ship an EMIO-routing bitstream and load it before the kernel
starts.

- `recipes-bsp/bitstream/ebaz4205-bitstream.bb` deploys
  `ebaz4205-base.bit` (the PS-only reference design from
  `nightseas/ebit_z7010`, GPL-3.0-or-later) to both DEPLOYDIR and
  `/lib/firmware/` in the rootfs.
- Machine conf: `EXTRA_IMAGEDEPENDS += "ebaz4205-bitstream"` +
  `IMAGE_BOOT_FILES` gains `ebaz4205-base.bit`, so wic places it on the
  FAT partition.
- `recipes-bsp/u-boot/files/boot.cmd.ebaz4205` gained an
  `fpga loadb 0` step ahead of the kernel load: u-boot programs the PL
  before `bootm`, and Linux probes the PHY with signals actually
  reaching the chip.

The Vivado project sources from which the bitstream was generated are
vendored in `hardware/ebit-z7010/` for reproducibility — see
`hardware/README.md`.

---

## Known remaining warnings (non-blocking)

- `spl_load_image_fat_os: ... system.dtb ... -2` — SPL optional pre-OS
  DTB probe. We do not ship `system.dtb`; boot continues via `boot.scr`.
- `*** Error - No Valid Environment Area found` in u-boot proper — no
  `u-boot.env` on SD. u-boot falls back to compiled-in defaults. Fine.
- `macb: invalid hw address, using random` — no MAC in device tree.
  Harmless for development; for production, set one in the DTS via
  `local-mac-address = [xx xx xx xx xx xx];` on the `&gem0` node.
