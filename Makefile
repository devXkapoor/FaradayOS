boot.bin: src/boot.asm
	nasm -f bin src/boot.asm -o boot.bin

run: boot.bin
	qemu-system-i386 -fda boot.bin

clean:
	rm -f *.bin

.PHONY: run clean
