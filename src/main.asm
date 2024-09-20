; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "zos_sys.asm"
    INCLUDE "zvb_hardware_h.asm"

    SECTION TEXT
    ORG 0x4000

    DEFC UPDATES_PER_FRAME = 16

    EXTERN keypad_init
    EXTERN keypad_poll
    EXTERN exec_tick
    EXTERN exec_instruction
    EXTERN screen_clear
    EXTERN screen_render
    EXTERN screen_get_byte_at
    EXTERN screen_set_byte_at
    EXTERN screen_init
    EXTERN c_ram
    EXTERN c_ram_end

_start:
    ; The kernel fills DE and BC with a NULL-terminated string address and its size respectively.
    ; B is 0 for sure
    ld a, c
    or a
    jp z, usage
    call load_rom_in_ram
    ; Load the ROM file in RAM
    call keypad_init
    call screen_init

loop:
    call keypad_poll
    call wait_for_vblank
    call exec_tick
    ld b, UPDATES_PER_FRAME
_next_instr:
    push bc
    call exec_instruction
    pop bc
    djnz _next_instr
    ; Make sure we are not in a v-blank state anymore
    call wait_for_no_vblank
    ; call test_scroll
    jp loop

    ld h, 0
    EXIT()


test_scroll:
    ld hl, (scroll)
    ld a, l
    out (IO_CTRL_L1_SCR_Y_LOW), a
    ld a, h
    out (IO_CTRL_L1_SCR_Y_HIGH), a
    ld a, l
    out (IO_CTRL_L0_SCR_Y_LOW), a
    ld a, h
    out (IO_CTRL_L0_SCR_Y_HIGH), a
    inc hl
    ld (scroll), hl
    ld bc, 640
    or a
    sbc hl, bc
    ret nz
    ld (scroll), hl
    ret

scroll: DEFW 0


usage:
    S_WRITE3(DEV_STDOUT, usage_msg, usage_msg_end - usage_msg)
    ld h, 0
    EXIT()

usage_msg: DEFM "usage: ./chip8.bin <rom.ch8>\n"
usage_msg_end:

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


    ; Load ROM file, in DE inside emulated RAM
load_rom_in_ram:
    ld b, d
    ld c, e
    ld h, O_RDONLY
    OPEN()
    or a
    jp m, load_error
    ; Read the file
    ld h, a
    ld de, c_ram + 0x200
    ld bc, c_ram_end - c_ram - 0x200
    READ()
    or a
    jr nz, close_error
    CLOSE()
    ret

close_error:
    ; H still contains the dev number
    CLOSE()
load_error:
    S_WRITE3(DEV_STDOUT, load_error_msg, load_error_msg_end - load_error_msg)
    ld h, 0
    EXIT()

load_error_msg: DEFM "Error loading the ROM, exiting...\n"
load_error_msg_end:
