PROJECT         :=  myos
SOURCE_ROOT     :=  .
BUILD_DIR       :=  build

INCLUDE_DIR     :=
SOURCE_DIR      :=  $(SOURCE_ROOT)
SOURCE_EXCLUDE  :=  $(SOURCE_ROOT)/iso

OBJECT_ROOT     :=  $(BUILD_DIR)/obj
BUILD           :=  $(BUILD_DIR)/$(PROJECT).elf
LDS             :=  link.ld

find             =  $(filter-out $(SOURCE_EXCLUDE),$(wildcard $1/$2)) \
                    $(foreach dir,$(filter-out $(SOURCE_EXCLUDE),$(wildcard $1/*)),$(call find,$(dir),$2))
SOURCE_C        :=  $(foreach dir,$(SOURCE_DIR),$(call find,$(dir),*.c))
SOURCE_S        :=  $(foreach dir,$(SOURCE_DIR),$(call find,$(dir),*.asm))
OBJECT          :=  $(patsubst $(SOURCE_ROOT)%,$(OBJECT_ROOT)%,$(patsubst %.c,%.o,$(SOURCE_C))) \
                    $(patsubst $(SOURCE_ROOT)%,$(OBJECT_ROOT)%,$(patsubst %.asm,%_asm.o,$(SOURCE_S)))

LD              :=  ld
LDFLAGS         :=  -m elf_i386 -T $(LDS)
AS              :=  nasm
SFLAGS          :=  -f elf32
CC              :=  gcc
# modern (PIE/SSP-by-default) host gcc needs the freestanding opt-outs spelled
# out: -fno-pie (fixed-address kernel), -fno-asynchronous-unwind-tables (no
# .eh_frame), -fcf-protection=none (no .note.gnu.property),
# -mgeneral-regs-only (gcc 15 auto-vectorizes into SSE, which #UDs before the
# kernel enables it in CR0/CR4)
CFLAGS          :=  $(INCLUDE_DIR) -c -m32 -ffreestanding -fno-pie \
                    -fno-stack-protector -fno-asynchronous-unwind-tables \
                    -fcf-protection=none -mgeneral-regs-only -Wall

.PHONY: clean

all: $(BUILD)

$(BUILD): $(OBJECT)
	@mkdir -p $(BUILD_DIR)
	$(LD) $(LDFLAGS) -o $(BUILD) $(OBJECT)

$(OBJECT_ROOT)/%_asm.o: $(SOURCE_ROOT)/%.asm
	@mkdir -p $(dir $@)
	$(AS) $(SFLAGS) -o $@ $<

$(OBJECT_ROOT)/%.o: $(SOURCE_ROOT)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(BUILD) $(OBJECT)
