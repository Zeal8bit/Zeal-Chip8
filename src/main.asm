; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "zos_sys.asm"
    INCLUDE "zvb_hardware_h.asm"

    SECTION TEXT
    ORG 0x4000

    EXTERN exec_tick
    EXTERN exec_instruction
    EXTERN screen_clear
    EXTERN screen_render
    EXTERN screen_get_byte_at
    EXTERN screen_set_byte_at
    EXTERN screen_init
    EXTERN c_ram

_start:
    call screen_init
    call load_rom_in_ram

loop:
    ld de, 1
    MSLEEP()
    ; call wait_for_vblank
    call exec_instruction
    ; call wait_for_no_vblank
    call exec_tick
    jp loop
    ; End of the program
    ld h, 0
    EXIT()


wait_for_vblank:
    in a, (IO_CTRL_STATUS_REG)
    bit 1, a
    jr z, wait_for_vblank
    ret


wait_for_no_vblank:
    in a, (IO_CTRL_STATUS_REG)
    bit 1, a
    jr nz, wait_for_no_vblank
    ret


load_rom_in_ram:
    ; Load the ROM at 0x200 in RAM
    ld de, c_ram + 0x200
    ld hl, rom
    ld bc, rom_end - rom
    ldir
    ret


rom: INCBIN "snake.ch8"
rom_end: