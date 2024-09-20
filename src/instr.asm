; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "zos_sys.asm"

    SECTION TEXT

    MACRO ADD_HL_A _
        add l
        ld l, a
        adc h
        sub l
        ld h, a
    ENDM

    EXTERN keypad_key_pressed
    EXTERN keypad_key_wait
    EXTERN screen_clear
    EXTERN screen_get_byte_at
    EXTERN screen_update_view
    EXTERN screen_set_byte_tilemap_addr
    EXTERN screen_get_and_set_pixels

    ; Execute a single tick
    PUBLIC exec_tick
exec_tick:
    ld a, (s_delay)
    dec a
    ld (s_delay), a
    ld a, (s_buzzer)
    dec a
    ; If A is 0, a sound should be made
    ld (s_buzzer), a
    ret


    ; Execute the next instruction in the virtual machine
    PUBLIC exec_instruction
exec_instruction:
    ; Load the current instruction c_ram[c_pc]
    ld hl, (c_pc)
    ld bc, c_ram
    add hl, bc
    ; The instruction is stored in big-endian!
    ld d, (hl)
    inc hl
    ld e, (hl)
    inc hl
    ; DE contains the instruction, HL contains the next instruction
    sbc hl, bc
    ld (c_pc), hl   ; Store it back as the next PC
    ; Put the top nibble in A
    ld a, d
    rlca
    rlca
    rlca
    rlca
    and 0xf
    ; Multiply it by 2 and call the the jump table
    rlca
    ld hl, jump_table
    ADD_HL_A()
    ; Dereference the instruction
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ; Jump to the instruction handler
    jp (hl)

    ; Reach here if the instruction is invalid
invalid_instruction:
    S_WRITE3(DEV_STDOUT, invalid_instr_str, invalid_instr_str_end - invalid_instr_str)
    ld h, 1
    EXIT()

invalid_instr_str: DEFM "ERROR: invalid instruction\n"
invalid_instr_str_end:

    ; === Helpers === ;

    ; Get the X register address and extract the NN value from the instruction
    ; Parameters:
    ;   DE - 16-bit instruction of the form _XNN
    ; Returns:
    ;   HL - Address of register X (from the instruction)
    ;   A - NN constant
    ; Alters:
    ;   A, HL
instr_get_x_nn:
    ld a, d
    and 0xf
    ld hl, c_regs
    ADD_HL_A()
    ; Load the constant
    ld a, e
    ret


    ; Get the X and Y registers addresses from the instruction
    ; Parameters:
    ;   DE - 16-bit instruction of the form _XY_
    ; Returns:
    ;   HL - Address of register X
    ;   DE - Address of register Y
    ;   A - Content of register Y
    ; Alters:
    ;   A, DE, HL
instr_get_x_y:
    ; Start by decoding register Y
    ld a, e
    rlca
    rlca
    rlca
    rlca
    and 0xf
    ld hl, c_regs
    push hl
    ADD_HL_A()
    ; HL points to register Y, put it in DE after getting the
    ; high byte of DE
    ld a, d
    and 0xf
    ex de, hl
    ; Retrieve c_regs from the stack
    pop hl
    ADD_HL_A()
    ; HL and DE and ready, dereference DE
    ld a, (de)
    ret


    ; Skip the next instruction by incrementing PC twice
    ; Parameters:
    ;   None
    ; Returns:
    ;   HL - Incremented PC
instr_skip_next_pc:
    ld hl, (c_pc)
    inc hl
    inc hl
    ld (c_pc), hl
    ret


    ; Load the address `ram + I` in HL, registers address in DE and the nibble X in BC (from the instruction _X__)
    ; Used for instructions save/load vx
    ; Parameters:
    ;   DE - 16-bit instruction
    ; Returns:
    ;   DE - Registers address
    ;   HL - Ram + I address
    ;   BC - Nibble X
instr_load_vx_ram_i:
    ld a, d
    and 0xf
    inc a
    ; Store in BC since we will use LDIR
    ld b, 0
    ld c, a
    ; Calculate the destination register (ram[I])
    ld hl, c_ram
    ld de, (c_i)
    add hl, de
    ; Load the source registers
    ld de, c_regs
    ret


    ; Store the carry (from the previous arithmetic operation) in emulated register Vf
store_carry_vf:
    ; Carry goes in Vf
    ld a, 0
    rla
    ld (c_regs + 0xf), a
    ret


    ; ============ Instructions implementation =========== ;

    ; For all the instructions below
    ; Parameters:
    ;   DE     - 16-bit instruction
    ;   [c_pc] - Already set to the next instruction
