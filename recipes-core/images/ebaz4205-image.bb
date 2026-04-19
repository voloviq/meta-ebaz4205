require recipes-core/images/ebaz4205-image-minimal.bb

SUMMARY = "Standard EBAZ4205 image — minimal + OpenSSH + package manager + debug tools."

# The minimal image already provides OpenSSH; here we add the full userland
# debug set plus package-management (opkg runtime).
IMAGE_FEATURES += " \
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
