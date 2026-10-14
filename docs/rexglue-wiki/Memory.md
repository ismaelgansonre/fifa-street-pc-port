The memory subsystem provides a 4 GB guest virtual address space mapped into host memory, with heap management matching Xbox 360 memory semantics. See [[Runtime Architecture Overview]] for where Memory fits in the subsystem initialization sequence.

## Virtual Address Space Layout

The entire 4 GB guest address space is backed by a memory-mapped file placed at a stable fixed address in the host address space (typically `0x100000000`). This avoids TLB emulation and enables direct pointer arithmetic for guest-to-host translation.

| Start | End | Size | Page Size | Heap | Purpose |
|-------|-----|------|-----------|------|---------|
| `0x00000000` | `0x3FFFFFFF` | 1024 MB | 4 KB | `v00000000` | Virtual 4K pages (includes GPU-visible physical mapping) |
| `0x40000000` | `0x7FFFFFFF` | 1024 MB | 64 KB | `v40000000` | Virtual 64K pages |
| `0x80000000` | `0x8BFFFFFF` | 192 MB | 64 KB | `v80000000` | XEX image (code + data sections) |
| `0x8C000000` | `0x8FFFFFFF` | 64 MB | 64 KB | `v80000000` | XEX encrypted region |
| `0x90000000` | `0x9FFFFFFF` | 256 MB | 4 KB | `v90000000` | XEX 4K pages |
| `0xA0000000` | `0xBFFFFFFF` | 512 MB | 64 KB | `PhysicalHeap` | Physical 64K pages |
| `0xC0000000` | `0xDFFFFFFF` | 512 MB | 16 MB | `PhysicalHeap` | Physical 16M pages |
| `0xE0000000` | `0xFFFFFFFF` | 512 MB | 4 KB | `PhysicalHeap` | Physical 4K pages |

Physical memory (512 MB) is stored at host offset `0x200000000` and is shared with the GPU subsystem. The three physical heap ranges (`0xA0000000`, `0xC0000000`, `0xE0000000`) are different views of the same physical backing with different page granularities.

## Heap Types

### VirtualHeap

Page-based allocation for guest virtual address ranges. Each VirtualHeap manages a contiguous region of the address space with its own page table.

Key operations:

| Method | Description |
|--------|-------------|
| `Alloc(size, alignment, type, protect, top_down)` | Allocate contiguous pages |
| `AllocFixed(base, size, alignment, type, protect)` | Allocate at a specific address |
| `AllocRange(low, high, size, ...)` | Allocate within an address range |
| `Decommit(address, size)` | Release backing memory, keep reservation |
| `Release(address)` | Decommit and unreserve pages |
| `Protect(address, size, protect)` | Change page protection flags |
| `QueryRegionInfo(address, info)` | Query allocation state of a region |

Protection flags: `kMemoryProtectRead`, `kMemoryProtectWrite`, `kMemoryProtectNoCache`, `kMemoryProtectWriteCombine`.

### PhysicalHeap

Maps physical pages, backed by a parent `VirtualHeap` in the guest virtual address space. Used for GPU-visible and audio-accessible memory. PhysicalHeap supports invalidation callbacks for cache coherency: when guest code writes to a watched physical page, registered callbacks are triggered so subsystems (e.g., GPU texture cache) can invalidate stale data.

### System Heap

Allocated from the top of virtual heaps via `Memory::SystemHeapAlloc(size, alignment, flags)`. Keeps [[kernel|Kernel State & Objects]] structures (object table entries, process blocks, TLS data) separate from game-visible memory while remaining accessible through normal guest virtual addresses.

`SystemHeapFree(address)` releases system heap memory.

## Guest-to-Host Translation

```cpp
// Virtual address translation
template <typename T>
T Memory::TranslateVirtual(uint32_t guest_address) const {
  uint8_t* host = virtual_membase_ + guest_address;
  auto heap = LookupHeap(guest_address);
  if (heap) host += heap->host_address_offset();
  return reinterpret_cast<T>(host);
}

// Physical address translation
template <typename T>
T Memory::TranslatePhysical(uint32_t guest_address) const {
  return reinterpret_cast<T>(physical_membase_ + (guest_address & 0x1FFFFFFF));
}
```

The `host_address_offset()` on each heap accounts for the gap between the logical guest address and the actual host mapping position. For most virtual heaps this is zero; for physical heaps it maps the `0xA0000000+` guest range onto the `0x200000000` host physical backing.

`HostToGuestVirtual(host_ptr)` performs the reverse translation.

All data at translated addresses is **big-endian**, matching the Xbox 360's PowerPC byte order. Use `rex::be<T>` wrappers for typed access.

### Windows Host Granularity

Windows enforces a 64 KB allocation granularity for memory-mapped file views (`MapViewOfFile`), while Linux allows 4 KB alignment. When the SDK maps the guest address space as file-backed views, each view's file offset is rounded down to the nearest 64 KB boundary on Windows. This is transparent for most heaps because their file offsets are already 64 KB-aligned.