instruction_0:
    ; Two possible instructions: CLEAR and RETURN
    ld a, e
    cp 0xe0
    jr z, instruction_0_clear
    cp 0xee
    jr z, instruction_0_ret
    jp invalid_instruction

instruction_0_clear:
    jp screen_clear

instruction_0_ret:
    ; Return from subroutine
    ; The stack grows downward
    ld hl, (c_sp)
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (c_sp), hl
    ; Store the return address in PC
    ld (c_pc), de
    ret



    ; ==================================================== ;

instruction_1:
    ; Jump NNN instruction
    ld a, d
    and 0xf
    ld d, a
    ld (c_pc), de
    ret

    ; ==================================================== ;

instruction_2:
    ; Store the next instruction on the stack
    ld bc, (c_pc)
    ; Make the stack grow downward
    ld hl, (c_sp)
    ld (hl), b
    dec hl
    ld (hl), c
    dec hl
    ld (c_sp), hl
    ; Store the new PC (function)
    ; Call NNN instruction
    ld a, d
    and 0xf
    ld d, a
    ld (c_pc), de
    ret

    ; ==================================================== ;

instruction_3:
    ; If Vx != NN, skip the next instruction
    call instr_get_x_nn
    ; HL points to the register, A contains the NN constant
    cp (hl)
    ret nz
    jp instr_skip_next_pc

    ; ==================================================== ;

instruction_4:
    ; If Vx == NN, skip the next instruction
    call instr_get_x_nn
    ; HL points to the register, A contains the NN constant
    cp (hl)
    ret z
    jp instr_skip_next_pc

    ; ==================================================== ;

instruction_5:
    ; If Vx == Vy, skip the next instruction
    call instr_get_x_y
    ; HL points to the register X, DE points to the register Y,
    ; A contains the content of register Y
    cp (hl)
    ret nz
    jp instr_skip_next_pc

    ; ==================================================== ;

instruction_6:
    ; Assign Vx := NN
    call instr_get_x_nn
    ld (hl), a
    ret

    ; ==================================================== ;

instruction_7:
    ; Vx += NN
    call instr_get_x_nn
    add (hl)
    ld (hl), a
    ret

    ; ==================================================== ;

instruction_8:
    ; Keep the instruction lower byte in C
    ld c, e
    call instr_get_x_y
    ;   HL - Address of register X
    ;   DE - Address of register Y
    ;   A - Content of register Y
    ld a, c
    and 0xf
    ; 0
    jr z, instruction_8_x_eq_y
    ; 1
    dec a
    jr z, instruction_8_x_or_y
    ; 2
    dec a
    jr z, instruction_8_x_and_y
    ; 3
    dec a
    jr z, instruction_8_x_xor_y
    ; 4
    dec a
    jr z, instruction_8_x_add_y
    ; 5
    dec a
    jr z, instruction_8_x_sub_y
    ; 6
    dec a
    jr z, instruction_8_shift_right
    ; 7
    dec a
    jr z, instruction_8_y_sub_x
    ; 14
    sub 7
    jr z, instruction_8_shift_left
    jp invalid_instruction

instruction_8_shift_left:
    ; Ambiguous instruction, shift left and put the former bit in Vf
  IF CONFIG_SHIFT_USE_VY
    ld a, (de)  ; Load Vy in A
  ELSE
    ld a, (hl)  ; Load Vx in A
  ENDIF
    add a
    ld (hl), a
    jp store_carry_vf

instruction_8_shift_right:
    ; Ambiguous instruction, shift right and put the former bit in Vf
  IF CONFIG_SHIFT_USE_VY
    ld a, (de)  ; Load Vy in A
  ELSE
    ld a, (hl)  ; Load Vx in A
  ENDIF
    srl a
    ld (hl), a
    jp store_carry_vf

instruction_8_y_sub_x:
    ; Vx = Vy - Vx, borrow in Vf
    ld a, (de)  ; A = Vy
    sub (hl)    ; A = Vy - Vx
    ld (hl), a  ; Vx = A
    ; BE CAREFUL HERE, Vf must be set to 0 IF BORROW
    ; So invert the carry flag
    ccf
    jp store_carry_vf

instruction_8_x_sub_y:
    ; Vx -= Vy, borrow in Vf
    ex de, hl   ; swap Vx and Vy
    ld a, (de)  ; Load Vx in A
    sub (hl)    ; A = Vx - Vy
    ld (de), a  ; Vx = A
    ; BE CAREFUL HERE, Vf must be set to 0 IF BORROW
    ; So invert the carry flag
    ccf
    jp store_carry_vf

