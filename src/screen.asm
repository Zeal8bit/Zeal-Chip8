; SPDX-FileCopyrightText: 2024 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    INCLUDE "zos_sys.asm"
    INCLUDE "zvb_hardware_h.asm"

    SECTION TEXT

    DEFC SCREEN_WIDTH  = 64
    DEFC SCREEN_HEIGHT = 32
    DEFC SCREEN_BORDERS = 0

    MACRO ADD_HL_A _
        add l
        ld l, a
        adc h
        sub l
        ld h, a
    ENDM


    DEFC TILESET_PHYS_ADDR = VID_MEM_PHYS_ADDR_START + VID_MEM_TILESET_OFFSET

    ; Initialize the screen output by setting the mode to 640x480 graphics mode
    ; and create 16 different tiles. Since there is no bitmap mode, we are going
    ; to simulate it by dividing each 16x16 tiles into 4 8x8 tiles. Therefore,
    ; there is 16 different combinations. This routine generates them all, starting
    ; at tile 0 (up to 15 included).
    ; Parameters:
    ;   None
    PUBLIC screen_init
screen_init:
    ; Since we don't need two layers and 2 colors are enough, switch to 640x480 4-bit mode
    ld a, VID_MODE_GFX_640_4BIT
    out (IO_CTRL_VID_MODE), a
    ; Map the tileset in page 2
    ld de, 0x8000
    ld bc, TILESET_PHYS_ADDR & 0xffff
    ld h, TILESET_PHYS_ADDR >> 16
    MAP()
    ; Generate the 16 combinations as described above
    ld b, 16
    ; Point to the tile 0
    ld hl, 0x8000
_screen_init_loop:
    ld a, 16
    sub b
    push bc
    ld de, 0
    ld bc, 0
    ; Check each bit and generate the tile, which is divided in four:
    ; Top-left: bit 3
    ; Top-right: bit 2
    ; Bottom-left: bit 1
    ; Bottom-right: bit 0
    ; If bit 3 is 1, store 0xff in D, else store 0 in D
    ; If bit 2 is 1, store 0xff in E, else store 0 in E
    ; If bit 1 is 1, store 0xff in B, else store 0 in B
    ; If bit 0 is 1, store 0xff in C, else store 0 in C
    rrca
    jr nc, _screen_init_skip_bit0
    dec c   ; Set C to 0xFF
_screen_init_skip_bit0:
    rrca
    jr nc, _screen_init_skip_bit1
    dec b
_screen_init_skip_bit1:
    rrca
    jr nc, _screen_init_skip_bit2
    dec e
_screen_init_skip_bit2:
    rrca
    jr nc, _screen_init_skip_bit3
    dec d
_screen_init_skip_bit3:
    call write_tile
    pop bc
    djnz _screen_init_loop
  IF SCREEN_BORDERS
    ; Generate a grey tile (color 0x7) as tile 16
    ld bc, 128
    ld e, 0x77
    call vramset
  ENDIF

  IF SCROLL_SCREEN
    ; Scroll left the screen, so that the virtual screen is in the middle
    ; Scroll left   4 tiles (640 - 4*16 = 640 - 64  = 576px)
    ; Scroll bottom 7 tiles (480 - 7*16 = 480 - 112 = 368px)
    ld a, 576 & 0xff
    out (IO_CTRL_L0_SCR_X_LOW), a
    ld a, 576 >> 8
    out (IO_CTRL_L0_SCR_X_HIGH), a
    ld a, 368 & 0xff
    out (IO_CTRL_L0_SCR_Y_LOW), a
    ld a, 368 >> 8
    out (IO_CTRL_L0_SCR_Y_HIGH), a
  ENDIF

    ; Use page 1 for this code, page 2 for the vram and page 3 for the stack and data
    ld de, 0x8000
    ld bc, VID_MEM_PHYS_ADDR_START & 0xffff
    ld h, VID_MEM_PHYS_ADDR_START >> 16
    MAP()
    ; Clear the tilemap by showing tile 0 everywhere
    ld hl, 0x8000 + VID_MEM_LAYER0_OFFSET
    ld bc, 80*40
  IF SCREEN_BORDERS
    ld e, 0x10
  ELSE
    ld e, 0
  ENDIF
    call vramset
    ; Similarly for the layer 1
    ld hl, 0x8000 + VID_MEM_LAYER1_OFFSET
    ld bc, 80*40
  IF SCREEN_BORDERS
    ld e, 0x10
  ELSE
    ld e, 0
  ENDIF
    call vramset
clear_virtual_screen:
    ; Set the top-left rectangle (32*16 tiles) to tile 0
    ld hl, 0x8000 + VID_MEM_LAYER0_OFFSET
    ld c, 16
    ld de, 80 - 32 ; max tiles per line - used tiles
_screen_init_height_loop:
    ld b, 32
