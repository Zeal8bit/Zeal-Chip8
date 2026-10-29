cmake_minimum_required(VERSION 3.16)

if(NOT EXISTS "$ENV{ZOS_PATH}/cmake/zos_init.cmake")
    message(FATAL_ERROR "Set ZOS_PATH to a Zeal 8-bit OS checkout with the CMake toolchain, or build with zde cmake.")
endif()
if(NOT EXISTS "$ENV{ZVB_SDK_PATH}/include/zvb_hardware_h.asm")
    message(FATAL_ERROR "Set ZVB_SDK_PATH to a Zeal Video Board SDK checkout.")
endif()

set(ZOS_TOOLCHAIN z88dk)
include("$ENV{ZOS_PATH}/cmake/zos_init.cmake")

project(chip8 LANGUAGES ASM)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin")
add_executable(chip8 src/main.asm src/instr.asm src/keypad.asm src/screen.asm)
target_include_directories(chip8 PRIVATE "$ENV{ZVB_SDK_PATH}/include")
target_link_options(chip8 PRIVATE -m)

# The ZOS z88dk toolchain does not scan assembler INCLUDE directives.
set(zos_headers "$ENV{ZOS_PATH}/sdk/z88dk-z80asm")
set_property(SOURCE src/main.asm src/instr.asm src/keypad.asm src/screen.asm APPEND PROPERTY
    OBJECT_DEPENDS "${zos_headers}/zos_sys.asm;${zos_headers}/zos_err.asm")
set_property(SOURCE src/main.asm src/screen.asm APPEND PROPERTY
    OBJECT_DEPENDS "$ENV{ZVB_SDK_PATH}/include/zvb_hardware_h.asm")
set_property(SOURCE src/keypad.asm APPEND PROPERTY
    OBJECT_DEPENDS "${zos_headers}/zos_keyboard.asm")

# ORG in SECTION TEXT causes z80asm to emit chip8_TEXT.bin.
add_custom_command(TARGET chip8 POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/chip8_TEXT.bin" "$<TARGET_FILE:chip8>"
    BYPRODUCTS "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/chip8_TEXT.bin"
               "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/chip8.map"
    VERBATIM
)
