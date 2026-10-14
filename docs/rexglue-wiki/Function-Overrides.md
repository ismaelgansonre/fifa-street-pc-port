Every recompiled function in the [[generated code|Generated Code Structure]] is emitted as a weak alias to a strong `__imp__`-prefixed implementation. You override a function by defining a strong symbol with the same name. The linker prefers your strong definition; the `__imp__` symbol always refers to the generated implementation, so you can wrap and call through to the original.

This page covers the override and import macros from `<rex/hook.h>`. See [[Mid-ASM Hooks]] for in-function injection at specific instruction addresses.

## REX_HOOK: typed override with auto-marshalling

Maps a recompiled function to a native C++ function. The SDK extracts arguments from PPC registers, calls your function, and writes the return value back to `r3` (or `f1` for floating point).

```cpp
#include <rex/hook.h>

uint32_t MyAdd(uint32_t a, uint32_t b) {
    return a + b;
}

// All calls to sub_82003A40 now go to MyAdd.
// r3 -> a, r4 -> b, return value -> r3.
REX_HOOK(sub_82003A40, MyAdd)
```

Argument marshalling uses standard PPC ABI register conventions. Use `mapped_u32` (and the other `mapped_*` types from `<rex/ppc.h>`) for guest pointer arguments that should be translated to host pointers automatically.

## REX_HOOK_RAW: raw override with direct context access

Use when you need the full PPC context, want to inspect or modify multiple registers, or want to call through to the original implementation. Declare the original via `REX_EXTERN`, then define your replacement.

```cpp
#include <rex/hook.h>

REX_EXTERN(__imp__sub_82003A40);

REX_HOOK_RAW(sub_82003A40) {
    // Pre-hook: modify state before the original runs
    ctx.r3.u64 = 42;

    // Call the original generated implementation
    __imp__sub_82003A40(ctx, base);

    // Post-hook: inspect or modify state after
}
```

`REX_HOOK_RAW(name)` expands to `extern "C" void name(PPCContext& ctx, uint8_t* base)` — the same signature every recompiled function uses. `ctx` and `base` are in scope inside the body.

## Stubs

Stubs replace a function with a logging no-op. Useful when you want a clean warning the first time something hits an unimplemented path instead of crashing.

```cpp
// Logs "FunctionName STUB" the first time it's called.
REX_STUB(sub_82003A40)

// Logs with a custom message.
REX_STUB_LOG(sub_82003A40, "TODO: implement audio mixing path")

// Logs and writes a return value into r3.
REX_STUB_RETURN(sub_82003A40, 0)
```

All three macros log at warning level under the `krnl` category.

## REX_EXPORT: hook + global registry

Like `REX_HOOK`, but additionally registers the function in the global PPC function registry so the kernel can resolve it by name (used for ordinal-based imports). Use this for kernel exports (xboxkrnl, xam) — not for game functions.

```cpp
uint32_t MyKernelImpl(uint32_t flags) { /* ... */ }

REX_EXPORT(NtSomeKernelCall, MyKernelImpl)
```

There are also `REX_EXPORT_STUB(name)` and `REX_EXPORT_STUB_RETURN(name, value)` variants matching the stub macros above.

## REX_IMPORT: typed callable for calling recompiled code

When host code needs to call a recompiled function with normal C++ argument types (rather than poking `ctx.r3`/`ctx.r4` manually), wrap it with `REX_IMPORT`:

```cpp
#include <rex/hook.h>

// Declare an external recompiled function with a typed signature.
REX_IMPORT(sub_82003A40, AddFunc, uint32_t(uint32_t, uint32_t));

// Call it. The macro creates an inline `AddFunc` callable that sets up
// registers, invokes the function, and returns the result.
uint32_t result = AddFunc(10, 20);
```

`REX_IMPORT(symbol, callable, signature)` takes three explicit arguments: the linker symbol, the variable name for the callable, and the function signature. The callable has three call shapes:

| Shape | Use when |
|--|--|
| `callable(ctx, base, args...)` | You already have a `PPCContext&` and `uint8_t*` (e.g. inside a `REX_HOOK_RAW`). |
| `callable(frame, base, args...)` | You have a `rex::CallFrame` (isolated context for side calls). |
| `callable(args...)` | No context in scope. Pulls the current thread's context, allocates a 0x70-byte guest stack frame, and runs in isolation. |

The third form is the one to use from non-hook host code (event handlers, UI callbacks, background threads).

### CallFrame: isolated calling context

When you call a recompiled function from inside a hook and don't want the callee to clobber your register state, wrap the call in a `rex::CallFrame`:

```cpp
REX_HOOK_RAW(sub_82003A40) {
    rex::CallFrame frame{ctx};
    // Calls run in `frame.ctx`. Only r1, r13, and fpscr are copied from `ctx`;
    // the callee's writes to other registers don't leak back out.
    SomeOtherImport(frame, base, 1, 2);

    // ctx is unchanged here (except fpscr, which propagates back on destruction).
}
```

## Compatibility aliases

The macros below still work for older code. New code should use the canonical names on the left.

| Canonical | Legacy alias |
|--|--|
| `REX_HOOK` | `PPC_HOOK` |
| `REX_HOOK_RAW` (raw form) | `PPC_FUNC` |
| `REX_FUNC` | `PPC_FUNC` |
| `REX_EXTERN` | `PPC_EXTERN_FUNC`, `PPC_EXTERN_IMPORT`, `PPC_FUNC_IMPL` |
| `REX_WEAK_FUNC` | `PPC_WEAK_FUNC` |
| `REX_STUB` | `PPC_STUB` |
| `REX_EXPORT` | `XBOXKRNL_EXPORT`, `XAM_EXPORT`, `REXCRT_EXPORT` |
