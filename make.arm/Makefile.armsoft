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

BUSYBOX_VER=1.31.1
BUSYBOX_MD5=70913edaf2263a157393af07565c17f0

KERNEL_VER=5.6.6
KERNEL_MD5=9de47377c6a0323579392a07a8fade43

# +------------------------------------------------------------
# | Architektura
# +------------------------------------------------------------

ARCH=arm
CROSS_COMPILE=arm-softfloat-linux-gnueabi-

# +------------------------------------------------------------
# | Host -j param
# +------------------------------------------------------------

MULTICPU=-j10

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

$(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz:
	@mkdir -p $(DOWNLOAD_DIR)
	@echo "$(KERNEL_MD5)  $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz" > $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).md5
	@if ! md5sum -c --quiet $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).md5; then \
	    echo "Pobieranie linux-$(KERNEL_VER).tar.xz"; \
	    wget -O $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz http://www.kernel.org/pub/linux/kernel/v5.x/linux-$(KERNEL_VER).tar.xz; \
	fi
	touch $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz

# +------------------------------------------------------------
# | Rozpakowywanie
# +------------------------------------------------------------

$(SRC_BUSYBOX)/Makefile:	$(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2
	@mkdir -p $(SRC_DIR)
	tar xjf $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2 -C $(SRC_DIR)
	touch $(SRC_BUSYBOX)/Makefile

$(SRC_KERNEL)/Makefile:	$(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz
	@mkdir -p $(SRC_DIR)
	tar xJf $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz -C $(SRC_DIR)
	touch $(SRC_KERNEL)/Makefile

# +------------------------------------------------------------
# | Zarządzanie downloadem
# +------------------------------------------------------------

dl/busybox: $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2
dl/kernel:  $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz
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

/usr/bin/arm-softfloat-linux-gnueabi-gcc:
	@USE="-fortran" crossdev --target arm-softfloat-linux-gnueabi --gcc 9.3.0 --libc 2.29-r7 --kernel 5.6.6 -oO /usr/portage

/usr/bin/crossdev:
	@emerge -av crossdev

gentoo: /etc/gentoo-release

crossdev:	gentoo /usr/bin/crossdev

toolchain:	crossdev /usr/bin/arm-softfloat-linux-gnueabi-gcc
	@echo $(HERE)

# +------------------------------------------------------------
# | Konfiguracja binarek poza drzewo źródłowe
# +------------------------------------------------------------

$(BIN_KERNEL)/Makefile: toolchain $(SRC_KERNEL)/Makefile
	mkdir -p $(BIN_KERNEL)
	@cd $(SRC_KERNEL) && make O=$(BIN_KERNEL) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) versatile_defconfig

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
	@sed -i "s:.*CONFIG_CROSS_COMPILER_PREFIX=.*:CONFIG_CROSS_COMPILER_PREFIX=\"arm-softfloat-linux-gnueabi-\":" $(BIN_BUSYBOX)/.config
	@sed -i "s/# CONFIG_STATIC is not set/CONFIG_STATIC=y/g" $(BIN_BUSYBOX)/.config
	@cd $(BIN_BUSYBOX) \
	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) $(MULTICPU)

$(BIN_KERNEL)/arch/arm/boot/zImage:	$(BIN_KERNEL)/.config
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

$(EMUL_DIR)/vmlinuz:	$(BIN_KERNEL)/arch/arm/boot/zImage
	@mkdir -p $(EMUL_DIR)
	@cd $(BIN_KERNEL) \
	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_PATH=$(EMUL_DIR) $(MULTICPU) install
	@cp $(BIN_KERNEL)/arch/arm/boot/zImage $(EMUL_DIR)/vmlinuz
	@touch $(EMUL_DIR)/vmlinuz

$(EMUL_DIR)/initrd:	$(INITRD_DIR)/bin/busybox $(wildcard $(INITRD_DIR)/bin/*) $(wildcard $(INITRD_DIR)/etc/*) $(wildcard $(INITRD_DIR)/sbin/*) $(BIN_KERNEL)/arch/arm/boot/zImage
	@mkdir -p $(INITRD_DIR)/{bin,sbin,etc,proc,sys,usr/{bin,sbin}}
	@cd $(BIN_KERNEL) \
	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH=$(INITRD_DIR) $(MULTICPU) 
#	 && make ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH=$(INITRD_DIR) $(MULTICPU) modules_install
	@cd $(INITRD_DIR) \
	 && find . | cpio --quiet -H newc -o --owner=0.0 > $(EMUL_DIR)/initrd

# +------------------------------------------------------------
# | Emulacja
# | machine ID and DTB address is assigned to linux when bootloader loads
# +------------------------------------------------------------

emulate: $(EMUL_DIR)/vmlinuz $(EMUL_DIR)/initrd
	qemu-system-arm -M versatileab -m 256 -kernel $(EMUL_DIR)/vmlinuz -initrd $(EMUL_DIR)/initrd -dtb bin/kernel/arch/arm/boot/dts/versatile-ab.dtb -append "rdinit=/init" -serial stdio


# +------------------------------------------------------------
# | Administracyjne usuwanie plików
# +------------------------------------------------------------

clean:
	@rm -rf bin emu initrd src

.phony: src src/busybox src/kernel toolchain crossdev kernconf busyboxconf emulate dl dl/kernel dl/busybox

.PRECIOUS: \
$(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2 \
$(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.bz2

