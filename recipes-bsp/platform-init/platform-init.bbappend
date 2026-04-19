FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:ebaz4205-zynq7 = " \
    file://ps7_init_gpl.c \
    file://ps7_init_gpl.h \
    "

COMPATIBLE_MACHINE:ebaz4205-zynq7 = "ebaz4205-zynq7"

# scarthgap-poky renamed common-licenses/GPL-2.0 → GPL-2.0-only; the stock
# platform-init.bb in meta-xilinx-core has not caught up. Point at the new name.
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"
