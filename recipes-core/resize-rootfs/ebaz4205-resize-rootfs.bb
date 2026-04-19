SUMMARY = "First-boot rootfs resizer for EBAZ4205 SD card images."
DESCRIPTION = "\
Runs once on first boot: grows the ext4 rootfs on /dev/mmcblk0p2 to \
fill the entire SD card, then disables itself and removes its own \
init hook + helper script. Idempotent — if the partition already \
fills the card, the run is a no-op.\
Ships both a sysvinit init script and a systemd unit; the right one is \
installed based on DISTRO_FEATURES.\
"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://ebaz4205-resize-rootfs.sh \
    file://ebaz4205-resize-rootfs.init \
    file://ebaz4205-resize-rootfs.service \
    "

S = "${WORKDIR}"

COMPATIBLE_MACHINE = "ebaz4205-zynq7"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit update-rc.d systemd

INITSCRIPT_NAME = "ebaz4205-resize-rootfs"
# Run late in the S runlevel so mmcblk0p2 is already the rw rootfs.
INITSCRIPT_PARAMS = "start 99 S ."

SYSTEMD_SERVICE:${PN} = "ebaz4205-resize-rootfs.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} = "e2fsprogs-resize2fs parted util-linux-blockdev"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/ebaz4205-resize-rootfs.sh \
                    ${D}${bindir}/ebaz4205-resize-rootfs

    # sysvinit: only install the init script if sysvinit is in DISTRO_FEATURES.
    if ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', 'true', 'false', d)}; then
        install -d ${D}${sysconfdir}/init.d
        install -m 0755 ${WORKDIR}/ebaz4205-resize-rootfs.init \
                        ${D}${sysconfdir}/init.d/ebaz4205-resize-rootfs
    fi

    # systemd: same logic the other way round.
    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${systemd_system_unitdir}
        install -m 0644 ${WORKDIR}/ebaz4205-resize-rootfs.service \
                        ${D}${systemd_system_unitdir}/ebaz4205-resize-rootfs.service
    fi
}

FILES:${PN} += " \
    ${sysconfdir}/init.d/ebaz4205-resize-rootfs \
    ${systemd_system_unitdir}/ebaz4205-resize-rootfs.service \
    "