instruction_8_x_add_y:
    ; Vx ^= Vy
    ld a, (de)
    add (hl)
    ld (hl), a
    jp store_carry_vf


instruction_8_x_xor_y:
    ; Vx ^= Vy
    ld a, (de)
    xor (hl)
    ld (hl), a
    ret

instruction_8_x_and_y:
    ; Vx &= Vy
    ld a, (de)
    and (hl)
    ld (hl), a
    ret

instruction_8_x_or_y:
    ; Vx |= Vy
    ld a, (de)
    or (hl)
    ld (hl), a
    ret

instruction_8_x_eq_y:
    ; Vx := Vy
    ld a, (de)
    ld (hl), a
    ret

    ; ==================================================== ;

instruction_9:
    ; If Vx != Vy, skip the next instruction
    call instr_get_x_y
    cp (hl)
    ret z
    jp instr_skip_next_pc

    ; ==================================================== ;

instruction_a:
    ; Load the I register
    ld a, d
    and 0xf
    ld d, a
    ld (c_i), de
    ret

    ; ==================================================== ;

instruction_b:
    ; Jump to NNN + V0 register content
    ex de, hl
    ld a, h
    and 0xf
    ld h, a
    ; HL contains NNN, get the content of V0 register
    ld a, (c_regs)
    ADD_HL_A()
    ld (c_pc), hl
    ret

    ; ==================================================== ;

instruction_c:
    ; Generate a random value, `and` it with NN and store it in Vx
    call instr_get_x_nn
    ; A contains NN, HL contains the address of Vx
    ld e, a
    ; Random value in A
    ld a, r
    and e
    ld (hl), a
    ret

    ; ==================================================== ;

instruction_d:
    out (0x86), a
    ; Get the lowest nibble and store it in B
    ld a, e
    and 0xf
    ld b, a
    call instr_get_x_y
    ; Organize the register as follows:
    ; D = Vx
    ; E = Vy
    ld e, a
    ld d, (hl)
    call screen_set_byte_tilemap_addr
    ; Load ram + I in HL
    push bc
    ld hl, c_ram
    ld bc, (c_i)
    add hl, bc
    pop bc
    ; Clear the Vf flag
    xor a
    ld (c_regs + 0xf), a
    ; Iterate over the B bytes (B*8 pixels)
    push bc
draw_byte:
    ; Get the pixels that are located at (D, E) on screen
    call screen_get_and_set_pixels
    or a
    ; No colision if flag is z here
    jr z, _draw_byte_no_colision
    ld a, 1
    ld (c_regs + 0xf), a
_draw_byte_no_colision:
    ; Go to the next line and load the next byte
    inc e
    inc hl
    djnz draw_byte
    pop bc
    ; We have to re-iterate and update the screen now
    call screen_update_view
    out (0x86), a
    ret

    ; ==================================================== ;

instruction_e:
    ; Get the register X address in HL
    call instr_get_x_nn
    ; Two different instructions that test a key press
    ld a, e
    cp 0x9e
    jr z, instruction_e_not_pressed
    cp 0xa1
    jr z, instruction_e_pressed
    jp invalid_instruction

instruction_e_not_pressed:
    ld a, (hl)
    call keypad_key_pressed
    ; A is 1 if pressed, if that's the case, skip the next instruction
    or a
    ret z
    jp instr_skip_next_pc

instruction_e_pressed:
    ld a, (hl)
    call keypad_key_pressed
    ; Skip the next instruction is key is NOT pressed (A == 0)
    or a
    ret nz
    jp instr_skip_next_pc

    ; ==================================================== ;

instruction_f:
    ; There are multiple instructions, make it simple this time, no jump table
    call instr_get_x_nn
    ; HL contains the address of Vx, A contains the constant
    cp 0x7
    jr z, instruction_f_vx_delay
    cp 0xa
    jr z, instruction_f_vx_key
    cp 0x15
    jr z, instruction_f_delay_vx
    cp 0x18
    jr z, instruction_f_buzzer_vx
    cp 0x1e
    jr z, instruction_f_i_vx
    cp 0x29
    jr z, instruction_f_i_hex_vx
    cp 0x33
    jr z, instruction_f_bcd_vx
    cp 0x55
    jr z, instruction_f_save_vx
    cp 0x65
    jr z, instruction_f_load_vx
    jp invalid_instruction

instruction_f_vx_delay:
    ; Store the delay in Vx register
    ld a, (s_delay)
    ld (hl), a
    ret

