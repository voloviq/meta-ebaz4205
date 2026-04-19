SUMMARY = "Minimal image for the EBAZ4205 — boots to a serial/SSH login."
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += " \
    empty-root-password \
    allow-empty-password \
    allow-root-login \
    debug-tweaks \
    ssh-server-openssh \
    "

IMAGE_INSTALL += " \
    packagegroup-core-boot \
    kernel-modules \
    ${CORE_IMAGE_EXTRA_INSTALL} \
    "

# Small user-space conveniences plus SFTP so scp/sftp work out of the box.
IMAGE_INSTALL += " \
    iproute2 \
    iputils \
    mtd-utils \
    mtd-utils-ubifs \
    openssh-sftp-server \
    ebaz4205-resize-rootfs \
    "

IMAGE_ROOTFS_EXTRA_SPACE = "32768"
