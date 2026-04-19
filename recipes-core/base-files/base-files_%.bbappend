FILESEXTRAPATHS:append := ":${THISDIR}/files"

SRC_URI:append:ebaz4205-zynq7 = " file://fstab"

do_install:append:ebaz4205-zynq7() {
    install -d ${D}/media/mmcblk0p1
}
