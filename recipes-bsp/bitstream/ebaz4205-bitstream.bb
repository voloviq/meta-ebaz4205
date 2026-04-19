SUMMARY = "FPGA bitstream for the EBAZ4205 — routes GEM0 EMIO signals to PL pins so the on-board IP101GA Ethernet PHY is reachable."
DESCRIPTION = "\
Pre-built Vivado 2018.3 bitstream from nightseas/ebit_z7010 (EBAZ4205 \
base reference design, PS-only). Implements: DDR3 256 MB, SDIO, UART1, \
100M Ethernet MII via EMIO, GPIO for LEDs via EMIO. Without this bitstream \
loaded, the PS GEM0 MAC has no routing to the PHY and Ethernet does not \
work on this board.\
\
Source: https://github.com/nightseas/ebit_z7010 (GPL-3.0-or-later).\
"
HOMEPAGE = "https://github.com/nightseas/ebit_z7010"

LICENSE = "GPL-3.0-or-later"
LIC_FILES_CHKSUM = "file://LICENSE-bitstream;md5=ca3c1cb6d52be458cdaafa6c2cd56000"

SRC_URI = " \
    file://ebaz4205-base.bit \
    file://LICENSE-bitstream \
"

S = "${WORKDIR}"

COMPATIBLE_MACHINE = "ebaz4205-zynq7"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit deploy

do_install() {
    install -d ${D}/lib/firmware
    install -m 0644 ${WORKDIR}/ebaz4205-base.bit ${D}/lib/firmware/ebaz4205-base.bit
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${WORKDIR}/ebaz4205-base.bit ${DEPLOYDIR}/ebaz4205-base.bit
}
addtask do_deploy after do_install before do_build

FILES:${PN} = "/lib/firmware/ebaz4205-base.bit"
