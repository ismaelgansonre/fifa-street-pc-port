The codegen configuration is a TOML file passed to `rexglue codegen`. Running [[rexglue init|rexglue CLI Commands]] generates a starter file with the required fields populated. See [[Codegen Pipeline Overview]] for how these options affect the analysis and recompilation phases, and [[Generated Code Structure]] for the output format.

## Required Fields

```toml
project_name = "foobar"
file_path = "assets/default.xex"
out_directory_path = "generated"
```

| Key | Description |
|-----|-------------|
| `project_name` | Name used for generated output files and header guards |
| `file_path` | Path to the Xbox 360 XEX or ELF binary |
| `out_directory_path` | Directory for generated C++ code (default: `generated`) |

## Optional Fields

```toml
patch_file_path = "assets/patch.xexp"
patched_file_path = "assets/default_patched.xex"
```

| Key | Description |
|-----|-------------|
| `patch_file_path` | Path to an XEX patch file. Applied to the binary before analysis. |
| `patched_file_path` | Output path for the patched binary. |

## Code Generation Options

These control how PPC registers and instructions are translated to C++. All default to `false`.


| Key | Default | Description |
|-----|---------|-------------|
| `skip_lr` | `false` | Skip link register saves/restores. Reduces generated code for leaf functions. |
| `skip_msr` | `false` | Skip MSR (Machine State Register) instructions. |
| `ctr_as_local` | `false` | Emit CTR (Count Register) as a local variable instead of reading/writing thread context. Reduces memory traffic in loops. |
| `xer_as_local` | `false` | Emit XER (Integer Exception Register) as a local variable. |
| `cr_as_local` | `false` | Emit CR (Condition Register) fields as local variables. Significant codegen improvement for branch-heavy code. |
| `reserved_as_local` | `false` | Emit reserved registers (r1, r2, r13) as local variables. |
| `non_argument_as_local` | `false` | Emit non-argument volatile registers (r11-r12) as local variables. |
| `non_volatile_as_local` | `false` | Emit non-volatile registers (r14-r31) as local variables. |
| `enable_exception_handlers` | `false` | Generate SEH exception handler wrappers for functions with PDATA exception entries. Also available as a CLI flag (`--enable_exception_handlers`). |

## Special Addresses

```toml
setjmp_address = 0x82001000
longjmp_address = 0x82002000
```

| Key | Description |
|-----|-------------|
| `setjmp_address` | Address of the `setjmp` function in the binary. Required for correct non-local jump handling. |
| `longjmp_address` | Address of the `longjmp` function in the binary. |


## Analysis Tuning

These live under the `[analysis]` table.

```toml
[analysis]
max_jump_extension = 65536
data_region_threshold = 16
large_function_threshold = 1048576
exception_handler_funcs = []
```

| Key | Default | Description |
|-----|---------|-------------|
| `max_jump_extension` | `65536` | Maximum bytes to extend a function boundary when following jump table targets. |
| `data_region_threshold` | `16` | Consecutive invalid instructions before marking a region as embedded data. |
| `large_function_threshold` | `1048576` | Byte threshold (1 MB) for "large function" warnings during analysis. |
| `exception_handler_funcs` | `[]` | Array of addresses for exception handler functions beyond those detected automatically. |

## Manual Overrides

### Functions

Define function boundaries, names, or parent-child relationships when auto-detection gets it wrong. Entries are keyed by hex address under the `[functions]` table.

```toml
[functions]
# Name a function
0x82000000 = { name = "MyFunction" }

# Explicit size in bytes
0x82000100 = { size = 64 }

# Explicit end address (exclusive)
0x82000200 = { end = 0x82000280 }

# Discontinuous chunk belonging to a parent function
0x82000300 = { parent = 0x82000000, size = 32 }

# Fields can be combined: named function with explicit boundaries
0x82000400 = { name = "GameUpdate", size = 128 }
0x82000500 = { name = "GameUpdate_Chunk1", parent = 0x82000400, end = 0x82000580 }
```

| Field | Description |
|-------|-------------|
| `name` | Custom symbol name. If omitted, the function is named `sub_XXXXXXXX`. |
| `size` | Explicit size in bytes. Mutually exclusive with `end`. |
| `end` | End address (exclusive). Must be greater than the function address. Mutually exclusive with `size`. |
| `parent` | Address of the parent function. Makes this entry a discontinuous chunk belonging to another function rather than a standalone function. |

### Switch Tables

Manually define switch/jump tables when auto-detection fails. Uses TOML array-of-tables syntax.

```toml
[[switch_tables]]
address = 0x82000000
register = 11
labels = [0x82000100, 0x82000200, 0x82000300]
```

| Field | Required | Description |
|-------|----------|-------------|
| `address` | Yes | Address of the `bctr` instruction that dispatches the jump table. |
| `register` | Yes | GPR number used as the jump index. |
| `labels` | Yes | Array of branch target addresses (the jump table entries). |

