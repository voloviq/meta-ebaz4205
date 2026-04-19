# Adds the Ebang EBAZ4205 device tree to u-boot-xlnx and selects it as the
# default DTS for the xilinx_zynq_virt_defconfig build.
#
# The virt defconfig otherwise targets zc706, whose DDR and pinctrl differ
# from the EBAZ4205. ps7_init_gpl.[ch] is injected separately via
# virtual/xilinx-platform-init (FORCE_PLATFORM_INIT = "1" in the machine conf).

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:ebaz4205-zynq7 = " \
    file://zynq-ebaz4205.dts \
    file://0001-arm-dts-add-zynq-ebaz4205-to-dtb-list.patch \
    "

UBOOT_USER_SPECIFIED_DTS:ebaz4205-zynq7 = "zynq-ebaz4205"

# meta-xilinx-core's u-boot-xlnx recipe deploys u-boot.{bin,elf,dtb} but not
# u-boot.img (the FIT that SPL actually loads from SD). Copy it manually.
do_deploy:append:ebaz4205-zynq7() {
    if [ -f ${B}/u-boot.img ]; then
        install -m 0644 ${B}/u-boot.img ${DEPLOYDIR}/u-boot.img
    fi
}

do_configure:prepend:ebaz4205-zynq7() {
    # Place our DTS inside u-boot's arch/arm/dts/ so the Makefile patch
    # (which only adds the entry to the build list) has something to point at.
    install -m 0644 ${WORKDIR}/zynq-ebaz4205.dts ${S}/arch/arm/dts/zynq-ebaz4205.dts

    # Point xilinx_zynq_virt_defconfig at our DTB (default + OF_LIST) so SPL
    # picks it from the multi-DTB FIT. Simple string substitutions — no
    # backslash gymnastics.
    sed -i 's|^CONFIG_DEFAULT_DEVICE_TREE=.*|CONFIG_DEFAULT_DEVICE_TREE="zynq-ebaz4205"|' \
        ${S}/configs/xilinx_zynq_virt_defconfig
    if ! grep -q 'zynq-ebaz4205' ${S}/configs/xilinx_zynq_virt_defconfig | grep -q OF_LIST; then
        sed -i 's|^CONFIG_OF_LIST="\(.*\)"$|CONFIG_OF_LIST="zynq-ebaz4205 \1"|' \
            ${S}/configs/xilinx_zynq_virt_defconfig
    fi

    # Early debug UART — lets SPL print a banner before ps7_init finishes,
    # so we can see where the boot hangs instead of having a silent board.
    # UART1 on EBAZ4205 = 0xE0001000, APB clock after BootROM = 100 MHz
    # (empirically verified: reading UART at 230400 yielded readable output
    # on our default 50 MHz guess, i.e. real clock is 2x).
    # Also ensure the full zynq serial driver is linked into SPL — otherwise
    # SPL prints "No serial driver found..resetting ..." and BootROM loops.
    cat >> ${S}/configs/xilinx_zynq_virt_defconfig <<'EOF'
CONFIG_DEBUG_UART=y
CONFIG_DEBUG_UART_ZYNQ=y
CONFIG_DEBUG_UART_BASE=0xe0001000
CONFIG_DEBUG_UART_CLOCK=100000000
CONFIG_DEBUG_UART_ANNOUNCE=y
CONFIG_SPL_SYS_MALLOC_F_LEN=0x8000
EOF
}
