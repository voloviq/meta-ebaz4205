# Ship our own boot.cmd for the EBAZ4205. The stock boot.cmd.generic.root
# from meta-xilinx hardcodes "system.dtb" and requires a ramdisk entry,
# neither of which match this layer's setup.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:ebaz4205-zynq7 = " file://boot.cmd.ebaz4205"