### Invalid Instructions

Mark data patterns that look like code but are not (e.g., embedded constants). Prevents false function discovery.

```toml
[[invalid_instructions]]
data = 0xDEADBEEF
size = 64
```

| Field | Required | Description |
|-------|----------|-------------|
| `data` | Yes | The 32-bit data pattern to mark as non-code. |
| `size` | Yes | Size in bytes of the data region starting at instances of this pattern. |


### Mid-ASM Hooks

Inject calls to native C++ functions at specific instruction addresses. Uses TOML array-of-tables syntax.

```toml
[[midasm_hook]]
address = 0x82000000
name = "MyHook"
registers = ["r3"]
after_instruction = false
jump_address_on_true = 0x82000004
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `address` | Yes | (required) | Address of the PPC instruction to hook. |
| `name` | Yes | (required) | Name of the C++ hook function to call. |
| `registers` | No | `[]` | Registers passed to the hook function as `PPCRegister&` arguments. |
| `after_instruction` | No | `false` | If `true`, the hook fires after the instruction executes; if `false`, before it. |
| `return` | No | `false` | Unconditionally return from the recompiled function after the hook. |
| `jump_address` | No | `0` | Unconditionally jump to this address after the hook. |
| `return_on_true` | No | `false` | Return if the hook function returns `true`. |
| `return_on_false` | No | `false` | Return if the hook function returns `false`. |
| `jump_address_on_true` | No | `0` | Jump to this address if the hook returns `true`. |
| `jump_address_on_false` | No | `0` | Jump to this address if the hook returns `false`. |

> [!WARNING]
> You cannot combine `return` with `jump_address`, or mix unconditional and conditional control flow options. The codegen will report an error if conflicting options are set.

**Hook function signatures:**

Void hooks (no control flow — the hook fires as a side effect):
```cpp
void MyVoidHook() {
    // No return value, no control flow effect
}
```

Bool hooks (conditional control flow via `return_on_true`, `jump_address_on_true`, etc.):
```cpp
bool MyHook(PPCRegister& r3) {
    if (some_condition) {
        r3.u64 = 42;    // Modify register before jump
        return true;     // Triggers jump_address_on_true
    }
    return false;        // Continue normal execution
}
```

Hooks with `after_instruction = true` fire after the instruction at the hooked address executes. Useful for modifying values that were just written.

### ReXCRT

Map CRT function names to their guest addresses under the `[rexcrt]` table. The codegen emits `rexcrt_<Name>` symbols instead of generic `sub_XXXXXXXX` names, and the SDK runtime provides native host implementations that replace the original PPC code. See [[Memory]] for the ReXCRT allocator implementation details.

See [[Function Overrides]] for how to use `REX_HOOK`, `REX_HOOK_RAW`, and the stub family to override generated functions.

The SDK provides native implementations for the following function groups:

| Group | Functions |
|-------|-----------|
| Heap | `RtlAllocateHeap`, `RtlFreeHeap`, `RtlSizeHeap`, `RtlReAllocateHeap` |
| File I/O | `CreateFileA`, `ReadFile`, `WriteFile`, `SetFilePointer`, `GetFileSize`, `GetFileSizeEx`, `SetEndOfFile`, `FlushFileBuffers`, `DeleteFileA`, `CloseHandle`, `FindFirstFileA`, `FindNextFileA`, `FindClose`, `CreateDirectoryA`, `MoveFileA`, `SetFileAttributesA`, `GetFileAttributesA`, `GetFileAttributesExA`, `SetFilePointerEx`, `SetFileTime`, `CompareFileTime`, `CopyFileA`, `RemoveDirectoryA`, `GetFileType` |
| Memory | `memcpy`, `memmove`, `memset`, `memchr`, `XMemCpy`, `XMemSet`, `XMemSet128`, `memset_vmx`, `memcpy_s`, `memmove_s` |
| String | `strncmp`, `strncpy`, `strchr`, `strstr`, `strrchr`, `strtok`, `_stricmp`, `strcpy_s`, `lstrlenA`, `lstrcpyA`, `lstrcpynA`, `lstrcatA`, `lstrcmpiA` |

> [!IMPORTANT]
> The **heap** group is validated as all-or-nothing. If you specify any heap function, you must specify all four. When the heap group is present, the generated `_init.h` defines `REXCRT_HEAP 1`, which tells the runtime to initialize the ReXCRT allocator after loading the XEX image.

Any function name mapped in `[rexcrt]` that has a corresponding `REX_HOOK` (or the legacy `REXCRT_EXPORT` alias) in the SDK will be handled natively. Functions without SDK implementations will still be renamed to `rexcrt_<Name>` but must be implemented in your project code.

All addresses must be 4-byte aligned.
