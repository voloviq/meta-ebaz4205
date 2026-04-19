require recipes-core/images/ebaz4205-image-minimal.bb

SUMMARY = "Standard EBAZ4205 image with SSH and common debugging tools."

IMAGE_FEATURES += " \
    ssh-server-dropbear \
    package-management \
    tools-debug \
    "

IMAGE_INSTALL += " \
    devmem2 \
    strace \
    net-tools \
    nfs-utils \
    "

IMAGE_ROOTFS_EXTRA_SPACE = "65536"