_screen_init_width_loop:
    ld (hl), 0
    inc hl
    djnz _screen_init_width_loop
    add hl, de
    dec c
    jr nz, _screen_init_height_loop
    ret


    ; Write a new tile, that is split in 4 where the from top left to bottom right pixels are
    ; represented as follows:
    ;   +-------+
    ;   | D | E |
    ;   +---+---+
    ;   | B | C |
    ;   +---+---+
    ; Where each subcell is 8x8 pixels
    ; Parameters:
    ;   HL - Tile address
    ;   DEBC - Pixel data
write_tile:
    ; In 4-bit mode, each pixel is one nibble, so 8 pixels take 4 bytes
    ; Generate 8 lines
    ld a, 8
_write_tile_top_lines:
    ld (hl), d
    inc hl
    ld (hl), d
    inc hl
    ld (hl), d
    inc hl
    ld (hl), d
    inc hl
    ld (hl), e
    inc hl
    ld (hl), e
    inc hl
    ld (hl), e
    inc hl
    ld (hl), e
    inc hl
    dec a
    jr nz, _write_tile_top_lines
    ; Same for the bottom lines
    ld a, 8
_write_tile_bottom_lines:
    ld (hl), b
    inc hl
    ld (hl), b
    inc hl
    ld (hl), b
    inc hl
    ld (hl), b
    inc hl
    ld (hl), c
    inc hl
    ld (hl), c
    inc hl
    ld (hl), c
    inc hl
    ld (hl), c
    inc hl
    dec a
    jr nz, _write_tile_bottom_lines
    ret


vramset:
    ld (hl), e
    inc hl
    dec bc
    ld a, b
    or c
    jp nz, vramset
    ret




    ; Get 8 pixels from the screen located at coordiantes (D, E)
    ; Parameters:
    ;   D - X coordinate
    ;   E - Y coordinate
    ; Returns:
    ;   A - 8 pixels
    ; Alters:
    ;   A
    PUBLIC screen_get_byte_at
screen_get_byte_at:
    push bc
    push hl
    ; Calculate the number of pixels to skip to point to the line E.
    ; One byte represents 1 pixel, so we have to multiply by 64.
    ; Make sure the Vy coordinate is between 0 and SCREEN_HEIGHT - 1
    ld a, e
    and SCREEN_HEIGHT - 1
    rrca
    rrca
    ld h, a
    and 0xc0
    ld l, a
    ld a, h
    and 7
    ld h, a
    ; Add X coordinates, guaranteed no carry
    ld a, d
    and SCREEN_WIDTH - 1
    add l
    ld l, a
    ; Make it point to the VRAM
    ld bc, c_vram
    add hl, bc
    ld (pixels_addr), hl
    ; Dereference HL 8 times
    ld b, 8
    ; Store the result in C
    ld c, 0
get_byte_loop:
    ld a, (hl)
    inc hl
    rrca
    rl c
    djnz get_byte_loop
    ld a, c
    pop hl
    pop bc
    ret

  IF 0
    ; Calculate the number of BYTES to skip to point to the line E.
    ; One byte represents 8 pixels, so we have to multiply by 64/8 = 8.
    ; Make sure the Vy coordinate is between 0 and SCREEN_HEIGHT - 1
    ld a, e
    and SCREEN_HEIGHT - 1
    ; Multiply A by 8
    add a
    add a
    add a
    ; Make HL point to that pixels line
    ld hl, c_vram
    ADD_HL_A()
    ; Here, we need to read 2 bytes because the requested pixels could be in-between two bytes!
    ld a, d
    and SCREEN_WIDTH - 1
    ; Divide D by 8, but keep a backup in C
    ld c, a
    rrca
    rrca
    rrca
    ; The result is at most 7
    and 7
    ; Add this result to HL
    ADD_HL_A()
    ld a, c
    and 7
    ; Save these data for the next call
    ld (pixels_addr), hl
    ld (pixels_shift), a
    jr z, screen_get_byte_shift_0
    ; Store the "left" pixels in B
    ; Store the "right" pixels in C
    ; Shift B left, shift C right, A times
    ; OR them to get an 8-bit value
    ld b, (hl)
    inc hl
    ld c, (hl)
    ; Mask in H
    ld h, 0xff
screen_get_byte_shift:
    ; Shift left B and H
    sla b
    ; Shift right C and H
    srl c
    srl h
    dec a
    jr nz, screen_get_byte_shift
    ; Remove unused bits
    ld a, h
    and c
    ld c, a
    ld a, h
    cpl
    and b
    ; Return A OR B
    or c
    ; Restore saved registers
    pop hl
    pop bc
    ret
screen_get_byte_shift_0:
    ld a, (hl)
    ; Restore saved registers
    pop hl
    pop bc
    ret
  ENDIF

    ; Set 8 pixels to the screen located at coordinates set by the function screen_get_byte_at.
    ; As such, that routine must be called beforehand.
    ; Parameters:
    ;   A - 8 pixels to set
    ; Returns:
    ;   -
    ; Alters:
    ;   A
    PUBLIC screen_set_byte_at
