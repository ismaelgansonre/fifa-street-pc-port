CVars (configuration variables) are the SDK's runtime configuration system. They provide type-safe global settings that can be set from code, command-line arguments, config files, and environment variables.

Header: `<rex/cvar.h>`

## Defining CVars

Define a cvar in exactly one `.cpp` file using the `REXCVAR_DEFINE_*` macros:

```cpp
#include <rex/cvar.h>

REXCVAR_DEFINE_BOOL(audio_mute, false, "Audio", "Mute audio output");
REXCVAR_DEFINE_INT32(texture_cache_limit, 384, "GPU", "Texture cache limit (MB)");
REXCVAR_DEFINE_STRING(log_level, "info", "Log", "Global log level");
```

Each macro takes four arguments:

| Argument | Description |
|----------|-------------|
| `name` | Identifier for the cvar. Creates a global `FLAGS_<name>`. |
| `default_val` | Default value, used until overridden. |
| `category` | Grouping string for UI/query filtering. Use `/` for hierarchy (e.g. `"GPU/D3D12"`). |
| `desc` | Human-readable description. |

### Available Types

| Macro | C++ type | Parsing |
|-------|----------|---------|
| `REXCVAR_DEFINE_BOOL` | `bool` | `"true"`, `"1"`, `"yes"` are true; anything else is false |
| `REXCVAR_DEFINE_INT32` | `int32_t` | `std::from_chars` |
| `REXCVAR_DEFINE_INT64` | `int64_t` | `std::from_chars` |
| `REXCVAR_DEFINE_UINT32` | `uint32_t` | `std::from_chars` |
| `REXCVAR_DEFINE_UINT64` | `uint64_t` | `std::from_chars` |
| `REXCVAR_DEFINE_DOUBLE` | `double` | `std::strtod` |
| `REXCVAR_DEFINE_STRING` | `std::string` | Direct assignment |

### Declaring CVars

To access a cvar defined in another translation unit, declare it with `REXCVAR_DECLARE`:

```cpp
// In a header or another .cpp file
REXCVAR_DECLARE(bool, audio_mute);
REXCVAR_DECLARE(int32_t, texture_cache_limit);
REXCVAR_DECLARE(std::string, log_level);
```

The first argument must match the C++ type from the define macro.

## Reading and Writing Values

### Type-safe access (preferred)

```cpp
// Read
bool muted = REXCVAR_GET(audio_mute);
int32_t limit = REXCVAR_GET(texture_cache_limit);

// Write
REXCVAR_SET(audio_mute, true);
REXCVAR_SET(texture_cache_limit, 512);
```

These expand to direct reads/writes of the underlying `FLAGS_<name>` global. Zero overhead.

### String-based access (dynamic lookup)

For consoles, config UIs, or any context where the cvar name is only known at runtime:

```cpp
std::string val = rex::cvar::GetFlagByName("audio_mute");
bool ok = rex::cvar::SetFlagByName("audio_mute", "true");
```

`SetFlagByName` parses the string, validates constraints, enforces lifecycle rules, and fires change callbacks. Returns `false` if the name is unknown or validation fails.

## Metadata

Chain metadata methods after the define macro to add constraints and lifecycle rules:

```cpp
REXCVAR_DEFINE_INT32(scale, 1, "GPU", "Resolution scale")
    .range(1, 8)
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);

REXCVAR_DEFINE_STRING(backend, "d3d12", "GPU", "Render backend")
    .allowed({"d3d12", "vulkan"})
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);

REXCVAR_DEFINE_DOUBLE(volume, 0.8, "Audio", "Master volume")
    .range(0.0, 1.0)
    .validator([](std::string_view v) { return v != "nan"; });

REXCVAR_DEFINE_BOOL(debug_overlay, false, "Debug", "Show debug overlay")
    .debug_only();
```

### Chain Methods

| Method | Description |
|--------|-------------|
| `.range(min, max)` | Numeric bounds. Rejects values outside `[min, max]`. |
| `.allowed({...})` | String whitelist. Rejects values not in the set. |
| `.lifecycle(lc)` | When the cvar can be modified (see below). |
| `.debug_only()` | Marks the cvar for filtering in release UIs. |
| `.validator(fn)` | Custom `bool(std::string_view)` validation function. |

## Lifecycle Modes

| Lifecycle | Description |
|-----------|-------------|
| `kHotReload` | **Default.** Can be changed at any time with immediate effect. |
| `kRequiresRestart` | Can be changed, but the new value only takes effect after restart. |
| `kInitOnly` | Locked after `FinalizeInit()`. Attempts to modify are rejected. |

## Initialization and Precedence

CVars are initialized in stages during application startup. [[ReXApp]] handles this automatically; only use the raw API if you are bypassing `ReXApp`.

```
Static init         REXCVAR_DEFINE_* macros register flags
     |
Init(argc, argv)    Parse command-line arguments (via CLI11)
     |
LoadConfig(path)    Load TOML config file
     |
ApplyEnvironment()  Apply REX_* environment variables
     |
FinalizeInit()      Lock kInitOnly flags
```

Later sources override earlier ones: environment variables take precedence over the config file, which takes precedence over CLI args, which take precedence over compiled defaults.

### Command-line arguments

`Init()` registers every defined cvar as a CLI11 option. Flags are passed with `--` prefix:

```
myapp --audio_mute true --texture_cache_limit 512 --log_level debug
```

Unrecognized arguments are returned as a `std::vector<std::string>` for the application to handle.

### Config file (TOML)

`LoadConfig()` reads a TOML file. Keys map directly to cvar names:

```toml
audio_mute = true
texture_cache_limit = 512
log_level = "debug"
```

`SaveConfig()` and `SerializeToTOML()` write only modified (non-default) cvars back to TOML.

### Environment variables

`ApplyEnvironment()` checks for environment variables matching the pattern `REX_<UPPER_NAME>`:

| CVar name | Environment variable |
|-----------|---------------------|
| `audio_mute` | `REX_AUDIO_MUTE` |
| `log_level` | `REX_LOG_LEVEL` |
| `d3d12_tiled_shared_memory` | `REX_D3D12_TILED_SHARED_MEMORY` |

## Change Callbacks

Register a callback to react when a cvar's value changes through `SetFlagByName`:

```cpp
rex::cvar::RegisterChangeCallback("audio_mute", [](std::string_view name,
                                                    std::string_view new_value) {
    // Called immediately after the value is set
    UpdateAudioState(new_value == "true");
});

// Remove all callbacks for a cvar
rex::cvar::UnregisterChangeCallbacks("audio_mute");
```

Callbacks are invoked synchronously from the thread that calls `SetFlagByName`.

## Querying CVars

```cpp
// List all registered cvars (sorted by name)
auto all = rex::cvar::ListFlags();

// Filter by category (exact match)
auto gpu = rex::cvar::ListFlagsByCategory("GPU");

// Filter by lifecycle
auto init_only = rex::cvar::ListFlagsByLifecycle(rex::cvar::Lifecycle::kInitOnly);

// Get metadata for a specific cvar
const rex::cvar::FlagEntry* info = rex::cvar::GetFlagInfo("audio_mute");
if (info) {
    // info->name, info->type, info->category, info->description
    // info->lifecycle, info->constraints, info->default_value, info->is_debug_only
}

// List cvars with non-default values
auto modified = rex::cvar::ListModifiedFlags();

// List cvars pending restart
auto pending = rex::cvar::GetPendingRestartFlags();
```

## Resetting CVars

```cpp
// Reset a single cvar to its compiled default
rex::cvar::ResetToDefault("audio_mute");

// Reset all cvars to defaults
rex::cvar::ResetAllToDefaults();

// Check if a cvar has been modified
bool changed = rex::cvar::HasNonDefaultValue("audio_mute");
```

## Built-in UI

[[ReXApp]] provides two built-in overlays for interacting with cvars at runtime:

| Overlay | Hotkey | Header | Description |
|---------|--------|--------|-------------|
| Settings | F4 | `<rex/ui/overlay/settings_overlay.h>` | Visual cvar editor with search, category filtering, and save-to-config |
| Console | `` ` `` | `<rex/ui/overlay/console_overlay.h>` | Log viewer with cvar command input |

## Testing Utilities

The `rex::cvar::testing` namespace provides helpers for unit tests:

```cpp
#include <rex/cvar.h>

// Temporarily bypass kInitOnly restrictions
{
    rex::cvar::testing::ScopedLifecycleOverride override;
    rex::cvar::SetFlagByName("backend", "vulkan");  // Would normally be rejected
}  // Restrictions restored on scope exit

// Reset all cvars to defaults and clear finalization state
rex::cvar::testing::ResetAllForTesting();
```
