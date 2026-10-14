The `rexglue codegen` command produces a self-contained directory of C++ source files that implement the recompiled game logic. This page documents the output layout, file roles, function structure, and integration points. See [[Codegen Pipeline Overview]] for how the analysis and recompilation phases produce this output.

## Output Directory Layout

All files are written to the `out_directory_path` specified in the [[TOML config|rexglue CLI Configuration File]]. Old generated files are cleaned before each run. The naming prefix is the `project_name` from the config.

```
output_dir/
  {project}_init.h            # Image constants, function-definition macros, forward declarations
  {project}_init.cpp          # PPCImageConfig + PPCFuncMappings[]
  {project}_recomp.0.cpp      # Recompiled functions (batch 0)
  {project}_recomp.1.cpp      # Recompiled functions (batch 1)
  {project}_recomp.N.cpp      # ... split for parallel compilation
  sources.cmake               # Source file list for CMake inclusion
```

The number of `_recomp.N.cpp` files depends on the function count and the `functions_per_file` CVar. Splitting keeps individual translation units small enough for reasonable compile times.

## `{project}_init.h`

Defines image layout constants, the function-definition macros that recompiled code uses, and forward declarations for every function in the graph:

```cpp
#pragma once
#define REX_IMAGE_BASE 0x82000000ull
#define REX_IMAGE_SIZE 0x1A00000ull
#define REX_CODE_BASE  0x82020000ull
#define REX_CODE_SIZE  0x190E000ull
#define REXCRT_HEAP 1  // 1 if [rexcrt] contains heap functions, 0 otherwise

#include <rex/ppc.h>
#include <rex/image_info.h>

extern const rex::PPCImageInfo PPCImageConfig;
extern PPCFuncMapping PPCFuncMappings[];

// Macros used by every recompiled function below
#define DECLARE_REX_FUNC(name) \
  REX_EXTERN(name);            \
  REX_EXTERN(__imp__##name)

#define DEFINE_REX_FUNC(name)                                  \
  __attribute__((alias("__imp__" #name))) REX_WEAK_FUNC(name); \
  REX_EXTERN(__imp__##name)

// Import function declarations
DECLARE_REX_FUNC(__imp__NtAllocateVirtualMemory);
DECLARE_REX_FUNC(__imp__DbgPrint);

// Recompiled function declarations
DECLARE_REX_FUNC(xstart);
DECLARE_REX_FUNC(sub_82003A40);
DECLARE_REX_FUNC(rexcrt_RtlAllocateHeap);
// ...
```

`DECLARE_REX_FUNC(name)` declares both the public symbol and the `__imp__`-prefixed strong implementation. Functions mapped to `[rexcrt]` entries in the [[rexglue CLI Configuration File]] use the `rexcrt_` prefix.

### Register locality flags

`#define` flags are emitted for each register locality option enabled in the [[TOML config|rexglue CLI Configuration File]]:

| Define | Corresponding Config Flag |
|---|---|
| `REX_CONFIG_SKIP_LR` | `skip_lr` |
| `REX_CONFIG_CTR_AS_LOCAL` | `ctr_as_local_variable` |
| `REX_CONFIG_XER_AS_LOCAL` | `xer_as_local_variable` |
| `REX_CONFIG_RESERVED_AS_LOCAL` | `reserved_register_as_local_variable` |
| `REX_CONFIG_SKIP_MSR` | `skip_msr` |
| `REX_CONFIG_CR_AS_LOCAL` | `cr_registers_as_local_variables` |
| `REX_CONFIG_NON_ARGUMENT_AS_LOCAL` | `non_argument_registers_as_local_variables` |
| `REX_CONFIG_NON_VOLATILE_AS_LOCAL` | `non_volatile_registers_as_local_variables` |

## `{project}_init.cpp`

Defines `PPCImageConfig` (passed to the SDK runtime to set up the [[guest memory layout|Memory]] and function table) and `PPCFuncMappings[]` (the guest-to-host address table consumed by [[FunctionDispatcher|Runtime Architecture Overview]] during `Runtime::Setup()`):

```cpp
#include "{project}_init.h"

const rex::PPCImageInfo PPCImageConfig = {
    REX_CODE_BASE,      // code_base
    REX_CODE_SIZE,      // code_size
    REX_IMAGE_BASE,     // image_base
    REX_IMAGE_SIZE,     // image_size
    PPCFuncMappings,    // func_mappings
    REXCRT_HEAP,        // rexcrt_heap
};

PPCFuncMapping PPCFuncMappings[] = {
    { 0x82020000, xstart },
    { 0x82003A40, sub_82003A40 },
    { 0x82010000, rexcrt_RtlAllocateHeap },
    // ... all recompiled functions
    { 0x82100000, __imp__NtAllocateVirtualMemory },  // import thunks
    { 0, nullptr }  // null terminator
};
```

`Runtime::Setup()` walks `PPCFuncMappings[]` and calls `function_dispatcher->SetFunction(guest_addr, host_func_ptr)` for each entry. This populates the function dispatch table stored at `IMAGE_BASE + IMAGE_SIZE` in [[guest memory|Memory]], indexed by `(guest_addr - CODE_BASE) * 2` (8-byte function pointers).

## Recompiled Function Structure

Each recompiled function follows a consistent pattern. Here is a representative example showing the key structural elements:

