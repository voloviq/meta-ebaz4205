SUMMARY = "Minimal image for the EBAZ4205 — boots to a serial login."
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += "empty-root-password allow-empty-password allow-root-login debug-tweaks"

IMAGE_INSTALL += " \
    packagegroup-core-boot \
    kernel-modules \
    ${CORE_IMAGE_EXTRA_INSTALL} \
    "

# Small user-space conveniences.
IMAGE_INSTALL += " \
    iproute2 \
    iputils \
    mtd-utils \
    mtd-utils-ubifs \
    "

IMAGE_ROOTFS_EXTRA_SPACE = "32768"
