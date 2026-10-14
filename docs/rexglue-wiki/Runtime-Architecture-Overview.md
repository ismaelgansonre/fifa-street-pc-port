The `Runtime` class (`rex::Runtime`) is the central owner of all subsystems in a recompiled application. It initializes them in dependency order, wires them together, and provides typed accessors to each.

The subsystem hierarchy, kernel object model, memory layout, and threading primitives originate from [Xenia](https://xenia.jp), reworked to remove JIT dependencies and support static linking of pre-compiled game code. See [[Home]] for the full comparison of execution models.

## Subsystem Diagram

```
Runtime
+-- Memory              - 4 GB guest virtual address space + physical memory
+-- ExportResolver      - Ordinal-to-name mapping + variable export registry
+-- FunctionDispatcher  - Guest-to-host function dispatch table
+-- VirtualFileSystem   - Guest path to host path mapping
+-- KernelState         - Xbox 360 kernel objects (threads, events, modules, ...)
+-- IGraphicsSystem*    - GPU backend (injected, in-flux)
+-- IAudioSystem*       - Audio backend (injected, in-flux)
+-- IInputSystem*       - Input backend (injected, in-flux)
```

Subsystems marked with `*` are injected via `RuntimeConfig` and are not owned by the SDK core library. Graphics, audio, and input backends are provided by the caller (typically [[ReXApp]]), keeping the runtime decoupled from concrete implementations.

## Initialization Sequence

`Runtime::Setup()` brings subsystems up in strict dependency order. Every later subsystem may allocate from earlier ones.

| Step | Action | Notes |
|------|--------|-------|
| 1 | Initialize SEH exception support | Platform-specific hardware exception handling |
| 2 | Initialize clock | Guest tick frequency: 50 MHz |
| 3 | Enable threading affinity | Host thread pinning configuration |
| 4 | Create [[Memory]] | Must be first; all other subsystems allocate from it |
| 5 | Create ExportResolver | Ordinal registry, populated later by kernel modules |
| 6 | Create FunctionDispatcher | Receives Memory + ExportResolver pointers |
| 7 | Create [[Virtual File System]] | Empty device list |
| 8 | Create [[Kernel State & Objects]] | Sets the global singleton; owns object table, processes |
| 9 | Initialize Input system | From injected `input_factory` |
| 10 | Load kernel modules | `RuntimeConfig::kernel_init` callback registers xboxkrnl/xam exports |
| 11 | Initialize Audio system | From injected `audio_factory`; receives FunctionDispatcher pointer |
| 12 | Setup VFS mounts | `game:`, `d:`, `update:`, NullDevice for cache partitions |
| 13 | Initialize Graphics system | Skipped in `tool_mode` |
| 14 | Register recompiled function mappings | Populates function dispatch table from `PPCFuncMapping` array (see [[Generated Code Structure]]) |

The extended `Setup()` overload additionally calls `FunctionDispatcher::InitializeFunctionTable()` to set up the guest-address-to-host-function dispatch table, then iterates the provided `PPCFuncMapping` array to register every recompiled function. After that, it sets `Runtime::instance_` for global access by recompiled code.

Shutdown runs in reverse order.

## Guest Code Execution

All game code is pre-compiled to native C++ and linked at build time. There is no JIT, no code cache, and no instruction decoding at runtime. `FunctionDispatcher` is a thin dispatch layer that maps guest addresses to host function pointers.

Recompiled functions are native C++ functions with a standardized signature:

```cpp
void sub_XXXXXXXX(PPCContext& ctx, uint8_t* membase);
```

- `PPCContext` carries the full PPC register file (GPRs, FPRs, CR, LR, CTR, XER, vector registers).
- `membase` is the host base pointer for the 4 GB guest virtual address space.

Execution flow:

1. `KernelState::LaunchModule()` creates an `XThread` for the executable module's entry point.
2. The thread calls `FunctionDispatcher::Execute()`, which looks up the host function pointer in the dispatch table.
3. The looked-up function is called directly as a native C++ function call.
4. Before calling the entry point, the runtime sets up the guest stack: `r1` is adjusted by 64 + 112 bytes of padding, matching the Xbox 360 PPC ABI stack frame convention.
5. Indirect calls within recompiled code use `PPC_CALL_INDIRECT_FUNC` / `PPC_LOOKUP_FUNC` macros that index the same dispatch table at runtime.

## FunctionDispatcher

`FunctionDispatcher` (`rex::runtime::FunctionDispatcher`) maps guest PPC addresses to host C++ function pointers. It is the runtime's only path from a guest address to executable code.

The function table is populated once during `Runtime::Setup()` from the `PPCFuncMappings[]` array in [[Generated Code Structure]]:

- `InitializeFunctionTable(code_base, code_size, image_base, image_size)` allocates the table in guest memory.
- `SetFunction(guest_addr, host_func)` registers a mapping.
- `GetFunction(guest_addr)` retrieves a host function pointer.
- `Execute(thread_state, address, args[], arg_count)` invokes a guest function from host code, setting up the stack frame and link register.
- `AllocateThunk(func)` returns a guest address that calls a host function, used for dynamically resolved imports (e.g. `XexGetProcedureAddress`).

See [[Memory]] for the table's placement in the guest address space.

## ExportResolver

`ExportResolver` (`rex::runtime::ExportResolver`) holds kernel module export metadata: ordinal-to-name mapping and variable export bindings.

- **Ordinal-to-name lookup**: maps kernel module ordinals to their export names, used during XEX import resolution and diagnostic logging.
- **Variable export management**: `SetVariableMapping(module_name, ordinal, value)` binds variable exports to guest memory addresses. This is how kernel globals that game code reads directly (e.g., `KeTimeStampBundle`) are exposed.
- **Export table registry**: each kernel module registers its export table via `RegisterTable(module_name, exports)`. The resolver maintains per-module tables indexed by ordinal and a name-sorted view for lookup.

Shim dispatch is no longer routed through the resolver - kernel imports are linked statically as `REX_EXPORT` / `REX_HOOK` definitions.

## Global Access

The Runtime is accessible as a singleton via `Runtime::instance()`. Recompiled code reaches subsystems through `KernelState`, which is the preferred entry point: prefer `kernel_state()->memory()` over `Runtime::instance()->memory()` in new code.
