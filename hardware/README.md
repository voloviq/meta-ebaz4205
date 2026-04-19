# EBAZ4205 hardware project

This directory holds the **Vivado project** from which the FPGA bitstream
`recipes-bsp/bitstream/files/ebaz4205-base.bit` was generated.

The pre-built bitstream is what the Yocto image actually uses at runtime
(loaded by U-Boot before kernel start, so that `gem0` can reach the
on-board IP101GA Ethernet PHY through EMIO → PL routing). The Vivado
sources are kept here for reproducibility and to allow future
modifications — e.g. exposing additional PS peripherals to PL, adding
custom IP, or recompiling against a different Vivado release.

## Sub-project: `ebit-z7010/`

Upstream: <https://github.com/nightseas/ebit_z7010>
License: **GPL-3.0-or-later** (see `ebit-z7010/LICENSE`)
Imported at revision `88907e0950e2a5b151905f922e58f91fd2d35ef8`
(2019-12-12).

Author: Xiaohai Li <haixiaolee@gmail.com>.

Differences from upstream:

- `.git/` removed (we're vendoring, not submoduling).
- `images/` removed — this was a pre-built boot set (`BOOT.bin`, uEnv,
  kernel) geared at a different build flow. We use Yocto, so we build
  our own.

### What the project implements

PS-only block design for the Zynq-7010 on EBAZ4205, with:

- DDR3 256 MB
- SDIO (micro-SD card slot)
- UART1 for debug/logging
- **100 Mb Ethernet with MII interface via EMIO** — the reason we pulled
  it in
- GPIO for LEDs via EMIO

### How to regenerate the bitstream

Open `ebit-z7010/ebit_z7010.xpr` in **Xilinx Vivado 2018.3** (free
WebPack licence covers Zynq-7010). Run *Generate Bitstream* to produce
`ebit_z7010.runs/impl_1/ebit_z7010_top_wrapper.bit`.

Then copy the resulting `.bit` over the one shipped in this layer:

```
cp ebit_z7010.runs/impl_1/ebit_z7010_top_wrapper.bit \
   recipes-bsp/bitstream/files/ebaz4205-base.bit
```

Vivado 2018.3 is only one option — the upstream author tested with it.
Later Vivado versions will likely upgrade the IP cores on first open
(confirm → save) and should still synthesise without modification, but
have not been validated here.

### Why Vivado 2018.3 specifically

The pre-built bitstream metadata reads
`Vivado 2018.3.1 - for 7z010clg400 - built 2019/12/09`. The source
in this directory was exported from the same environment and will open
cleanly in Vivado 2018.3. Newer versions will require an IP upgrade and
re-synthesis.

### When to rebuild the bitstream

- You want to add an FPGA IP block (e.g. PWM, custom AXI peripheral).
- You change pin constraints (e.g. route GEM signals to different PL
  pins on a different EBAZ4205 revision).
- You upgrade Vivado and want a fresh synthesis.

For any of these, rebuild, drop the `.bit` in
`recipes-bsp/bitstream/files/ebaz4205-base.bit`, then
`bitbake ebaz4205-bitstream -c cleansstate && bitbake ebaz4205-image-minimal`.
