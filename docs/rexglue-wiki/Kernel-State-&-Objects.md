`KernelState` implements the Xbox 360 kernel's object model, process structure, and threading semantics. It manages all kernel objects and provides the syscall-level API that recompiled game code depends on.

## Code vs Data Loading

The XEX binary is loaded at runtime, but only for its **data layout**: initialized globals, heap structures, TLS templates, and import tables. Code execution is handled entirely by the pre-built function table that maps guest addresses to native C++ function pointers. The kernel never sees PPC instructions; it provides the runtime environment that pre-compiled native code expects: guest memory layout, thread scheduling, object handles, and syscall implementations.

Practical consequences:

- **Function dispatch** is a static table populated once at startup, not a JIT cache lookup.
- **Module loading** maps XEX data sections; code sections are already compiled into the host binary.
- **Kernel shims** are linked statically. The ExportResolver is just an ordinal registry.
- **Unimplemented imports** are reported at codegen time as unresolved calls, not at runtime when hit.

See [[Runtime Architecture Overview]] for the full initialization sequence, [[Memory]] for the function table layout, and [[Home]] for the broader Xenia comparison.

## KernelState Overview

`KernelState` (`rex::system::KernelState`) is a global singleton set at construction and accessed via `kernel_state()`. It is created during the [[Runtime::Setup()|Runtime Architecture Overview]] initialization sequence and receives a back-pointer to the `Runtime`.

**Owns:**
- Object table (handles to all kernel objects)
- Three `X_KPROCESS` structures (idle, system, title)
- Thread registry
- DPC system (deferred procedure call dispatch)
- Notification listeners
- App manager, content manager, user profile

**Accessors:**

| Accessor | Returns |
|----------|---------|
| `memory()` | `Memory*` (see [[Memory]]) |
| `function_dispatcher()` | `FunctionDispatcher*` (see [[Runtime Architecture Overview]]) |
| `file_system()` | `VirtualFileSystem*` (see [[Virtual File System]]) |
| `object_table()` | `ObjectTable*`: handle-to-object mapping |
| `app_manager()` | `AppManager*`: XAM application management |
| `content_manager()` | `ContentManager*`: content/DLC enumeration |
| `user_profile()` | `UserProfile*`: signed-in user data |

## Process Model

The kernel maintains three `X_KPROCESS` structures, matching the Xbox 360's process architecture:

| Process | Type Constant | Purpose | Notes |
|---------|---------------|---------|-------|
| Idle | `X_PROCTYPE_IDLE` (0) | System background | Quantum: 127 |
| System | `X_PROCTYPE_USER` (1) | Kernel modules | Default TLS: 32 slots |
| Title | `X_PROCTYPE_SYSTEM` (2) | User-loaded game modules | TLS re-initialized from XEX header |

Each `X_KPROCESS` contains:

- `thread_list_spinlock` + `thread_list`: linked list of threads in this process
- `quantum`: scheduling time quantum
- `tls_static_data_address`, `tls_data_size`, `tls_raw_data_size`: thread-local storage layout
- `tls_slot_bitmap[8]`: 256 max TLS slots, tracked as a bit array
- `process_type`: identifies which process this is
- `is_terminating`: set during title termination

All three processes are allocated in guest memory as part of `KernelGuestGlobals`, which also holds the kernel's object type descriptors and global spinlocks.

## Kernel Object Model

All kernel objects derive from `XObject` with a type tag and are tracked in the `ObjectTable`. Handles are `uint32_t` values with a base offset of `0xF8000000`. Objects are reference-counted (retain/release semantics via `object_ref<T>`).

### Object Types

| Object | Class | Description |
|--------|-------|-------------|
| Thread | `XThread` | Host thread wrapper carrying a `PPCContext`. Maintains a guest `X_KTHREAD` structure in kernel memory. Supports waiting on events, mutants, and semaphores. |
| Event | `XEvent` | Manual-reset or auto-reset event. Signal state stored in the dispatch header. |
| Semaphore | `XSemaphore` | Counting semaphore with limit count and current count. |
| Mutant | `XMutant` | Recursive mutex with owner thread tracking. Maps to Xbox 360 `KMUTANT`. |
| Module | `XModule` | Abstract base. `KernelModule` for built-in kernel exports, `UserModule` for loaded XEX/ELF images. |
| File | `XFile` | [[Virtual File System]] file reference with synchronous and async I/O, including completion port support. |

Additional object types defined in `KernelGuestGlobals` (used for type checking but not directly instantiated as `XObject` subclasses): Timer, IoCompletion, IoDevice, ObDirectory, ObSymbolicLink.

### Dispatch Header

