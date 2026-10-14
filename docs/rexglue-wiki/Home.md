ReXGlue is an experimental SDK for static recompilation of Xbox 360 executables. Its goal is to provide an extensible, modular foundation for building and customizing recompiled game projects for educational and research purposes. It provides the tooling and runtime components needed to analyze, recompile, and run Xbox 360 binaries natively on modern platforms.

This is early-stage software. Expect rough edges, incomplete implementations, and things that don't quite work yet.

> [!IMPORTANT]
>
> This is **not** a turnkey solution for running Xbox 360 games. It is **not** an alternative to Xenia.
>
> Using this SDK requires advanced knowledge of Xbox 360 internals, PowerPC architecture, and emulation concepts. You will spend significant time manually specifying function boundaries, providing missing kernel imports, and iterating on codegen output. If you want to play Xbox 360 games, use [Xenia](https://github.com/xenia-project/xenia).
>
> ReXGlue is experimental and pre-1.0. APIs and CLI behavior may change between releases without notice.

## How ReXGlue Relates to Xenia

ReXGlue's runtime is derived from [Xenia](https://github.com/xenia-project/xenia)'s emulator core. The kernel object model, memory layout, threading primitives, and many subsystem interfaces originate from Xenia's codebase. If you've worked with Xenia, you will recognize the structure.

**That is where the similarity ends.** ReXGlue is a fundamentally different kind of project. Xenia is a dynamic emulator that JIT-compiles PPC instructions at runtime. ReXGlue is a static recompilation toolkit that converts entire binaries to native C++ ahead of time. Nearly every subsystem has been reworked, stripped down, or replaced to support this model. Xenia's `Processor` has been stripped of its JIT and renamed to `FunctionDispatcher` (a thin guest-to-host dispatch table). The codegen pipeline, function override system, and build integration are entirely new.

This is not a fork you can run games with. It is a development SDK for people who want to build standalone native ports of individual titles, one function at a time.

For detailed comparisons of specific subsystems, see:

- [[Runtime Architecture Overview]]: subsystem hierarchy, initialization sequence, FunctionDispatcher, ExportResolver
- [[Kernel State & Objects]]: side-by-side comparison table, function dispatch, module loading differences
- [[Codegen Pipeline Overview]]: why static recompilation over JIT, design rationale

## Audience

This wiki is for SDK developers building recompiled game projects and contributors to the SDK itself.

It assumes familiarity with C++, CMake, and low-level systems programming.

## Quick Links

- [[Getting Started]]: prerequisites, installation, first build
- [[Contributing]]: code style, build instructions, PR workflow

## Status

**v0.3.x** (active development). Core codegen pipeline, runtime kernel, memory subsystem, and VFS are functional. Graphics, audio, and input backends are in flux.

See the sidebar for full documentation coverage.
