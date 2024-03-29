#!/usr/bin/make -rf

# +------------------------------------------------------------
# | (C) 2011 Pawel Kraszewski <root@linuxpedia.pl>
# | System generujący środowisko i system na procesory ARM
# | Extended by Piotr Wasiewicz <piotrwasiewiczeu@gmail.com>
# +------------------------------------------------------------

HERE=$(PWD)

# +------------------------------------------------------------
# | Wersje
# +------------------------------------------------------------

BUSYBOX_VER=1.36.1
BUSYBOX_MD5=0fc591bc9f4e365dfd9ade0014f32561

KERNEL_VER=stable_20231123
KERNEL_MD5=8b646b69cfe2f5104e19ef25a82908a4

# +------------------------------------------------------------
# | Architektura
# +------------------------------------------------------------

ARCH=arm64
CROSS_COMPILE=aarch64-unknown-linux-gnu-

# +------------------------------------------------------------
# | Host -j param
# +------------------------------------------------------------

MULTICPU=-j16

# +------------------------------------------------------------
# | Katalogi
# +------------------------------------------------------------

# Katalog na pobrane pliki
DOWNLOAD_DIR=$(HERE)/dl

# Katalogi na pliki źródłowe
SRC_DIR=$(HERE)/src
SRC_KERNEL=$(SRC_DIR)/linux-$(KERNEL_VER)
SRC_BUSYBOX=$(SRC_DIR)/busybox-$(BUSYBOX_VER)

# Katalogi na binaria
BIN_DIR=$(HERE)/bin
BIN_KERNEL=$(BIN_DIR)/kernel
BIN_BUSYBOX=$(BIN_DIR)/busybox

# Katalog źródłowy initrd
INITRD_DIR=$(HERE)/initrd

# Katalog emulatora
EMUL_DIR=$(HERE)/emu

# +------------------------------------------------------------
# | Ściąganie z sieci
# +------------------------------------------------------------

$(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2:
	@mkdir -p $(DOWNLOAD_DIR)
	@echo "$(BUSYBOX_MD5)  $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2" > $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).md5
	@if ! md5sum -c --quiet $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).md5; then \
	    echo "Pobieranie busybox-$(BUSYBOX_VER).tar.bz2"; \
	    wget -O $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2 http://busybox.net/downloads/busybox-$(BUSYBOX_VER).tar.bz2; \
	fi
	touch $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2

$(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.gz:
	@mkdir -p $(DOWNLOAD_DIR)
	@echo "$(KERNEL_MD5)  $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.gz" > $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).md5
	@if ! md5sum -c --quiet $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).md5; then \
	    echo "Pobieranie linux-$(KERNEL_VER).tar.gz"; \
	    #wget -O $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.gz http://www.kernel.org/pub/linux/kernel/v4.x/linux-$(KERNEL_VER).tar.gz; \
	    wget -O $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.gz https://github.com/raspberrypi/linux/archive/refs/tags/$(KERNEL_VER).tar.gz; \
	fi
	touch $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.gz

# +------------------------------------------------------------
# | Rozpakowywanie
# +------------------------------------------------------------

$(SRC_BUSYBOX)/Makefile:	$(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2
	@mkdir -p $(SRC_DIR)
	tar xjf $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2 -C $(SRC_DIR)
	touch $(SRC_BUSYBOX)/Makefile

$(SRC_KERNEL)/Makefile:	$(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.gz
	@mkdir -p $(SRC_DIR)
	tar xzf $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.gz -C $(SRC_DIR)
	touch $(SRC_KERNEL)/Makefile

# +------------------------------------------------------------
# | Zarządzanie downloadami
# +------------------------------------------------------------

dl/busybox: $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2
dl/kernel:  $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.gz
dl:	dl/busybox dl/kernel

# +------------------------------------------------------------
# | Zarządzanie źródłami
# +------------------------------------------------------------

src/busybox: $(SRC_BUSYBOX)/Makefile
src/kernel:  $(SRC_KERNEL)/Makefile
src:	src/busybox src/kernel

# +------------------------------------------------------------
# | Budowa potrzebnych narzędzi do Gentoo
# +------------------------------------------------------------

/etc/gentoo-release:
	@echo "Potrzebujesz do tego Gentoo!"
	exit

/usr/bin/aarch64-unknown-linux-gnu-gcc:
	#crossdev -C aarch64-unknown-linux-gnu -f
	#@USE="-fortran nossp" crossdev --target aarch64-unknown-linux-gnu --gcc 7.4.0-r2 --libc 2.29-r7 --kernel 4.19.115 -oO /usr/portage
	@USE="static-libs" crossdev -S --target aarch64-unknown-linux-gnu -oO /usr/portage

/usr/bin/crossdev:
	@emerge -av crossdev

gentoo: /etc/gentoo-release

crossdev:	gentoo /usr/bin/crossdev

toolchain:	crossdev /usr/bin/aarch64-unknown-linux-gnu-gcc
	@echo $(HERE)

# +------------------------------------------------------------
# | Konfiguracja binarek poza drzewo źródłowe
# +------------------------------------------------------------

$(BIN_KERNEL)/Makefile: toolchain $(SRC_KERNEL)/Makefile 
	@mkdir -p $(BIN_KERNEL)
	#@cd $(SRC_KERNEL) && make O=$(BIN_KERNEL) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) defconfig
	@cd $(SRC_KERNEL) && make O=$(BIN_KERNEL) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) bcmrpi3_defconfig

$(BIN_BUSYBOX)/Makefile: toolchain $(SRC_BUSYBOX)/Makefile
	@mkdir -p $(BIN_BUSYBOX)
	@cd $(SRC_BUSYBOX) && make O=$(BIN_BUSYBOX) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) defconfig