screen_set_byte_at:
    push bc
    push hl
    push de
    ld hl, (pixels_addr)
    ld b, 8
    ld c, a
set_byte_loop:
    xor a
    rl c
    rla
    ld (hl), a
    inc hl
    djnz set_byte_loop
    ld hl, (pixels_vram_addr)
    push hl
    ; Now that the bitmap is modified, we need to upadte the VRAM
    ; We have at most 5 updates to do:
    ;   - 4 if the pixels address is even
    ;   - 5 if the pixels address is odd
    ld hl, (pixels_addr)
    ld b, 1
    bit 6, l
    jp z, set_byte_bottom_line
    dec b
set_byte_bottom_line:
    ; HL contains the address of the pixels that were modified
    bit 0, l
    jp z, set_byte_even
    ; Make HL even
    dec hl
    call set_byte_next_pair
set_byte_even:
    ; We have 4 pairs to set
    call set_byte_next_pair
    call set_byte_next_pair
    call set_byte_next_pair
    call set_byte_next_pair
    ; Pop original pixels_vram_addr from the stack
    pop hl
    ; If B is 0, the next call to this function will affect the next line of tile
    dec b
    jr z, set_byte_end
    ld a, 80
    ADD_HL_A()
set_byte_end:
    ld (pixels_vram_addr), hl
    ; Update pixels_vram_addr to point to the next line of pixels
    pop de
    pop hl
    pop bc
    ret


    ; Calculate the tilemap address (in VRAM) that will be affected by the new pixels
    ; Parameters:
    ;   D - X coordinate
    ;   E - Y coordinate
    ; Alters:
    ;   A
    PUBLIC screen_set_byte_tilemap_addr
screen_set_byte_tilemap_addr:
    push hl
    push bc
    ld a, e
    and SCREEN_HEIGHT - 1 ; between 0 and 31, divide by 2 to between 0 and 15
    srl a
    ; Multiply by 80, since we have 80 tiles per line
    rlca ; x2
    rlca ; x4
    rlca ; x8
    rlca ; x16
    ld l, a
    ld h, 0
    push hl
    add hl, hl ; x32
    add hl, hl ; x64
    pop bc
    add hl, bc
    ; Load the X coordinates
    ld a, d
    and SCREEN_WIDTH - 1
    srl a
    ADD_HL_A()
    ; Page 2 is mapped to VRAM, set highest bit of HL
    set 7, h
    ld (pixels_vram_addr), hl
    pop bc
    pop hl
    ret


    ; Calculate the tile index to show for the pixels pointed by HL
    ; Parameters:
    ;   HL - Address of the pixels to show
    ;   B - 1 if the pixels are the top part of the tile, 0 else
    ; Returns:
    ;   HL - HL + 2
    ; Alters:
    ;   A, C, DE, HL
set_byte_next_pair:
    ; Even address, get the two bits of the tile to show
    ld a, (hl)
    inc hl
    rlca
    or (hl)
    ld c, a
    ; If HL's bit 6 is 0, the new pixels are on the top of the tiles (MSB)
    ; to edit else, they are at the bottom (LSB)
    call set_byte_get_other_line
    ; HL was not altered by the routine above
    inc hl
    ; C contains the final tile value to draw on screen
    ; Each tile will show 2 pixels, so we have a virtual resolution of 32*16 tiles
    ; Update the tile
    push hl
    ld hl, (pixels_vram_addr)
    ld (hl), c
    inc hl
    ld (pixels_vram_addr), hl
    pop hl
    ret



    ; Parameters:
    ;   HL - Pointer to the right pixel of the new tile to render
    ;   C - 2 bits of the current line pointed by HL
    ;   B - 1 if C must be shifted twice, 0 else
set_byte_get_other_line:
    ; If B is 1, check the line below the current one
    push hl
    ; Toggle HL's bit 6
    ld a, 1 << 6
    xor l
    ld l, a
    ld e, (hl)
    dec hl
    ld a, (hl)
    rlca
    or e
    ld e, a
    ; E contains the "other" line's data
    ; if B is 0, return (E << 2) | C
    ; else return (C << 2) | E
    ld a, b
    or a
    jr z, other_line_shift_e
    ; Shift C
    ld a, c
    rlca
    rlca
    or e
    jr other_line_end
other_line_shift_e:
    ld a, e
    rlca
    rlca
    or c
other_line_end:
    ld c, a
    pop hl
    ret


    PUBLIC screen_clear
screen_clear:
    ld hl, c_vram
    ld de, c_vram + 1
    ld (hl), 0
    ld bc, c_vram_end - c_vram - 1
    ldir
    jp clear_virtual_screen


pixels_addr:  DS 2
pixels_vram_addr: DS 2

    SECTION VRAM
    ; Define a single pixel as one byte to simplify the algorithm above
    ; Align it on 128 to be sure bit 6 is cleared for the first 64 bytes
    ALIGN 128
c_vram: DS SCREEN_WIDTH * SCREEN_HEIGHT
c_vram_end:
