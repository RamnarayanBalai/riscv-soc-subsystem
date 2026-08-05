TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-
CC = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy

all: ../rtl/rom.hex

../rtl/rom.hex: main.c start.S link.ld
	$(CC) -Os -ffreestanding -nostdlib -mabi=ilp32 -march=rv32imc -T link.ld start.S main.c -o firmware.elf
	$(OBJCOPY) -O binary firmware.elf firmware.bin
	python3 -c "import binascii; f=open('firmware.bin', 'rb'); open('../rtl/rom.hex', 'w').write('\\n'.join([binascii.hexlify(d.ljust(4, b'\\x00')[::-1]).decode('utf-8') for d in iter(lambda: f.read(4), b'') if d])); f.close()"

clean:
	rm -f firmware.elf firmware.bin ../rtl/rom.hex