Waitable objects (threads, events, semaphores, mutants) share a common `X_DISPATCH_HEADER` at the start of their guest-memory structure:

- Object type identifier
- Signal state (signaled / not signaled)
- Wait list head (linked list of waiting threads)

This matches the Xbox 360 kernel's `DISPATCHER_HEADER` layout and enables the multi-object wait implementation (`WaitForMultipleObjects` semantics).

## Thread Management

| Function | Purpose |
|----------|---------|
| `RegisterThread(XThread*)` | Add thread to the kernel's thread registry |
| `UnregisterThread(XThread*)` | Remove thread from registry |
| `GetThreadByID(uint32_t)` | Look up thread by its guest thread ID |
| `OnThreadExecute(XThread*)` | Lifecycle hook called when thread begins execution |
| `OnThreadExit(XThread*)` | Lifecycle hook called when thread exits |

Each `XThread` owns a `PPCContext` that carries the full PPC register state. When a thread executes, the kernel looks up the target guest address in the function table, retrieves the corresponding native C++ function pointer, and calls it directly, passing the `PPCContext` by reference and the [[guest memory|Memory]] base pointer. There is no interpretation or JIT compilation; every function call is a direct native invocation of statically-compiled code.

TLS slot allocation is per-process: `AllocateTLS()` / `FreeTLS()` manage the process's `tls_slot_bitmap`, protected by the kernel's TLS spinlock.

## Function Dispatch

The function table maps guest PPC addresses to host C++ function pointers. It is managed by `FunctionDispatcher` (see [[Runtime Architecture Overview]]) and populated **once** during `Runtime::Setup()` from the `PPCFuncMappings[]` array in [[Generated Code Structure]] generated by `rexglue codegen`.

Each entry stores a `PPCFunc*`, a pointer to a native C++ function with the signature:

```cpp
void(PPCContext& ctx, uint8_t* base)
```

The table exists in two forms for different access patterns:

| Form | Storage | Used By |
|------|---------|---------|
| C++ `unordered_map` | `FunctionDispatcher::function_table_` | `FunctionDispatcher::Execute()`, `GetFunction()` |
| Guest memory array | `image_base + image_size` | Indirect calls from recompiled code (`PPC_CALL_INDIRECT_FUNC`) |

The guest memory table stores host function pointers indexed by `(guest_addr - code_base) * 2`, enabling recompiled code to resolve indirect calls (vtable dispatch, function pointers) without leaving native execution. See [[Memory]] for the table's placement in the guest address space.

`FunctionDispatcher::Execute(thread_state, address, args, arg_count)` is the primary host-driven dispatch entry point: it looks up the function, sets up the stack frame and link register, and calls the native function directly.

## Module Loading

In ReXGlue, "module loading" sets up the guest memory environment. It does not load code for execution. The recompiled C++ functions are already linked into the host binary at build time.

The loading pipeline:

1. **`LoadUserModule(path)`**: Parses the XEX binary and maps its **data sections** into [[guest memory|Memory]] (initialized globals, heap structures, embedded resources). Resolves import ordinals against registered kernel modules via [[ExportResolver|Runtime Architecture Overview]]. The XEX's code sections are loaded into guest memory for data-level compatibility (read-only), but execution always goes through the pre-built function table. The PPC instructions are never interpreted.

2. **`SetExecutableModule(module)`**: Designates the main game module. Updates kernel globals with the module's stack size and TLS layout from the XEX header. Sets up `XexExecutableModuleHandle` and `ExLoadedImageName` for kernel export variables.

3. **`LaunchModule(module)`**: Creates an `XThread` targeting the module's XEX entry point address. The entry point is resolved through the function table to its pre-compiled native C++ function, and the thread begins executing it directly.

Kernel modules (`xboxkrnl.exe`, `xam.xex`) are loaded via `LoadKernelModule<T>()`, which constructs the module and registers its export table with the `ExportResolver`. These provide the syscall implementations that recompiled code calls into.

## DPC System

Deferred Procedure Calls allow work to be queued for execution at `DISPATCH` IRQL level:

- `dpc_list_`: a `NativeList` of pending DPCs, guarded by the global critical region.
- A background `dispatch_thread_` (an `XHostThread`) processes the list.
- The thread sleeps on `dispatch_cond_` and wakes when new DPCs are queued.
- DPC execution nominally raises the IRQL to `DPC` level for the duration of the callback. IRQL is currently modeled but not enforced - there is no preemption boundary between IRQL levels in the host runtime.

The DPC system also handles `CompleteOverlapped` / `CompleteOverlappedDeferred` for async I/O completion, routing results back through the dispatch queue. See [[Virtual File System]] for how file I/O uses this path.