```cpp
DEFINE_REX_FUNC(sub_82003A40) {
    REX_FUNC_PROLOGUE();

    // Local variable declarations (when register locality is enabled)
    PPCRegister r0{};
    PPCRegister r11{};
    PPCRegister r12{};
    PPCCRRegister cr0{};

    // Block: 0x82003A40
    // stwu r1, -0x20(r1)
    ctx.r1.s64 = ctx.r1.s64 + -32;
    PPC_STORE_U32(base, ctx.r1.u32 + 4294967264, ctx.r1.u32);
    // mflr r0
    r0.u64 = ctx.lr;
    // stw r0, 0x24(r1)
    PPC_STORE_U32(base, ctx.r1.u32 + 36, r0.u32);
    // bl sub_82010000
    ctx.lr = 0x82003A50;
    sub_82010000(ctx, base);

    // Block: 0x82003A50
    // cmpwi cr0, r3, 0
    cr0.compare<int32_t>(ctx.r3.s32, 0, ctx.xer);
    // beq cr0, loc_82003A68
    if (cr0.eq) goto loc_82003A68;
    // bl __imp__DbgPrint
    ctx.lr = 0x82003A5C;
    __imp__DbgPrint(ctx, base);

loc_82003A68:
    // Block: 0x82003A68
    // lwz r0, 0x24(r1)
    r0.u64 = PPC_LOAD_U32(base, ctx.r1.u32 + 36);
    // mtlr r0
    ctx.lr = r0.u64;
    // addi r1, r1, 0x20
    ctx.r1.s64 = ctx.r1.s64 + 32;
    // blr
    return;
}
```

Key structural elements:

- **`DEFINE_REX_FUNC(name)`**: emits a weak alias from `name` to a strong `__imp__name` implementation, and opens the function body with the standard recompiled-function signature `void(PPCContext& ctx, uint8_t* base)`. The weak alias lets user code [[override any recompiled function|Function Overrides]] by defining a strong symbol with the same name.
- **`REX_FUNC_PROLOGUE()`**: per-function prologue. Currently asserts membase alignment and (when profiling is enabled) opens a Tracy zone.
- **Local variable declarations**: Only registers actually used in the function are declared, sized by the locality flags in [[rexglue CLI Configuration File]].
- **Block comments**: Each basic block is annotated with its guest address. The original PPC disassembly appears as comments alongside each emitted C++ statement.
- **Labels**: Internal branch targets use `loc_XXXXXXXX:` labels. Conditional branches emit `goto loc_XXXXXXXX;` for intra-function targets.
- **Function calls**: Set `ctx.lr` to the return address, then call the target directly.
- **Return**: `blr` translates to `return;`.

### SEH Exception Handling

Functions with SEH scope tables (when `--enable_exception_handlers` is used) wrap their body in platform SEH macros:

```cpp
DEFINE_REX_FUNC(sub_82050000) {
    REX_FUNC_PROLOGUE();
    // ... local declarations ...
    SEH_TRY {
        // ... function body ...
    } SEH_CATCH_ALL {
        REXLOG_WARN("SEH exception caught in sub_82050000");
        // Run __finally handlers in reverse order
        sub_82050100(ctx, base);  // __finally handler
        __restgprlr_14(ctx, base);  // Restore caller registers
        SEH_RETHROW;
    } SEH_END
}
```

## Import Declarations

Functions imported from Xbox 360 kernel modules (xboxkrnl.exe, xam.xex) are declared in `{project}_init.h` and appear in the mapping table. The SDK runtime provides implementations for these through its [[kernel module|Kernel State & Objects]] system.

Import thunks are included in `PPCFuncMappings[]` so that indirect calls (via function pointers stored in guest memory) can resolve to the correct host implementation at the import's original thunk address.

## Unresolved Calls

When the [[analysis pipeline|Codegen Pipeline Overview]] cannot resolve a `bl` target to any function in the graph or import table, it reports a validation error:

```
UnresolvedCall (3):
  0x82100000 from 0x82003A48: bl 0x82100000 from 0x82003A48 - target not in any function
```

With `--force`, code generation proceeds and the unresolved call site emits a fatal abort:

```cpp
// FATAL: unresolved function 0x82100000
REX_FATAL("Unresolved call from 0x82003A48 to 0x82100000");
```

> [!WARNING]
> Unresolved calls will abort at runtime if reached. Always investigate them.

**Common causes and resolutions:**

| Cause | Resolution |
|---|---|
| Function not discovered by analysis | Add the address with `size` under `[functions]` in the [[rexglue CLI Configuration File]] (e.g., `0x82000000 = { size = 64 }`) |
| Target is in a data section | Verify the binary actually contains code at that address |
| Import not in the SDK's export tables | Implement the import in your project or add it to the SDK |
| Tail call to mid-function address | Specify the containing function with correct boundaries in config |

## ReXCRT Functions

The `[rexcrt]` section in the [[rexglue CLI Configuration File]] maps C runtime function names to guest addresses. These functions are renamed to `rexcrt_` prefixed names and excluded from recompilation; the SDK provides host-native implementations instead. See [[Memory]] for the ReXCRT allocator implementation.

```toml
[rexcrt]
RtlAllocateHeap = "0x820A0000"
RtlFreeHeap = "0x820A0100"
memcpy = "0x820B0000"
```

In generated code, all call sites targeting these addresses emit the `rexcrt_` name:

```cpp
rexcrt_RtlAllocateHeap(ctx, base);  // instead of sub_820A0000
```

## Project Integration

The `sources.cmake` file defines `GENERATED_SOURCES` which you add to your build target. See [[Function Overrides]] for `REX_HOOK` / `REX_HOOK_RAW` and the stub family, and [[Mid-ASM Hooks]] for in-function injection.

Mid-ASM hook configuration is documented in [[rexglue CLI Configuration File]].
