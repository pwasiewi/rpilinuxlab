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

KERNEL_VER=6.6.5
KERNEL_MD5=528c4c09d2802c2a387b7740550d8a5a

# +------------------------------------------------------------
# | Architektura
# +------------------------------------------------------------

ARCH=x86_64
CROSS_COMPILE=x86_64-pc-linux-gnu

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
	@if ! md5sum -c --status $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).md5; then \
	    echo "Pobieranie busybox-$(BUSYBOX_VER).tar.bz2"; \
	    wget -O $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2 http://busybox.net/downloads/busybox-$(BUSYBOX_VER).tar.bz2; \
	fi
	touch $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2

$(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz:
	@mkdir -p $(DOWNLOAD_DIR)
	@echo "$(KERNEL_MD5)  $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz" > $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).md5
	@if ! md5sum -c --status $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).md5; then \
	    echo "Pobieranie linux-$(KERNEL_VER).tar.xz"; \
	    wget -O $(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.xz http://www.kernel.org/pub/linux/kernel/v4.x/linux-$(KERNEL_VER).tar.xz; \
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
# | Zarządzanie downloadami
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
# +------------------------------------------------------------\
#########
#/etc/gentoo-release:
#	@echo "Potrzebujesz do tego Gentoo!"
#	exit
#
#/usr/bin/x86_64-softfloat-linux-gnueabi-gcc:
#	@USE="-fortran nossp" crossdev --target x86_64-softfloat-linux-gnueabi-gcc  --stable  --gcc 7.3.0-r1 --libc 2.25-r11 --kernel 4.16.9 -oO /usr/portage
#
#/usr/bin/crossdev:
#	@emerge -av crossdev
#
#gentoo: /etc/gentoo-release
#
#crossdev:	gentoo /usr/bin/crossdev
#
#toolchain:	crossdev /usr/bin/x86_64-softfloat-linux-gnueabi-gcc
#	@echo $(HERE)

# +------------------------------------------------------------
# | Konfiguracja binarek poza drzewo źródłowe
# +------------------------------------------------------------

$(BIN_KERNEL)/Makefile: $(SRC_KERNEL)/Makefile
	mkdir -p $(BIN_KERNEL)
	@cd $(SRC_KERNEL) \
	&& make O=$(BIN_KERNEL) ARCH=$(ARCH)  defconfig \
	&& make O=$(BIN_KERNEL) ARCH=$(ARCH)  kvm_guest.config \

$(BIN_BUSYBOX)/Makefile: $(SRC_BUSYBOX)/Makefile
	@mkdir -p $(BIN_BUSYBOX)
	@cd $(SRC_BUSYBOX) && make O=$(BIN_BUSYBOX) ARCH=$(ARCH)  defconfig

# +------------------------------------------------------------
# | Konfiguracja 
# +------------------------------------------------------------

$(BIN_KERNEL)/.config:	$(BIN_KERNEL)/Makefile

$(BIN_BUSYBOX)/.config:	$(BIN_BUSYBOX)/Makefile

kernconf:	$(BIN_KERNEL)/.config
	@cd $(BIN_KERNEL) && make ARCH=$(ARCH)  menuconfig

busyboxconf:	$(BIN_BUSYBOX)/.config
	@cd $(BIN_BUSYBOX) && make ARCH=$(ARCH)  menuconfig

# +------------------------------------------------------------
# | Kompilacja
# +------------------------------------------------------------

$(BIN_BUSYBOX)/busybox: $(BIN_BUSYBOX)/.config
	@sed -i "s:.*CONFIG_PREFIX=.*:CONFIG_PREFIX=\"$(INITRD_DIR)\":" $(BIN_BUSYBOX)/.config
	#@sed -i "s:.*CONFIG_CROSS_COMPILER_PREFIX=.*:CONFIG_CROSS_COMPILER_PREFIX=\"\":" $(BIN_BUSYBOX)/.config
	@sed -i "s:.*CONFIG_CROSS_COMPILER_PREFIX=.*:CONFIG_CROSS_COMPILER_PREFIX=\"\":" $(BIN_BUSYBOX)/.config
	@sed -i "s/# CONFIG_STATIC is not set/CONFIG_STATIC=y/g" $(BIN_BUSYBOX)/.config
	@cd $(BIN_BUSYBOX) \
	 && make ARCH=$(ARCH)  $(MULTICPU) 
	 #&& make ARCH=$(ARCH)  $(MULTICPU) PREFIX=$(INITRD_DIR)

$(BIN_KERNEL)/arch/x86_64/boot/zImage:	$(BIN_KERNEL)/.config
	@cd $(BIN_KERNEL) \
	 && make ARCH=$(ARCH)  $(MULTICPU)

# +------------------------------------------------------------
# | Składanie INITRD
# +------------------------------------------------------------

$(INITRD_DIR)/bin/busybox: $(BIN_BUSYBOX)/busybox
	@mkdir -p $(INITRD_DIR)
	@cd $(BIN_BUSYBOX) \
	 && make ARCH=$(ARCH) PREFIX=$(INITRD_DIR) install

# +------------------------------------------------------------
# | Składanie Emulatora
# +------------------------------------------------------------

$(EMUL_DIR)/vmlinuz:	$(BIN_KERNEL)/arch/x86_64/boot/zImage
	@mkdir -p $(EMUL_DIR)
	@cd $(BIN_KERNEL) \
	 && make ARCH=$(ARCH)  INSTALL_PATH=$(EMUL_DIR) $(MULTICPU) install
	@cp $(BIN_KERNEL)/arch/x86_64/boot/bzImage $(EMUL_DIR)/vmlinuz
	@touch $(EMUL_DIR)/vmlinuz

$(EMUL_DIR)/initrd:	$(INITRD_DIR)/bin/busybox $(wildcard $(INITRD_DIR)/bin/*) $(wildcard $(INITRD_DIR)/etc/*) $(wildcard $(INITRD_DIR)/sbin/*) $(BIN_KERNEL)/arch/x86_64/boot/zImage
	@mkdir -p $(INITRD_DIR)
	@cp -av $(HERE)/init $(INITRD_DIR)
	@cd $(BIN_KERNEL) \
	 && make ARCH=$(ARCH)  INSTALL_MOD_PATH=$(INITRD_DIR) $(MULTICPU) modules_install
	@cd $(INITRD_DIR) \
	 && find . | cpio --quiet -H newc -o --owner=0.0 > $(EMUL_DIR)/initrd

# +------------------------------------------------------------
# | Emulacja
# +------------------------------------------------------------

emulate: $(EMUL_DIR)/vmlinuz $(EMUL_DIR)/initrd
	qemu-system-x86_64 --enable-kvm -m 4048 -kernel $(EMUL_DIR)/vmlinuz -initrd $(EMUL_DIR)/initrd -append "init=/init" 
	#qemu-system-x86_64 --enable-kvm -m 2048 -kernel $(EMUL_DIR)/vmlinuz -initrd $(EMUL_DIR)/initrd -nographic -append "console=ttyS0" -serial stdio

# +------------------------------------------------------------
# | Administracyjne usuwanie plików
# +------------------------------------------------------------

clean:
	@rm -rf bin emu initrd src

.phony: src src/busybox src/kernel toolchain crossdev kernconf busyboxconf emulate dl dl/kernel dl/busybox

.PRECIOUS: \
$(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VER).tar.bz2 \
$(DOWNLOAD_DIR)/linux-$(KERNEL_VER).tar.bz2
