Mid-ASM hooks inject calls to native C++ functions at specific instruction addresses inside a recompiled function, without overriding the whole function. They're useful for inspecting state at a specific PC, patching a value mid-execution, or redirecting control flow on a condition.

For overriding entire functions, see [[Function Overrides]].

## TOML Configuration

Hooks are declared in the codegen [[TOML config|rexglue CLI Configuration File]] under `[[midasm_hook]]`. The codegen emits the call site at the matching instruction in the generated source.

```toml
[[midasm_hook]]
address = 0x82000000
name = "MyHook"
registers = ["r3", "r4"]
after_instruction = false
jump_address_on_true = 0x82000004
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `address` | Yes | — | Address of the PPC instruction to hook. |
| `name` | Yes | — | Name of the C++ hook function to call. |
| `registers` | No | `[]` | Registers passed to the hook as `PPCRegister&` arguments. |
| `after_instruction` | No | `false` | If `true`, hook fires after the instruction; if `false`, before. |
| `return` | No | `false` | Unconditionally return from the recompiled function. |
| `jump_address` | No | `0` | Unconditionally jump to this address. |
| `return_on_true` | No | `false` | Return if the hook returns `true`. |
| `return_on_false` | No | `false` | Return if the hook returns `false`. |
| `jump_address_on_true` | No | `0` | Jump if the hook returns `true`. |
| `jump_address_on_false` | No | `0` | Jump if the hook returns `false`. |

> [!WARNING]
> You cannot combine `return` with `jump_address`, or mix unconditional and conditional control flow options. The codegen reports an error if conflicting options are set.

## Hook Function Signatures

### Void hooks

Side-effect only — the hook fires and execution continues.

```cpp
void MyVoidHook() {
    // Inspect global state, log, etc.
}
```

### Bool hooks

Drive conditional control flow via `return_on_true` / `jump_address_on_true` etc. The hook receives the registers listed in `registers` as `PPCRegister&`, so you can read or modify them before the jump or return.

```cpp
bool MyHook(PPCRegister& r3, PPCRegister& r4) {
    if (r3.u32 == 0) {
        r4.u64 = 42;     // Patch r4 before redirecting
        return true;     // Triggers jump_address_on_true
    }
    return false;        // Continue normal execution
}
```

## Timing: before vs after

`after_instruction = false` (default) fires the hook *before* the instruction at `address` executes. This is the right choice when you want to observe or modify inputs.

`after_instruction = true` fires *after* the instruction executes. Use this when you want to observe or modify the result the instruction just produced (e.g. patching a load).
