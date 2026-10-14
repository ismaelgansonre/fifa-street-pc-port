The ReXGlue SDK supports three install modes depending on your workflow needs. Only the discovery block at the top of consumer `CMakeLists.txt` changes; `rex::` target names and link lines are identical across all three modes. See [[Getting Started]] for basic setup.

## Binary Install (recommended)

Build and install the SDK once per machine/branch. Consumer projects discover it via `find_package(rexglue)`.

### Setup

```bash
# Build + install the SDK (only needed once per SDK version/branch)
cmake --preset win-amd64
cmake --build --preset win-amd64 --target install
```

After install, the SDK registers itself in the CMake user package registry automatically. `find_package(rexglue)` will find it on any subsequent configure with no env vars.

> [!NOTE]
> **Windows:** Written to `HKEY_CURRENT_USER\Software\Kitware\CMake\Packages\rexglue`
>
> **Linux/macOS:** Written to `~/.cmake/packages/rexglue/`

### Consumer CMakeLists.txt

`rexglue init` generates this automatically:

```cmake
set(REXSDK "" CACHE PATH "Path to ReXGlue SDK install prefix (overrides auto-discovery)")
set(REXSDK_VERSION "" CACHE STRING "Required ReXGlue SDK version, e.g. 0.2.0 (empty = any)")
if(REXSDK)
    list(PREPEND CMAKE_PREFIX_PATH "${REXSDK}")
elseif(DEFINED ENV{REXSDK})
    list(PREPEND CMAKE_PREFIX_PATH "$ENV{REXSDK}")
endif()
find_package(rexglue ${REXSDK_VERSION} REQUIRED CONFIG)
```

Discovery priority: `REXSDK` cache var > `REXSDK` env var > CMake registry > system paths.

To pin to a specific version, set `REXSDK_VERSION` in your committed `CMakePresets.json`:

```json
"cacheVariables": { "REXSDK_VERSION": "0.2.0" }
```

## Git Submodule

Include the SDK source as a submodule. Good for reproducible builds pinned to a specific commit.

### Setup

```bash
# In your consumer project root:
git submodule add https://github.com/rexglue-sdk/rexglue-sdk thirdparty/rexglue-sdk
git submodule update --init --recursive
```

### Consumer CMakeLists.txt

Replace the `find_package` block with:

```cmake
add_subdirectory(thirdparty/rexglue-sdk)
# rex:: targets are now available directly — no find_package needed
```

## FetchContent

CMake downloads and builds the SDK automatically at configure time. Good for CI pipelines and zero-setup onboarding.

### Setup

None. CMake handles this at configure time.

### Consumer CMakeLists.txt

Replace the `find_package` block with:

```cmake
include(FetchContent)
FetchContent_Declare(rexglue
    GIT_REPOSITORY https://github.com/rexglue-sdk/rexglue-sdk
    GIT_TAG        v0.2.0   # pin to a tag or commit hash
)
FetchContent_MakeAvailable(rexglue)
# rex:: targets are now available directly
```

## Version Pinning and Discovery

### Managing Side-by-Side SDK Installs

You may have multiple SDK builds installed at once, for example, `main` and `feat/foo` branches, or different version releases. Each `cmake --install` registers the SDK in the CMake user package registry. Multiple installs coexist -- each prefix gets its own entry. `find_package(rexglue)` picks one automatically; to control *which* one, use the `REXSDK` cache variable.

### Per-project SDK Selection

Set `REXSDK` in a `CMakeUserPresets.json` in your project root. This file should be gitignored so it's machine-local and never committed.

Create `CMakeUserPresets.json` in the project root:

```json
{
    "version": 6,
    "configurePresets": [
        {
            "name": "user-env",
            "hidden": true,
            "cacheVariables": {
                "REXSDK": "/some/install/path"
            }
        },
        { "name": "win-amd64-debug",           "inherits": ["win-amd64-debug",           "user-env"] },
        { "name": "win-amd64-release",          "inherits": ["win-amd64-release",          "user-env"] },
        { "name": "win-amd64-relwithdebinfo",   "inherits": ["win-amd64-relwithdebinfo",   "user-env"] },
        { "name": "linux-amd64-debug",          "inherits": ["linux-amd64-debug",          "user-env"] },
        { "name": "linux-amd64-release",        "inherits": ["linux-amd64-release",        "user-env"] },
        { "name": "linux-amd64-relwithdebinfo", "inherits": ["linux-amd64-relwithdebinfo", "user-env"] }
    ]
}
```

To switch SDK branches: change the `REXSDK` value and delete `CMakeCache.txt` in your build directory before reconfiguring.

### Version Pinning

To ensure a project always uses a specific SDK release, set `REXSDK_VERSION` in the **committed** `CMakePresets.json` (not the gitignored user presets):

```json
"cacheVariables": {
    "REXSDK_VERSION": "0.2.0"
}
```

CMake will reject any SDK that doesn't satisfy the version requirement.
