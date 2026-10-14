The `rexglue codegen` command converts an Xbox 360 XEX binary into portable C++23 source code via a two-phase pipeline:
1. **Analysis**: function discovery and control flow reconstruction
2. **Recompilation**: PPC instruction translation to C++

See [[rexglue CLI Configuration File]] for all TOML options that control this pipeline, and [[Generated Code Structure]] for the output format.

## Pipeline Architecture

The pipeline is orchestrated by `Analyze()` in `analyze.cpp`, which runs seven sequential stages to build a complete `FunctionGraph`, followed by `Recompile()` which walks the sealed graph and emits C++.

```
XEX Binary
  |
  v
Phase 1: Analysis (analyze.cpp)
  1. Register    - import/export resolution, helpers, PDATA, config
  2. Scan        - segment binary into code/data regions
  3. Discover    - iterative block discovery (includes VTable scan)
  4. GapFill     - claim orphaned code regions
  5. Discover    - block discovery for gap-filled functions
  6. Merge       - resolve jumps, seal function boundaries
  7. Validate    - verify all call targets are resolvable
  |
  v
Phase 2: Recompilation (recompiler.cpp)
  - Walk sealed FunctionGraph
  - Dispatch each PPC instruction to a builder function
  - Emit C++ source files
  |
  v
Generated C++ (see [[Generated Code Structure]])
```

## Phase 1: Analysis

### 1. Register

`registerEntryPoints()` populates the `FunctionGraph` with initial entry points from multiple sources:

- **Import/export resolution**: Resolves import thunks against the module's import table via the ExportResolver (see [[Runtime Architecture Overview]]). Each resolved import becomes a `FunctionNode` with `IMPORT` authority. Unresolved imports log a warning but do not block analysis.
- **Helper detection**: Runs `SigScanner::helperSignatures()` to pattern-match known compiler helpers:
  - `__savegprlr_14` through `__savegprlr_31`
  - `__restgprlr_14` through `__restgprlr_31`
  - `__savefpr_14` through `__savefpr_31`
  - `__restfpr_14` through `__restfpr_31`
  - `__savevmx_64` through `__savevmx_127`
  - `__restvmx_64` through `__restvmx_127`
- **PDATA parsing**: Reads the `.pdata` exception table (`IMAGE_CE_RUNTIME_FUNCTION` entries, 8 bytes each) to extract function start addresses and sizes. Functions with the `ExceptionFlag` bit set trigger SEH scope table parsing and C++ EH FuncInfo parsing (magic `0x19930522`), which discovers handler functions and adds them to the graph.
- **User config**: Loads manual `[functions]` entries from the [[TOML config|rexglue CLI Configuration File]]. These get `CONFIG` authority with exact boundaries that cannot be overridden.
- **Entry point**: The XEX entry point is always registered as an immutable entry.

### 2. Scan

`scanBinary()` segments each executable section into code and data regions by scanning for null-delimited boundaries. The result is a set of `CodeRegion` objects that constrain where the Discover phase will look for instructions.

Regions of consecutive null dwords (`0x00000000`) or padding are classified as data. The `data_region_threshold` [[config option|rexglue CLI Configuration File]] controls how many consecutive null dwords trigger a data region split.

### 3. Discover

`discoverAllFunctions()` is the core of function discovery. It runs iteratively to a fixed point, since discovering one function's blocks often reveals `bl` (call) targets that are new function entry points during the first few cycles.

For each registered-but-undiscovered function, `discoverBlocks()` performs:

1. **Linear sweep** from the entry point through the containing `CodeRegion`
2. **Block construction**: instructions are grouped into basic blocks, terminated by `blr` (return), `bctr` (indirect branch), unconditional `b` (branch), or null padding
3. **Branch following**: conditional branches (`beq`, `bne`, `blt`, etc.) create two paths (the branch target and the fall-through), both added to the work queue
4. **Call recording**: `bl` instructions are recorded as unresolved branches for resolution during Merge
5. **Jump table detection**: when `bctr` is encountered, the scanner backward-scans for the `mtctr`/load pattern and attempts to identify jump table entries (absolute `lwzx`, byte-offset `lbzx`, half-word `lhzx`, or computed `rlwinm`+`lbzx`). See [[switch_tables|rexglue CLI Configuration File]] for manual overrides when auto-detection fails.

The discover phase also runs a **VTable scan** using `VTableScanner`. This traverses RTTI structures (MSVC-style `RTTICompleteObjectLocator` at vtable[-1]) to discover vtable slot addresses, which are registered as functions with `VTABLE` authority.

The iteration continues until no new function entry points are found.

### 4. GapFill

`gapFillCodeRegions()` examines code regions that are not covered by any discovered function. Uncovered sub-regions are split at natural boundaries (null padding, PDATA markers, exception data patterns) and registered as `GAP_FILL` authority functions.

GAP_FILL functions are speculative: they represent code that was not reachable from any known entry point but occupies executable memory. During the subsequent Merge phase, GAP_FILL functions can be absorbed into adjacent higher-authority functions via vacancy-based expansion.

### 5. Discover (Gap-Filled)

A second discovery pass runs block discovery for the newly registered gap-filled functions. After this pass, absorbed GAP_FILL functions (those whose address range was claimed by a neighboring function's expansion) are cleaned up.

### 6. Merge

`mergeAndSeal()` resolves all unresolved jumps and seals function boundaries:

1. **Jump resolution**: For each function with unresolved branches, checks whether the target is (a) a known function entry point, (b) an import thunk, or (c) an internal label within the same function. Resolved jumps become `CallEdge` entries.
2. **Vacancy expansion**: Functions can expand into adjacent vacant regions (regions with no null-dword boundary, no chunk claims, and no protected function overlap).
3. **Sealing**: Functions transition from `kDiscovered` to `kSealed` state once all branches are resolved and blocks are finalized. The `FunctionAnalysis` is computed (CSR requirements, special register usage).

### 7. Validate

`validateGraph()` iterates all sealed functions and verifies that every `bl` and `b` target resolves to either a function in the graph or a known import. Unresolved calls are reported as `AnalysisErrors::Category::UnresolvedCall`. See [[Unresolved Calls|Generated Code Structure]] for how these appear in the output.

> [!NOTE]
> Validation errors do not prevent code generation if `--force` is passed. The generated code will contain error comments at unresolved call sites.

## Function Discovery Mechanisms

The pipeline discovers functions through five complementary mechanisms:

### Signature Scanning

`SigScanner` performs dword-based pattern matching against executable sections. Each `Signature` has a pattern (instruction words), a mask (which bits must match), and an entry offset. The built-in `helperSignatures()` set targets save/restore helper functions generated by the Xbox 360 MSVC compiler:

```cpp
struct Signature {
  std::string name;
  std::vector<uint32_t> pattern;  // Instruction words to match
  std::vector<uint32_t> mask;     // 0xFFFFFFFF = exact match
  size_t entryOffset = 0;         // Offset from pattern start to entry point
  std::optional<size_t> size;     // Known size, or nullopt
};
```

### VTable Scanning

`VTableScanner` traverses Xbox 360 MSVC-style RTTI structures in `.rdata`:

1. Find all `RTTICompleteObjectLocator` structures (signature = 0 for 32-bit)
2. Locate the vtable that references each COL (COL address appears at vtable[-1])
3. Read vtable slots until a non-executable address is encountered
4. Register each slot address as a function with `VTABLE` authority

### Block-Based Discovery

The primary discovery mechanism. From each known entry point, `discoverBlocks()` performs a worklist-driven linear sweep:

- Instructions are decoded and grouped into basic blocks
- Branch targets create new work items
- `bl` targets are recorded as potential new function entries
- The outer loop re-discovers when new entries appear

### Exception Handler Discovery

During PDATA parsing, functions with the `ExceptionFlag` bit trigger exception table analysis:

- **SEH**: Scope tables are parsed to extract `__finally` and `__except` handler function addresses
- **C++ EH**: `FuncInfo` structures (identified by magic `0x19930522`) yield unwind map entries, try block handlers, and catch handler addresses

All discovered handler functions are added to the graph.

### User-Specified Functions

Manual `[functions]` entries in the [[TOML config|rexglue CLI Configuration File]] provide exact function boundaries with `CONFIG` authority. These cannot be overridden or absorbed by any other mechanism.

## PPC to C++ Translation

### Dispatch Architecture

Each PPC instruction maps to a **builder function** via a static dispatch table in `instruction_dispatch.cpp`. The table is an `unordered_map<int, Builder>` where `Builder` is a function pointer `bool (*)(BuilderContext&)`.

The dispatch table covers approximately 350 entries across these categories:

| Category | Examples |
|--|--|
| Arithmetic | `add`, `addi`, `subf`, `mullw`, `divw` |
| Logical | `and`, `or`, `xor`, `rlwinm`, `slw`, `sraw` |
| Comparison | `cmpw`, `cmplwi`, `fcmpu` |
| Control Flow | `b`, `bl`, `blr`, `bctr`, `beq`, `bne`, `bdnz` |
| Floating Point | `fadd`, `fmul`, `fmadd`, `fcfid`, `fsel` |
| Memory (Load) | `lbz`, `lhz`, `lwz`, `ld`, `lfs`, `lfd`, `lvx` |
| Memory (Store) | `stb`, `sth`, `stw`, `std`, `stfs`, `stfd`, `stvx` |
| System | `nop`, `sync`, `eieio`, `mflr`, `mtctr`, `tw`, `dcbz` |
| Vector (FP) | `vaddfp`, `vmaddfp`, `vrefp`, `vrsqrtefp` |
| Vector (Int) | `vadduwm`, `vsububs`, `vmaxsw` |
| Vector (Other) | `vperm`, `vsel`, `vsldoi`, `vspltw`, `vpkuhum` |
| Conditional Register | `crand`, `cror`, `crxor` |

Unimplemented instructions emit a `PPC_UNIMPLEMENTED` trap macro rather than silently failing, producing a runtime error.

### Register Access

Builder functions access PPC registers through typed unions on `PPCContext`. The `BuilderContext` provides accessor functions that return either local variable names or context member expressions, depending on [[register locality configuration|rexglue CLI Configuration File]]:

```cpp
BuilderContext::r();  // returns either "rN" (local) or "ctx.rN" (context)
BuilderContext::f();  // returns either "fN" or "ctx.fN"
BuilderContext::v();  // returns either "vN" or "ctx.vN"
BuilderContext::cr(); // returns either "crN" or "ctx.crN"
```

Register values are accessed via typed suffixes on the register union:
- `r3.u64` / `r3.s64` / `r3.u32` / `r3.s32`: integer access
- `f0.d`: double-precision float
- `v0`: 128-bit vector (backed by SIMDE `__m128` for portability)

### Configurable Register Locality

Several [[TOML config flags|rexglue CLI Configuration File]] control whether registers are stored as local variables (faster, since the compiler can optimize them into machine registers) or accessed through the `PPCContext` struct:

| Config Flag | Registers Affected |
|--|--|
| `non_argument_registers_as_local_variables` | r0, r2, r11, r12, f0, v32-v63 |
| `non_volatile_registers_as_local_variables` | r14-r31, f14-f31, v14-v31, v64-v127 |
| `cr_registers_as_local_variables` | cr0-cr7 |
| `ctr_as_local_variable` | ctr |
| `xer_as_local_variable` | xer |
| `reserved_register_as_local_variable` | reserved (lwarx/stwcx) |

When `non_volatile_registers_as_local_variables` is enabled, calls to `__savegprlr_N`/`__restgprlr_N` helper functions are elided; the local variable tracking makes them unnecessary.

### BuilderContext

`BuilderContext` is the central object passed to every instruction builder. It provides:

- Register accessors (`r()`, `f()`, `v()`, `cr()`, `ctr()`, `xer()`)
- Output helpers (`print()`, `println()` with fmt-style formatting)
- MMIO detection (`mmio_check_d_form()`, `mmio_check_x_form()`)
- Load/store emission (`emit_load_d_form()`, `emit_store_x_form()`, etc.)
- Branch emission (`emit_conditional_branch()`, `emit_function_call()`)
- CSR flush mode tracking (`emit_set_flush_mode()`)
- Mid-ASM hook support (`emit_mid_asm_hook()`)

## Special Handling

### MMIO Detection

Memory-mapped I/O accesses require special treatment because they target hardware registers rather than normal memory. The codegen detects MMIO via two mechanisms:

1. **eieio fence**: if the instruction following a load/store is `eieio` (Enforce In-Order Execution of I/O), the access is MMIO
2. **Register tracking**: when `lis` or `oris` loads an upper half matching known MMIO ranges, the destination register is flagged as an MMIO base. Subsequent loads/stores using that register emit `PPC_MM_LOAD_*`/`PPC_MM_STORE_*` macros instead of the normal versions.

Known MMIO upper-half ranges:
- `0x7FC8`-`0x7FCF`: GPU registers
- `0x7FEA`-`0x7FEF`: XMA/APU registers

The MMIO flag propagates through `mr`, `or`, and `ori` instructions that copy or combine register values.

### CSR Flush Mode

Xbox 360 PPC uses different denormal handling for scalar FPU vs. vector VMX instructions. The codegen tracks a `CSRState` (Unknown, FPU, VMX) and emits `ctx.fpscr.enableFlushMode()` / `ctx.fpscr.disableFlushMode()` calls at state transitions. After labels (potential jump targets from unknown origins), the state resets to Unknown, causing a conditional mode check on the next FP/VMX instruction.

### Jump Tables

When the recompiler encounters `bctr` (branch to count register), it attempts to reconstruct switch/case dispatch:

1. Backward scan from `bctr` to find `mtctr rX`
2. Trace the register chain backward to find the table load instruction
3. Identify the table type based on the load instruction:
   - `lwzx`: absolute 32-bit addresses
   - `lbzx`: byte offsets added to a base address
   - `lhzx`: 16-bit offsets added to a base address
   - `lbzx` + `rlwinm`: byte values shifted and added to base (computed)
4. Scan backward for bounds check (`cmpli`/`cmpi` or `clrlwi` mask)
5. Read table entries and validate targets against the containing code region

If detection succeeds at recompile time (late detection), the jump table and its labels are retroactively added so the generated `switch` dispatch is correct. If auto-detection fails, use [[switch_tables|rexglue CLI Configuration File]] in the TOML config to specify tables manually.

## Design Rationale

**Why static recompilation over JIT?** Xenia uses a JIT backend that translates PPC instructions at runtime into host machine code. This works well for general-purpose emulation but means the host compiler's optimization passes (register allocation, instruction scheduling, vectorization) must be reimplemented in the JIT. ReXGlue takes the opposite approach: the codegen pipeline runs offline, producing standard C++ that Clang/MSVC can optimize with their full pass pipelines. The output is deterministic, debuggable with standard tools (debuggers, profilers, sanitizers), and can be distributed without shipping the original game code.

**Why C++ as the target language?** C++ provides direct access to host platform APIs (Win32, POSIX, graphics backends), mature SSE/AVX intrinsic support via SIMDE for PPC vector instruction emulation, and compatibility with existing game engine middleware. No custom intermediate representation is needed; the C++ compiler's own IR handles all optimization. The weak symbol / alias pattern (`__attribute__((alias))`) allows individual functions to be [[overridden at link time|Function Overrides]] without modifying generated code.

## FunctionGraph Model

The `FunctionGraph` is the central data structure shared between Analysis and Recompilation. Each `FunctionNode` follows a three-state lifecycle:

```
kRegistered ──discover()──> kDiscovered ──seal()──> kSealed
```

- **kRegistered**: Entry point known, no blocks yet
- **kDiscovered**: Blocks and instructions assigned, may have unresolved branches
- **kSealed**: All branches resolved, ready for code generation

Authority levels determine boundary mutability:

| Authority | Source | Mutable? |
|--|--|--|
| `GAP_FILL` | Unclaimed code regions | Can be absorbed |
| `DISCOVERED` | `bl` call targets | Immutable entry point |
| `VTABLE` | RTTI vtable slots | Immutable entry point |
| `HELPER` | Signature-matched helpers | Fixed, overlaps allowed |
| `PDATA` | Exception table entries | Entry fixed, can extend |
| `CONFIG` | User [[rexglue CLI Configuration File]] | Exact boundaries, immutable |
| `IMPORT` | Import thunk resolution | External, immutable |