The exception is the `0xE0000000` physical heap. Its backing data starts at file offset `0x100001000` (the physical memory region at `0x100000000` plus a 4 KB page offset). On Windows, the 64 KB granularity mask rounds this down to `0x100000000`, losing the `0x1000` offset. The heap compensates by setting a `host_address_offset` of `0x1000`:

```cpp
// PhysicalHeap::Initialize
if (heap_base >= 0xE0000000 && allocation_granularity() > 0x1000) {
  host_address_offset = 0x1000;  // compensate for granularity masking
}
```

This offset is applied in two places:

- **`TranslateVirtual`**: adds `heap->host_address_offset()` to the computed host pointer (shown above).
- **Generated code**: the `PPC_PHYS_HOST_OFFSET(addr)` macro returns `0x1000` when the address falls in the `0xE0000000` range on Windows, and `0` on Linux or for other ranges. All `PPC_LOAD_*` / `PPC_STORE_*` macros in the physical 4K region incorporate this offset.

`HostToGuestVirtual` performs the reverse: if the host address falls within the `0xE0000000` range, it subtracts the offset before computing the guest address.

| Heap | File Offset | Granularity Issue | `host_address_offset` |
|------|-------------|-------------------|-----------------------|
| `v00000000` | `0x000000000` | None (aligned) | `0` |
| `v40000000` | `0x040000000` | None (aligned) | `0` |
| `v80000000` | `0x080000000` | None (aligned) | `0` |
| `v90000000` | `0x080000000` | None (aligned) | `0` |
| `PhysicalHeap` 64K | `0x100000000` | None (aligned) | `0` |
| `PhysicalHeap` 16M | `0x100000000` | None (aligned) | `0` |
| `PhysicalHeap` 4K | `0x100001000` | **Masked to `0x100000000` on Windows** | **`0x1000`** |

> [!NOTE]
> On Linux, allocation granularity is 4 KB, so the `0x1000` file offset maps correctly and no compensation is needed. The `host_address_offset` remains `0` for all heaps.

## Function Table

The recompiled function dispatch table is stored in guest memory immediately after the XEX image. This is the table that [[FunctionDispatcher|Runtime Architecture Overview]] and [[thread dispatch|Kernel State & Objects]] use to resolve guest addresses to native C++ functions.

- **Location:** `IMAGE_BASE + IMAGE_SIZE`
- **Index formula:** `(guest_addr - CODE_BASE) * 2`. Each 4-byte-aligned guest address maps to an 8-byte host function pointer slot.

```cpp
// Register a recompiled function
memory->SetFunction(guest_addr, host_func_ptr);

// Look up at runtime (used by PPC_LOOKUP_FUNC / PPC_CALL_INDIRECT_FUNC)
PPCFunc* func = memory->GetFunction(guest_addr);
```

The table is populated during [[Runtime::Setup()|Runtime Architecture Overview]] from the `PPCFuncMappings[]` array in [[Generated Code Structure]].

Thunk allocation (`FunctionDispatcher::AllocateThunk`) provides slots for dynamically resolved functions (e.g., addresses returned by `XexGetProcedureAddress` that need host-callable wrappers).

## ReXCRT Allocator

For games that use standard CRT heap functions (malloc/free/realloc via `RtlAllocateHeap`/`RtlFreeHeap`), the SDK provides a replacement allocator that operates directly in guest memory. Configure CRT function mappings in the `[rexcrt]` section of the [[rexglue CLI Configuration File]].

**Design:**
- Based on [o1heap](https://github.com/pavel-kirienko/o1heap): O(1) worst-case allocation and deallocation.
- **Multi-segment:** if the initial segment runs out of space, additional segments are allocated from the guest virtual heap on demand, avoiding hard OOM on large allocations.
- Thread-safe via `std::mutex`.

**Configuration:**
- `rexcrt_heap_size_mb` [[CVar|CVar System]] controls the initial segment size (default varies by project).
- `rexcrt_heap_enable` CVar can disable the heap entirely.
- Initialization happens in [[ReXApp::OnInitialize()|ReXApp]] after `LoadXexImage`, so the heap region does not conflict with the XEX image mapping.

**API** (`rex::kernel::crt::ReXHeap`):

| Method | Description |
|--------|-------------|
| `Alloc(size, zero)` | Allocate guest memory, optionally zeroed |
| `Free(guest_addr)` | Free a previous allocation |
| `Realloc(guest_addr, new_size, zero_new)` | Resize allocation |
| `Size(guest_addr)` | Query allocation size |
| `InHeap(guest_addr)` | Check if address belongs to the rexcrt heap |
| `GetDiagnostics()` | Capacity, allocated, peak, OOM count |

The heap is activated by codegen when the `[rexcrt]` section in the [[rexglue CLI Configuration File]] maps CRT functions. Original heap implementations in the game binary are replaced with calls to this allocator.
