SUMMARY = "EBAZ4205 NAND flashing helper script"
DESCRIPTION = "flash-nand.sh — programs the on-board 128 MiB NAND from a running (SD-booted) system using mtd-utils."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://flash-nand.sh"
S = "${WORKDIR}"

COMPATIBLE_MACHINE = "ebaz4205-zynq7"

RDEPENDS:${PN} = "mtd-utils mtd-utils-ubifs bash"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/flash-nand.sh ${D}${bindir}/flash-nand
}

FILES:${PN} = "${bindir}/flash-nand"
