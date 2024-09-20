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


    ; Get the pixels at the given coordinates and XOR them with the new pixels to set
    ; Parameters:
    ;   HL - Address of the new pixels
    ;   D - X coordinate (useless, pixels_addr contains the address to process)
    ;   E - Y coordinate (useless, pixels_addr contains the address to process)
    ; Returns:
    ;   A - Non zero on collision, zero else
    PUBLIC screen_get_and_set_pixels
screen_get_and_set_pixels:
    push bc
    push hl
    push de
    ; Get the new pixel
    ld b, (hl)
    ; Get the vram addr
    ld hl, (pixels_addr)
    ; Put new pixels in C
    ld c, b
    ld d, 0
  REPT 8
    xor a
    rl b
    rla
    xor (hl)
    ld (hl), a
    ; Store this new bit in D
    rrca
    rl d
    inc hl
  ENDR
    ; D has the XORed pixels, C has the new pixel
    ld a, d
    ; Get the former value
    xor c
    ; Check if there was a conflict
    and c
    ; A is ready to be returned, we need to make HL point to the next pixels
    ld bc, 64 - 8
    add hl, bc
    ld (pixels_addr), hl
    pop de
    pop hl
    pop bc
    ret


    ; Parameters:
    ;   B - Number of lines of the new sprite
    ; Returns:
    ;   -
    ; Alters:
    ;   A, BC, DE, HL
    PUBLIC screen_update_view
screen_update_view:
    ; We have at most 5 updates to do:
    ;   - 4 if the pixels address is even
    ;   - 5 if the pixels address is odd
    ld hl, (pixels_addr_backup)
    ld de, (pixels_vram_addr)
    ; Make HL always point to the "top" line of tiles.
    ; One tile line contains 2 CHIP-8 graphics lines.
    res 6, l
screen_update_view_loop:
    push hl
    push de
    ; Similarly, make HL always point to the most left pixel of a
    ; 4x4 CHIP-8 pixel tile
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
    ; Make the VRAM address go to the next line
    ld a, 80
    ADD_HL_A()
    ex de, hl
    ; Make the pixel address go to the next line
    pop hl
    ld a, 128   ; Skip 2 lines (64 pixels each)
    ADD_HL_A()
    djnz screen_update_view_loop
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

    ; Calculate the pixel addr
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
    ; New pixels in A
    ld a, c
    ; Make it point to the VRAM
    ld bc, c_vram
    add hl, bc
    ld (pixels_addr), hl
    ld (pixels_addr_backup), hl

    pop bc
    pop hl
    ret


    ; Calculate the tile index to show for the pixels pointed by HL
    ; Parameters:
    ;   HL - Address of the pixels to show
    ;   DE - Tilemap address
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
    ; HL bit 6 is 0 for sure, the new pixels are on the top of the tiles (MSB)
    call set_byte_get_other_line
    ; HL was not altered by the routine above
    inc hl
    ; C contains the final tile value to draw on screen
    ; Each tile will show 2 pixels, so we have a virtual resolution of 32*16 tiles
    ; Update the tile
    ld a, c
    ld (de), a
    inc de
    ret

    ; Parameters:
    ;   HL - Pointer to the right pixel of the new tile to render
    ;   C - 2 bits of the current line pointed by HL
set_byte_get_other_line:
    ; Set L's bit 6
    set 6, l
    dec hl
    ld a, (hl)
    rrca
    rl c
    inc hl
    ld a, (hl)
    rrca
    rl c
    res 6, l
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
pixels_addr_backup: DS 2
pixels_vram_addr: DS 2

    SECTION VRAM
    ; Define a single pixel as one byte to simplify the algorithm above
    ; Align it on 128 to be sure bit 6 is cleared for the first 64 bytes
    ALIGN 128
c_vram: DS SCREEN_WIDTH * SCREEN_HEIGHT
c_vram_end:
