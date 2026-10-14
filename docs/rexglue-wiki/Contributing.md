Guidelines for contributing to the ReXGlue SDK, covering build setup, code style, and the pull request workflow.

## Prerequisites

- **CMake** 3.25+
- **Clang** 20+
- **Ninja**

See [[Getting Started]] for full environment setup instructions.

## Building

```bash
# Configure (pick your platform preset)
cmake --preset win-amd64    # Windows
cmake --preset linux-amd64  # Linux

# Build and install
cmake --build out/build/[preset name] --target install
```

> [!TIP]
> **Windows contributors:** the `scripts/PSReX/` PowerShell module provides optional `rex-*` aliases that wrap the cmake workflow. `Import-Module ./scripts/PSReX` then use `rex-configure`, `rex-build`, `rex-test`, `rex-format`.

## Code Style

The project uses [**Google C++ Style**](https://google.github.io/styleguide/cppguide.html) with project-specific conventions.

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes / Structs | PascalCase | `CommandProcessor` |
| Functions / Methods | PascalCase | `Initialize()` |
| Local variables | snake_case | `vertex_count` |
| Member variables | snake_case + trailing `_` | `chunk_size_` |
| Constants | k + PascalCase | `kMaxBufferSize` |
| Enum values | k + PascalCase | `kReadWrite` |
| Namespaces | lowercase, `::` nested | `rex::graphics` |
| Macros | UPPER_CASE | `REX_RESTRICT_VAR` |

### Formatting Rules

- **Line endings:** LF (`\n`) only -- no CRLF. Configure your editor and Git accordingly (see [Git Workflow](#git-workflow) below).
- **Indentation:** 2 spaces (no tabs)
- **Column limit:** 100
- **Braces:** K&R (opening brace on same line)
- **Namespace contents:** Not indented
- **Namespace closing:** `} // namespace rex::foo`
- **Pointers / References:** Left-aligned (`int* p`, `int& r`)
- **Const placement:** West const (`const int x`)
- **Access specifiers:** 1-space indent (` public:`)
- **Include guards:** `#pragma once`
- **Project includes:** Angle brackets (`<rex/...>`)
- **Include order:** C headers, C++ STL, platform headers, third-party, `<rex/...>`
- **Preferred:** `using` over `typedef`

## Git Workflow

### Line Endings

This project uses **LF line endings exclusively**. Windows developers must configure Git to handle this correctly:

```bash
git config core.autocrlf input
```

With `core.autocrlf=input`, Git will convert CRLF to LF on commit but leave LF untouched on checkout.

If your editor is inserting CRLF, configure it to use LF:
- **VS Code:** Set `"files.eol": "\n"` in settings
- **CLion:** Settings > Editor > Code Style > Line separator: "Unix and macOS (\\n)"

### Linear History

This project uses a **linear history** -- no merge commits. Always rebase your branch onto `upstream/main` (or similar) before creating a pull request.

> [!IMPORTANT]
> If you have conflicts, resolve them during the rebase.
> Never use `git merge` to update your branch.

### Submitting Changes

1. Create a branch from your forked repo's `main`
2. Make your changes
3. Rebase onto the latest `upstream/main` (or similar) before pushing
4. Push and open a pull request against `main`

> [!IMPORTANT]
> All pull requests must have an associated issue (or issues). Link them in the PR description. If no issue exists for what you're working on, create one first.
