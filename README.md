# CHIP-8 emulator for Zeal 8-bit OS

## Building

Use the [Zeal Development Environment](https://github.com/Zeal8bit/zeal-dev-environment):

```sh
zde cmake
```

For a native build, install CMake 3.16 or later and z88dk, then point `ZOS_PATH` and `ZVB_SDK_PATH` to current checkouts of Zeal 8-bit OS and the Zeal Video Board SDK:

```sh
cmake -S . -B build
cmake --build build
```

The executable is `bin/chip8.bin`. Run it on Zeal 8-bit OS with a CHIP-8 ROM as its argument:

```text
./chip8.bin <rom.ch8>
```

To clean the build, run `cmake --build build --target clean` (or `zde cmake build --target clean` with ZDE).
