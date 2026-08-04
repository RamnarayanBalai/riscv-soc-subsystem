all: ../rtl/rom.hex

../rtl/rom.hex: main.c start.S link.ld
	riscv32-unknown-elf-gcc -Os -ffreestanding -nostdlib -mabi=ilp32 -march=rv32imc -T link.ld start.S main.c -o firmware.elf
	riscv32-unknown-elf-objcopy -O binary firmware.elf firmware.bin
	python3 -c "import binascii; open('../rtl/rom.hex', 'w').write('\\n'.join([binascii.hexlify(d[::-1]).decode('utf-8') for d in iter(lambda: open('firmware.bin', 'rb').read(4), b'') if len(d) == 4]))"

clean:
	rm -f firmware.elf firmware.bin ../rtl/rom.hex
