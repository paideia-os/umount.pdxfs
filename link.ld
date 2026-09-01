# link.ld — umount.pdxfs ELF layout, matching paideia-os's src/user/true.ld
# convention for every satellite-tool ring-3 ELF (paideia-os#1976/#1977).
#
# IMPORTANT: .bss stays contiguous with .data (no forced high address for
# .bss) per paideia-os#1595 — pinning .bss to a fixed address far above
# .data would stretch a single PT_LOAD across a multi-MB hole, wasting one
# physical frame per 4KiB of that hole at load time.

OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0x00400000;

    .text : ALIGN(4K) {
        KEEP(*(.text._start))
        *(.text .text.*)
    } :text

    .rodata : ALIGN(8) {
        *(.rodata .rodata.*)
    } :text

    . = 0x00600000;

    .data : ALIGN(4K) {
        *(.data .data.*)
    } :data

    .bss (NOLOAD) : ALIGN(4K) {
        *(COMMON)
        *(.bss .bss.*)
        . = ALIGN(4K);
    } :data

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame*)
        *(.note.*)
    }
}