# +------------------------------------------------------------
# | Konfiguracja 
# +------------------------------------------------------------

$(BIN_KERNEL)/.config:	$(BIN_KERNEL)/Makefile

$(BIN_BUSYBOX)/.config:	$(BIN_BUSYBOX)/Makefile

kernconf:	$(BIN_KERNEL)/.config
	@cd $(BIN_KERNEL) && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) menuconfig

busyboxconf:	$(BIN_BUSYBOX)/.config
	@cd $(BIN_BUSYBOX) && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) menuconfig

# +------------------------------------------------------------
# | Kompilacja
# +------------------------------------------------------------

$(BIN_BUSYBOX)/busybox: $(BIN_BUSYBOX)/.config
	@sed -i "s:.*CONFIG_PREFIX=.*:CONFIG_PREFIX=\"$(INITRD_DIR)\":" $(BIN_BUSYBOX)/.config
	@sed -i "s:.*CONFIG_CROSS_COMPILER_PREFIX=.*:CONFIG_CROSS_COMPILER_PREFIX=\"aarch64-unknown-linux-gnu-\":" $(BIN_BUSYBOX)/.config
	@sed -i "s/# CONFIG_STATIC is not set/CONFIG_STATIC=y/g" $(BIN_BUSYBOX)/.config
	@cd $(BIN_BUSYBOX) \
	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(MULTICPU)

$(BIN_KERNEL)/arch/arm64/boot/Image:	$(BIN_KERNEL)/.config
	@cd $(BIN_KERNEL) \
	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(MULTICPU)

# +------------------------------------------------------------
# | Składanie INITRD
# +------------------------------------------------------------

$(INITRD_DIR)/bin/busybox: $(BIN_BUSYBOX)/busybox
	@mkdir -p $(INITRD_DIR)
	@cp -av $(HERE)/init $(INITRD_DIR) 
	@cd $(BIN_BUSYBOX) \
	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) PREFIX=$(INITRD_DIR) install

# +------------------------------------------------------------
# | Składanie Emulatora
# +------------------------------------------------------------

$(EMUL_DIR)/vmlinuz:	$(BIN_KERNEL)/arch/arm64/boot/Image
	@mkdir -p $(EMUL_DIR)
	@cd $(BIN_KERNEL) \
	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_PATH=$(EMUL_DIR) $(MULTICPU) install
	@cp $(BIN_KERNEL)/arch/arm64/boot/Image $(EMUL_DIR)/vmlinuz
	@touch $(EMUL_DIR)/vmlinuz

$(EMUL_DIR)/initrd:	$(INITRD_DIR)/bin/busybox $(wildcard $(INITRD_DIR)/bin/*) $(wildcard $(INITRD_DIR)/etc/*) $(wildcard $(INITRD_DIR)/sbin/*) $(BIN_KERNEL)/arch/arm64/boot/Image
	@mkdir -p $(INITRD_DIR)/{bin,sbin,etc,proc,sys,usr/{bin,sbin}}
	@cd $(BIN_KERNEL) \
	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH=$(INITRD_DIR) $(MULTICPU) 
#	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH=$(INITRD_DIR) $(MULTICPU) modules_install
	@cd $(INITRD_DIR) \
	 && find . | cpio --quiet -H newc -o --owner=0.0 > $(EMUL_DIR)/initrd

# +------------------------------------------------------------
# | Emulacja
# | machine ID and DTB address is assigned to linux when 
# +------------------------------------------------------------

emulate: $(EMUL_DIR)/vmlinuz $(EMUL_DIR)/initrd
	qemu-system-aarch64 -M raspi3b -cpu cortex-a53 -kernel $(EMUL_DIR)/vmlinuz -initrd $(EMUL_DIR)/initrd -dtb ./dtb/bcm2837-rpi-3-b.dtb -append "console=ttyAMA0 init=/init" -serial stdio

# +------------------------------------------------------------
# | Administracyjne
# +------------------------------------------------------------

clean:
	@rm -rf bin emu initrd src

.phony: src src/busybox src/kernel toolchain crossdev kernconf busyboxconf emulate dl dl/kernel dl/busybox

.PRECIOUS: \
$(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2 \
$(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.bz2
