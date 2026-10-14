This page covers the shortest path from zero to a building ReXGlue recompiled project.

## Prerequisites

### All Platforms

- **CMake 3.25+**
- **Ninja** build system

### Windows

- [**Visual Studio 2022 Community Edition**](https://visualstudio.microsoft.com/vs/community/) with the **Desktop development with C++** workload, including:
  - **C++ Clang Compiler for Windows** (20.x or newer)
  - **MSBuild support for LLVM (clang-cl) toolset**

### Linux

- **Clang 20+**
- GTK3 development headers (`libgtk-3-dev` on Debian/Ubuntu)

See [[SDK Install Modes]] for detailed install and discovery options.

## Install the SDK

Clone and build the SDK, then install it to a local prefix:

```bash
git clone --recursive https://github.com/rexglue/rexglue-sdk.git
cd rexglue-sdk
cmake --preset win-amd64          # or linux-amd64
cmake --build out/build/win-amd64 --target install
```

The install step registers the SDK in the CMake user package registry, so downstream projects can find it automatically via `find_package(rexglue)`.

You may also add the `bin/` directory from the install prefix to your `PATH` for easy access to the `rexglue` CLI.

## Initialize a Project

Scaffold a new project with `rexglue init`:

```bash
rexglue init --app_name "foobar" --app_root ./foobar
```

This generates:

| File | Purpose |
|------|---------|
| `CMakeLists.txt` | Project build configuration with SDK discovery |
| `CMakePresets.json` | Platform build presets (win-amd64, linux-amd64) |
| `src/main.cpp` | Application entry point using [[ReXApp]] |
| `src/foobar_app.h` | Your `ReXApp` subclass with override stubs |
| `foobar_config.toml` | [[rexglue CLI Configuration File]] template |
| `generated/rexglue.cmake` | SDK integration script (managed by `rexglue migrate`) |

See [[ReXApp]] for details on the generated project structure.


## Run Code Generation

1. Edit `foobar_config.toml` to point `file_path` at your Xbox 360 XEX binary.
2. Run codegen via the CMake target:

```bash
cmake --build --preset win-amd64-debug --target foobar_codegen
```

3. Rebuild to pick up the generated sources:

```bash
cmake --build --preset win-amd64-debug
```

See [[rexglue CLI Configuration File]] for the full TOML reference, and [[rexglue CLI Commands]] for all command-line options.

> [!NOTE]
> Unresolved functions are expected. You will need to manually specify function boundaries in the [[TOML config|rexglue CLI Configuration File]], provide implementations for missing kernel imports (see [[Kernel State & Objects]]), and iteratively refine the output. This is not a push-button process. The [[codegen pipeline|Codegen Pipeline Overview]] reports unresolved calls as validation errors; use `--force` to generate output anyway and work through them incrementally.