instruction_f_vx_key:
    ; Wait for a keypress and store it in Vx
    push hl
    call keypad_key_wait
    pop hl
    ld (hl), a
    ret

instruction_f_delay_vx:
    ; Store Vx register content in delay special register
    ld a, (hl)
    ld (s_delay), a
    ret

instruction_f_buzzer_vx:
    ; Store Vx register content in buzzer special register
    ld a, (hl)
    ld (s_buzzer), a
    ret

instruction_f_i_vx:
    ; Add Vx to the register I, which is 12-bit
    ld a, (hl)
    ld hl, (c_i)
    ADD_HL_A()
    ; Make sure I it always 12-bit!
    ld a, h
    and 0xf
    ld h, a
    ld (c_i), hl
    ret

instruction_f_i_hex_vx:
    ; Store the hex character address of the byte contained in Vx
    ld a, (hl)
    and 0xf ; Only keep the last nibble
    ; Multiple A by 5 since each character is 5 bytes big in the font (starting at 0x000)
    ; The result will always be 8-bit
    ld e, a
    add a   ; x2
    add a   ; x4
    add e
    ; Store the result in I
    ld h, 0
    ld l, a
    ld (c_i), hl
    ret

instruction_f_bcd_vx:
    ld c, (hl)
    xor a
    ld b, 8
    ld d, 0
_bcd_loop:
    rl c
    adc a
    daa
    jp nc, _bcd_loop_no_carry
    inc d
_bcd_loop_no_carry:
    djnz _bcd_loop
_bcd_store:
    ld e, a
    ; Store the three nibbles in RAM[I], RAM[I+1], RAM[I+2], big endian
    ld hl, c_ram
    ld bc, (c_i)
    add hl, bc
    ; 100
    ld (hl), d
    inc hl
    ; 10
    ld a, e
    rlca
    rlca
    rlca
    rlca
    and 0xf
    ld (hl), a
    inc hl
    ; 1
    ld a, e
    and 0xf
    ld (hl), a
    ret

instruction_f_save_vx:
    ; Save the registers v0-vx to I address
    call instr_load_vx_ram_i
    ; Registers address in DE, make it the source
    ex de, hl
    ldir
    ret


instruction_f_load_vx:
    call instr_load_vx_ram_i
    ; Registers address in DE
    ldir
    ret


    ; ==================================================== ;

    ; Data an jump table for the instruction emulation

jump_table:
    DW instruction_0
    DW instruction_1
    DW instruction_2
    DW instruction_3
    DW instruction_4
    DW instruction_5
    DW instruction_6
    DW instruction_7
    DW instruction_8
    DW instruction_9
    DW instruction_a
    DW instruction_b
    DW instruction_c
    DW instruction_d
    DW instruction_e
    DW instruction_f


    ; Special register
s_delay: DS 1
s_buzzer: DS 1


    ; Execution starts at emulated address 0x200 (512 bytes)
c_pc: DW 0x200

    ; 16 levels of 16-bit values
c_stack: DS 32
    ; 16 levels of stack depth, make it point to the top of the stack
c_sp: DW c_stack + 31

    ; Special 12-bit register
c_i: DEFS 2

    ; CHIP-8 has 16 8-bit registers
c_regs: DS 16
    ; And a 4096 bytes RAM, the first bytes contain the font
    PUBLIC c_ram
c_ram:
    DEFB 0xF0,0x90,0x90,0x90,0xF0
    DEFB 0x20,0x60,0x20,0x20,0x70
    DEFB 0xF0,0x10,0xF0,0x80,0xF0
    DEFB 0xF0,0x10,0xF0,0x10,0xF0
    DEFB 0x90,0x90,0xF0,0x10,0x10
    DEFB 0xF0,0x80,0xF0,0x10,0xF0
    DEFB 0xF0,0x80,0xF0,0x90,0xF0
    DEFB 0xF0,0x10,0x20,0x40,0x40
    DEFB 0xF0,0x90,0xF0,0x90,0xF0
    DEFB 0xF0,0x90,0xF0,0x10,0xF0
    DEFB 0xF0,0x90,0xF0,0x90,0x90
    DEFB 0xE0,0x90,0xE0,0x90,0xE0
    DEFB 0xF0,0x80,0x80,0x80,0xF0
    DEFB 0xE0,0x90,0x90,0x90,0xE0
    DEFB 0xF0,0x80,0xF0,0x80,0xF0
    DEFB 0xF0,0x80,0xF0,0x80,0x80
    DS 4096 - 80 ; 80 is the size of the font in bytes
    PUBLIC c_ram_end
c_ram_end: