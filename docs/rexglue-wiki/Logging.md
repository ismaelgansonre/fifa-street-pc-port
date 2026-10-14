The logging system provides structured, category-based logging built on [spdlog](https://github.com/gabime/spdlog). Categories are extensible; SDK consumers can register their own without modifying SDK code. [[ReXApp]] initializes logging automatically during startup.

Header: `<rex/logging.h>`

## Categories

Every log message belongs to a **category**. Categories are identified by `LogCategoryId` handles -- lightweight `uint16_t` indices into a flat registry array.

### Built-in SDK Categories

These are `constexpr` globals in `rex::log::` with zero-cost lookup:

| Handle | Logger name | Use for |
|--------|-------------|---------|
| `rex::log::Core` | `core` | General/default messages |
| `rex::log::CPU` | `cpu` | CPU emulation, PPC code |
| `rex::log::APU` | `apu` | Audio processing unit |
| `rex::log::GPU` | `gpu` | Graphics processing unit |
| `rex::log::Kernel` | `krnl` | Kernel/OS emulation |
| `rex::log::System` | `sys` | System emulation layer |
| `rex::log::FS` | `fs` | Filesystem operations |

### Registering Custom Categories

Call `RegisterLogCategory()` to create a new category at runtime. The returned handle works with all logging macros and API functions.

```cpp
#include <rex/logging.h>

// Register once (e.g. as an inline global in a header)
namespace myapp::log {
inline const rex::LogCategoryId Input   = rex::RegisterLogCategory("app.input");
inline const rex::LogCategoryId NetPlay = rex::RegisterLogCategory("app.netplay");
}
```

Categories registered this way automatically inherit the current default sinks (console, file) and respect any matching entries in `LogConfig::category_levels` and `LogConfig::category_sinks`.

Duplicate registrations return the existing handle -- it's safe to call from multiple translation units.

### Defining Convenience Macros

Define shorthand macros for your categories, following the SDK pattern:

```cpp
// myapp_logging.h
#pragma once
#include <rex/logging.h>

namespace myapp::log {
inline const rex::LogCategoryId Input = rex::RegisterLogCategory("app.input");
}

#define MYAPP_INPUT_TRACE(...) REXLOG_CAT_TRACE(::myapp::log::Input, __VA_ARGS__)
#define MYAPP_INPUT_DEBUG(...) REXLOG_CAT_DEBUG(::myapp::log::Input, __VA_ARGS__)
#define MYAPP_INPUT_INFO(...)  REXLOG_CAT_INFO(::myapp::log::Input, __VA_ARGS__)
#define MYAPP_INPUT_WARN(...)  REXLOG_CAT_WARN(::myapp::log::Input, __VA_ARGS__)
#define MYAPP_INPUT_ERROR(...) REXLOG_CAT_ERROR(::myapp::log::Input, __VA_ARGS__)
```

Then use them like any other logging macro:

```cpp
#include "myapp_logging.h"

void PollControllers() {
    MYAPP_INPUT_DEBUG("scanning for connected controllers");
}
```

## Log Levels

Levels follow spdlog conventions, from most to least verbose:

| Level | Use for |
|-------|---------|
| `trace` | Per-instruction, per-iteration detail (massive output) |
| `debug` | Development info, function entry/exit, intermediate state |
| `info` | Normal operational events, progress updates |
| `warn` | Recoverable issues, fallback behaviors, unsupported features |
| `error` | Serious problems affecting functionality |
| `critical` | Fatal errors, memory corruption, unrecoverable state |

Default level is `info` in release builds, `debug` in debug builds.

## Logging Macros

### Parameterized macros (primary API)

These take a `LogCategoryId` as the first argument:

```cpp
REXLOG_CAT_TRACE(rex::log::GPU, "draw call {}", count);
REXLOG_CAT_DEBUG(rex::log::CPU, "register r{} = {:#x}", reg, val);
REXLOG_CAT_INFO(rex::log::Core, "initialized");
REXLOG_CAT_WARN(rex::log::FS, "file not found: {}", path);
REXLOG_CAT_ERROR(rex::log::Kernel, "syscall failed: {}", name);
REXLOG_CAT_CRITICAL(rex::log::Core, "out of memory");
```

### Legacy macros (no category parameter)

These log to their respective built-in category. All existing call sites use these and they remain fully supported:

| Macros | Category |
|--------|----------|
| `REXLOG_TRACE`, `REXLOG_DEBUG`, ... `REXLOG_CRITICAL` | Core |
| `REXCPU_TRACE`, `REXCPU_DEBUG`, ... `REXCPU_CRITICAL` | CPU |
| `REXAPU_TRACE` ... `REXAPU_CRITICAL` | APU |
| `REXGPU_TRACE` ... `REXGPU_CRITICAL` | GPU |
| `REXKRNL_TRACE` ... `REXKRNL_CRITICAL` | Kernel |
| `REXSYS_TRACE` ... `REXSYS_CRITICAL` | System |
| `REXFS_TRACE` ... `REXFS_CRITICAL` | FS |

```cpp
REXLOG_INFO("Application started");        // logs to Core
REXGPU_DEBUG("Shader compiled: {}", name); // logs to GPU
```

### Function-prefixed macros

Automatically prepend the function name to the message:

```cpp
// Parameterized
REXLOG_CAT_FN_INFO(rex::log::GPU, "state={}", s);
// Output: [INFO] [gpu] MyFunction: state=foo

// Legacy (Core category)
REXLOGFN_DEBUG("entered");
// Output: [DEBUG] [core] MyFunction: entered
```

### Thread-ID macros

Prepend the guest thread ID and function name (useful for kernel/runtime logging):

```cpp
// Parameterized
REXLOG_CAT_TID_INFO(rex::log::Kernel, "syscall {}", name);
// Output: [INFO] [krnl] [T:0000ABCD] MySyscall: syscall NtFoo

// Legacy (Kernel category)
REXKRNLFN_TRACE("handling interrupt");
```

### Fatal and assert macros

```cpp
// Log critical error to Core and abort
REX_FATAL("unrecoverable: {}", reason);

// Log critical error to a specific category and abort
REX_FATAL_CAT(rex::log::GPU, "device lost");

// Log with function name and abort
REX_FATAL_FN("null pointer");

// Conditional fatal (abort if condition is false)
REX_FATAL_IF(ptr != nullptr, "allocation failed");

// Debug-only assertions (crash in debug, log error in release)
REX_ASSERT(index < size, "index out of bounds");
REX_ASSERT_RET(handle != nullptr, "null handle", -1);      // returns -1
REX_ASSERT_RET_VOID(ctx != nullptr, "null context");        // returns void
```

## Configuration

### LogConfig Struct

Pass a `LogConfig` to `InitLogging()` for full control:

```cpp
rex::LogConfig config;
config.default_level = spdlog::level::debug;
config.log_to_console = true;
config.log_file = "game.log";
config.console_pattern = "[%^%l%$] [%n] %v";
config.file_pattern = "[%Y-%m-%d %H:%M:%S.%e] [%l] [%n] [t%t] %v";
config.flush_level = spdlog::level::warn;

// Per-category level overrides (by name, works for unregistered categories too)
config.category_levels["gpu"] = spdlog::level::trace;
config.category_levels["app.input"] = spdlog::level::warn;

rex::InitLogging(config);
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `default_level` | `spdlog::level::level_enum` | `info` | Global default level |
| `log_to_console` | `bool` | `true` | Create stdout sink |
| `use_colors` | `bool` | `true` | ANSI color codes on console |
| `log_file` | `const char*` | `nullptr` | Log file path (null = no file) |
| `console_pattern` | `std::string` | `"[%^%l%$] [%n] [t%t] %v"` | Console format pattern |
| `file_pattern` | `std::string` | `"[%Y-%m-%d %H:%M:%S.%e] [%l] [%n] [t%t] %v"` | File format pattern |
| `flush_level` | `spdlog::level::level_enum` | `warn` | Auto-flush threshold |
| `category_levels` | `std::map<std::string, level>` | `{}` | Per-category level overrides |
| `extra_sinks` | `std::vector<spdlog::sink_ptr>` | `{}` | Additional sinks for all loggers |
| `category_sinks` | `std::map<std::string, vector<sink_ptr>>` | `{}` | Per-category extra sinks |
| `category_sinks_exclusive` | `bool` | `false` | If true, per-category sinks replace defaults |

### Simple Initialization

For quick setup without a full config:

```cpp
rex::InitLogging();                                    // console-only, info level
rex::InitLogging("game.log");                          // console + file, info level
rex::InitLogging("game.log", spdlog::level::debug);   // console + file, debug level
```

### BuildLogConfig Helper

Build a `LogConfig` from CLI arguments and environment variables with proper precedence:

```cpp
// Precedence: CLI args > REX_LOG_LEVEL env var > build-type default
auto config = rex::BuildLogConfig(
    log_file_path,          // const char* or nullptr
    cli_log_level,          // e.g. "debug" from --log_level
    cli_category_levels     // e.g. {"gpu": "trace", "cpu": "warn"}
);
rex::InitLogging(config);
```

## Runtime Control

### Changing Levels

```cpp
// Set level for one category
rex::SetCategoryLevel(rex::log::GPU, spdlog::level::trace);

// Set level for all categories
rex::SetAllLevels(spdlog::level::debug);

// Enable CVAR-driven level changes (responds to `log_level` cvar)
rex::RegisterLogLevelCallback();
```

### Managing Sinks

Add or remove sinks at runtime. `AddSink` with no category adds to all loggers (including future ones):

```cpp
// Add a sink to all loggers
auto ring_sink = std::make_shared<spdlog::sinks::ringbuffer_sink_mt>(1024);
rex::AddSink(ring_sink);

// Add a sink to one category only
auto gpu_file = std::make_shared<spdlog::sinks::basic_file_sink_mt>("gpu.log", true);
rex::AddSink(rex::log::GPU, gpu_file);

// Remove a sink
rex::RemoveSink(ring_sink);
rex::RemoveSink(rex::log::GPU, gpu_file);
```

### Changing Patterns

```cpp
rex::SetConsolePattern("[%l] %v");                       // minimal console output
rex::SetFilePattern("[%Y-%m-%d %T.%e] [%l] [%n] %v");   // detailed file output
```

## Category Query API

### Querying Categories

```cpp
// Look up a category by name
auto cat = rex::FindCategory("app.input");
if (cat) {
    rex::SetCategoryLevel(*cat, spdlog::level::trace);
}

// Iterate all registered categories
for (const auto& entry : rex::GetAllCategories()) {
    fmt::print("Category: {} (level: {})\n",
               entry.name,
               spdlog::level::to_string_view(entry.logger->level()));
}
```

### Direct Logger Access

For advanced use cases where you need the spdlog logger directly:

```cpp
// Raw pointer (zero overhead, used by macros internally)
spdlog::logger* logger = rex::GetLoggerRaw(rex::log::GPU);
if (logger && logger->should_log(spdlog::level::debug)) {
    logger->debug("custom message");
}

// Shared pointer (for holding references or manipulating sinks)
auto logger = rex::GetLogger(rex::log::GPU);

// Default (Core) logger
auto core = rex::GetLogger();
```

## Level Parsing Helpers

```cpp
// Parse a level string (case-insensitive)
auto level = rex::ParseLogLevel("debug");     // returns std::optional
auto level2 = rex::ParseLogLevel("WARNING");  // returns warn

// Parse with fallback
auto level3 = rex::ParseLogLevelOr(user_input, spdlog::level::info);
```

Accepted strings: `trace`, `debug`, `info`, `warn`/`warning`, `error`/`err`, `critical`, `off`.

## Formatting Helpers

Convenience formatters in `rex::log::`:

```cpp
rex::log::ptr(0x82000000u);   // "0x82000000"
rex::log::ptr(some_pointer);  // "0x00007FF..."
rex::log::hex(255u);          // "0xFF"
rex::log::boolean(true);      // "true"
```

## CVar Integration

Logging behavior can be controlled at runtime through CVars. The `log_level`, `log_file`, and `log_verbose` CVars are documented in the [[CVar System]] page under the Log category. Call `rex::RegisterLogLevelCallback()` to enable automatic level changes when the `log_level` CVar is modified.

## Complete Example

Here's a full example of a downstream application registering custom categories:

```cpp
// my_game_logging.h
#pragma once
#include <rex/logging.h>

namespace mygame::log {
inline const rex::LogCategoryId Input   = rex::RegisterLogCategory("game.input");
inline const rex::LogCategoryId NetPlay = rex::RegisterLogCategory("game.netplay");
inline const rex::LogCategoryId Save    = rex::RegisterLogCategory("game.save");
}

#define GAME_INPUT_TRACE(...)   REXLOG_CAT_TRACE(::mygame::log::Input, __VA_ARGS__)
#define GAME_INPUT_DEBUG(...)   REXLOG_CAT_DEBUG(::mygame::log::Input, __VA_ARGS__)
#define GAME_INPUT_INFO(...)    REXLOG_CAT_INFO(::mygame::log::Input, __VA_ARGS__)
#define GAME_INPUT_WARN(...)    REXLOG_CAT_WARN(::mygame::log::Input, __VA_ARGS__)

#define GAME_NET_TRACE(...)     REXLOG_CAT_TRACE(::mygame::log::NetPlay, __VA_ARGS__)
#define GAME_NET_DEBUG(...)     REXLOG_CAT_DEBUG(::mygame::log::NetPlay, __VA_ARGS__)
#define GAME_NET_INFO(...)      REXLOG_CAT_INFO(::mygame::log::NetPlay, __VA_ARGS__)
#define GAME_NET_WARN(...)      REXLOG_CAT_WARN(::mygame::log::NetPlay, __VA_ARGS__)

#define GAME_SAVE_INFO(...)     REXLOG_CAT_INFO(::mygame::log::Save, __VA_ARGS__)
#define GAME_SAVE_ERROR(...)    REXLOG_CAT_ERROR(::mygame::log::Save, __VA_ARGS__)
```

```cpp
// main.cpp
#include "my_game_logging.h"

int main() {
    rex::LogConfig config;
    config.default_level = spdlog::level::info;
    config.log_file = "game.log";

    // Crank up input logging for debugging
    config.category_levels["game.input"] = spdlog::level::trace;

    // Send netplay logs to a separate file
    auto net_sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>("netplay.log", true);
    config.category_sinks["game.netplay"] = {net_sink};

    rex::InitLogging(config);
    rex::RegisterLogLevelCallback();

    GAME_INPUT_TRACE("polling controllers, tick {}", tick);
    GAME_NET_INFO("connected to lobby {}", lobby_id);
    GAME_SAVE_INFO("checkpoint saved");

    rex::ShutdownLogging();
}
```
