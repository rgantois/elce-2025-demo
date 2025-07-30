SNAGBOOT_VENV = $(PWD)/snagboot/venv/bin/activate
CROSS_COMPILE_64 = $(PWD)/aarch64--glibc--stable-2025.08-1
CROSS_COMPILE_32 = $(PWD)/armv7-eabihf--glibc--stable-2025.08-1

UBOOT_DIR = $(PWD)/u-boot
TI_LINUX_FW_DIR = $(PWD)/ti-linux-firmware
TFA_DIR = $(PWD)/arm-trusted-firmware-lts-v2.10.20
BL31=$(TFA_DIR)/build/k3/lite/release/bl31.bin
OPTEE_DIR = $(PWD)/optee_os-4.7.0
TEE=$(OPTEE_DIR)/out/arm-plat-k3/core/tee-pager_v2.bin
BUILDROOT_DIR = $(PWD)/buildroot-2025.02.5

$(eval NCPUS=$$(ncpus))

all:  tiboot3.bin tispl.bin u-boot.img factory.yaml sdcard.img spinand.img snagboot/venv

sdcard.img spinor.img: $(CROSS_COMPILE_64) br-build/.config
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(PWD)/br-external O=$(PWD)/br-build all
	cp br-build/images/sdcard.img .
	cp br-build/images/assets.tar.gz spinor.img

br-build/.config:
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(PWD)/br-external O=$(PWD)/br-build am62x_evm_demo_defconfig

$(BUILDROOT_DIR):
	rm -rf $(BUILDROOT_DIR)
	wget https://buildroot.org/downloads/buildroot-2025.02.5.tar.gz
	tar -xzf $(BUILDROOT_DIR).tar.gz
	rm -rf $(BUILDROOT_DIR).tar.gz
	cd $(BUILDROOT_DIR) && patch -p1 <../package-mpv-disable-manpage-build.patch

tispl.bin u-boot.img: $(CROSS_COMPILE_64) $(UBOOT_DIR) $(TI_LINUX_FW_DIR) $(BL31) $(TEE) am62x_a53_snagfactory.config
	rm -rf $(UBOOT_DIR)/out/a53
	mkdir -p $(UBOOT_DIR)/out/a53
	cp am62x_a53_snagfactory.config u-boot/configs/
	$(MAKE) -C $(UBOOT_DIR) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE_64)/bin/aarch64-buildroot-linux-gnu- \
		O=$(UBOOT_DIR)/out/a53 am62x_evm_a53_defconfig am62x_a53_usbdfu.config am62x_a53_snagfactory.config
	$(MAKE) -C $(UBOOT_DIR) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE_64)/bin/aarch64-buildroot-linux-gnu- \
		BL31=$(BL31) TEE=$(TEE) \
		O=$(UBOOT_DIR)/out/a53 BINMAN_INDIRS=$(TI_LINUX_FW_DIR) -j$(NCPUS)
	cp $(UBOOT_DIR)/out/a53/tispl.bin .
	cp $(UBOOT_DIR)/out/a53/u-boot.img .

$(TEE): $(CROSS_COMPILE_32) $(CROSS_COMPILE_64) $(OPTEE_DIR)
	$(MAKE) -C $(OPTEE_DIR) CROSS_COMPILE=$(CROSS_COMPILE_32)/bin/arm-buildroot-linux-gnueabihf- \
		CROSS_COMPILE64=$(CROSS_COMPILE_64)/bin/aarch64-buildroot-linux-gnu- \
		PLATFORM=k3-am62x CFG_ARM64_core=y \
		-j$(NCPUS)

$(BL31): $(CROSS_COMPILE_64) $(TFA_DIR)
	$(MAKE) -C $(TFA_DIR) ARCH=aarch64 CROSS_COMPILE=$(CROSS_COMPILE_64)/bin/aarch64-buildroot-linux-gnu- \
		PLAT=k3 K3_PM_SYSTEM_SUSPEND=1 TARGET_BOARD=lite SPD=opteed \
		-j$(NCPUS)

tiboot3.bin: $(CROSS_COMPILE_32) $(UBOOT_DIR) $(TI_LINUX_FW_DIR)
	rm -rf $(UBOOT_DIR)/out/r5
	mkdir -p $(UBOOT_DIR)/out/r5
	$(MAKE) -C $(UBOOT_DIR) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE_32)/bin/arm-buildroot-linux-gnueabihf- \
		O=$(UBOOT_DIR)/out/r5 am62x_evm_r5_defconfig am62x_r5_usbdfu.config
	$(MAKE) -C $(UBOOT_DIR) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE_32)/bin/arm-buildroot-linux-gnueabihf- \
		O=$(UBOOT_DIR)/out/r5 BINMAN_INDIRS=$(TI_LINUX_FW_DIR) -j$(NCPUS)
	cp $(UBOOT_DIR)/out/r5/tiboot3.bin .

$(OPTEE_DIR):
	wget https://github.com/OP-TEE/optee_os/archive/refs/tags/4.7.0.tar.gz
	tar -xzf 4.7.0.tar.gz
	rm -rf 4.7.0.tar.gz

$(TI_LINUX_FW_DIR):
	rm -rf ti-linux-firmware
	git clone --depth 1 git://git.ti.com/processor-firmware/ti-linux-firmware.git -b 11.01.08

$(CROSS_COMPILE_64):
	rm -rf $(CROSS_COMPILE_64) $(CROSS_COMPILE_64).tar.xz
	wget https://toolchains.bootlin.com/downloads/releases/toolchains/aarch64/tarballs/$(CROSS_COMPILE_64).tar.xz
	tar -xf $(CROSS_COMPILE_64).tar.xz
	rm -rf $(CROSS_COMPILE_64).tar.xz

$(CROSS_COMPILE_32):
	rm -rf $(CROSS_COMPILE_32) $(CROSS_COMPILE_32).tar.xz
	wget https://toolchains.bootlin.com/downloads/releases/toolchains/armv7-eabihf/tarballs/$(CROSS_COMPILE_32).tar.xz
	tar -xf $(CROSS_COMPILE_32).tar.xz
	rm -rf $(CROSS_COMPILE_32).tar.xz

$(TFA_DIR):
	rm -rf arm-trusted-firmware
	wget https://github.com/ARM-software/arm-trusted-firmware/archive/refs/tags/lts-v2.10.20.tar.gz
	tar -xzf lts-v2.10.20.tar.gz
	rm -rf lts-v2.10.20.tar.gz

u-boot:
	rm -rf u-boot
	git clone https://source.denx.de/u-boot/u-boot.git -b v2025.07

snagboot/venv: snagboot
	rm -rf snagboot/venv
	python -m venv snagboot/venv
	source $(SNAGBOOT_VENV) && pip install snagboot/.[gui]

snagboot:
	rm -rf snagboot
	git clone git@github.com:bootlin/snagboot.git -b ea8a11d688e463d778e682c39c7e9dca41e8e201

clean:
	rm -rf snagboot
