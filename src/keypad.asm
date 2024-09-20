; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "zos_sys.asm"
    INCLUDE "zos_keyboard.asm"

    SECTION TEXT


keypad_mapping:
    DEFM KB_KEY_X, KB_KEY_1, KB_KEY_2, KB_KEY_3, KB_KEY_Q
    DEFM KB_KEY_W, KB_KEY_E, KB_KEY_A, KB_KEY_S, KB_KEY_D
    DEFM KB_KEY_Z, KB_KEY_C, KB_KEY_4, KB_KEY_R, KB_KEY_F
    DEFM KB_KEY_V
keypad_mapping_end:


    ; Initialize the keypad support
    PUBLIC keypad_init
keypad_init:
    ld h, DEV_STDIN
    ld c, KB_CMD_SET_MODE
    ld de, KB_MODE_RAW | KB_READ_NON_BLOCK
    IOCTL()
    ret


    ; Get the CHIP-8 keypad from a keyboard key
    ; The keys are mapped as followed:
    ;   1 2 3 4
    ;   q w e r
    ;   a s d f
    ;   z x c v
    ; equivalent to CHIP-8's
    ;   1 2 3 c
    ;   4 5 6 d
    ;   7 8 9 e
    ;   a 0 b f
    ; Parameter:
    ;   A - Key to test
    ; Return:
    ;   A - Keypad index
    ; Alters:
    ;   A, BC, HL
keypad_from_kbkey:
    ld b, keypad_mapping_end - keypad_mapping
    ld c, 0
    ld hl, keypad_mapping
keypad_from_kbkey_loop:
    cp (hl)
    jr z, keypad_from_kbkey_found
    inc hl
    inc c
    djnz keypad_from_kbkey_loop
    ; Not found
    ld a, 0xff
    ret
keypad_from_kbkey_found:
    ld a, c
    ret


    ; Ask the kernel for any key pressed.
    PUBLIC keypad_poll
keypad_poll:
    ; Poll the kernel and update the keys
    S_READ3(DEV_STDIN, c_buf, 16)
    ; Make the assumption it will be a success
    ld a, c
    or a
    ret z
    ; Put the read size in B
    ld b, c
keypad_poll_loop:
    ; Dereference the key
    ld a, (de)
    inc de
    cp KB_RELEASED
    jr z, keypad_poll_released
    ; Not release key, check if it's a valid keypad
    call keypad_get_keypad_addr
    jr z, keypad_poll_skip
    ld (hl), 1
    jr keypad_poll_skip
keypad_poll_released:
    ; Release key detect, check the next one
    dec b
    ld a, (de)
    inc de
    call keypad_get_keypad_addr
    jr z, keypad_poll_skip
    ; Valid key, set it as released!
    ld (hl), 0
keypad_poll_skip:
    djnz keypad_poll_loop
    ret

    ; Check if the keyboard key in A is valid
    ; Return:
    ;   Z  - Invalid key
    ;   NZ - Valid key
    ;   HL - Address for the valid key
keypad_get_keypad_addr:
    push bc
    call keypad_from_kbkey
    pop bc
    ; If the key is 0xFF, skip
    inc a
    ret z
    ; The key is valid, return the address
    dec a
    ld hl, c_keys
    add l
    ld l, a
    adc h
    sub l
    ld h, a
    ; Make sure Z is not set
    inc a
    ret


    ; Check if the given key is pressed.
    ; Parameters:
    ;   A - Key to check
    ; Returns:
    ;   A - 1 if key was pressed, 0 else
    PUBLIC keypad_key_pressed
keypad_key_pressed:
    cp 0x10
    jr nc, _keypad_key_pressed_error
    ld hl, c_keys
    ld b, 0
    ld c, a
    add hl, bc
    ld a, (hl)
    ret
_keypad_key_pressed_error:
    xor a
    ret


    ; Wait for a key to be pressed on the keypad. The pressed key will be stored in A.
    ; Parameters:
    ;   None
    ; Returns:
    ;   A - Key pressed
    PUBLIC keypad_key_wait
keypad_key_wait:
    call keypad_key_check_any
    ; If NZ, A contains the key pressed
    ret nz
    call keypad_poll
    jp keypad_key_wait


keypad_key_check_any:
    ; Check if anykey is pressed
    ld b, c_keys_end - c_keys
    ld c, 0
    ld hl, c_keys
keypad_key_check_any_loop:
    ld a, (hl)
    inc hl
    or a
    jr nz, keypad_key_check_found
    inc c
    djnz keypad_key_check_any_loop
    ; Set flag to Z
    xor a
    ret
keypad_key_check_found:
    ; Flags is NZ
    ld a, c
    ret

    ; Temporary buffer
c_buf: DEFS 16
    ; 16 keys,1 if pressed
c_keys: DEFS 16
c_keys_end: