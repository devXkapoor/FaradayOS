boot.bin: src/boot.asm
	nasm -f bin src/boot.asm -o boot.bin

run: boot.bin
	qemu-system-i386 -drive file=boot.bin,format=raw,index=0,if=floppy -boot a

clean:
	rm -f *.bin

.PHONY: run clean
