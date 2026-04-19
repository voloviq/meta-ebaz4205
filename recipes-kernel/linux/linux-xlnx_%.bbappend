# Extra kernel config for the EBAZ4205:
#  - ICPLUS_PHY:  driver for the on-board IP101GA PHY used by gem0.
#                 Without it the kernel logs "Could not get PHY for eth0: addr 0"
#                 and Ethernet does not come up.
#
# We ship plain .cfg fragments (no .scc wrapper) because scarthgap linux-xlnx's
# kernel-yocto kmeta resolver rejects custom bsp/<subdir>/*.scc paths. kernel.bbclass
# picks up .cfg files from SRC_URI automatically and feeds them to merge_config.sh.

FILESEXTRAPATHS:prepend := "${THISDIR}/config:${THISDIR}/files:${THISDIR}/linux-xlnx:"

SRC_URI:append:ebaz4205-zynq7 = " \
    file://bsp/net/eth.cfg \
    file://bsp/fs/mtd.cfg \
    file://bsp/leds/leds.cfg \
    file://0001-arm-dts-zynq-ebaz4205-add-nand-mtd-partitions.patch \
    file://0002-arm-dts-zynq-ebaz4205-add-gpio-leds-via-EMIO.patch \
    "
