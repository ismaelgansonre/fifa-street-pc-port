The VFS maps Xbox 360 guest paths to host filesystem paths, allowing recompiled game code to perform file I/O using the original path conventions (`game:\content\data.bin`, `d:\media\video.wmv`, etc.).

## Device Architecture

The VFS is built on a device abstraction:

- **`Device`** (base class): defines the interface for a mounted filesystem (`Initialize()`, `ResolvePath()`, mount path, read-only flag, and disk statistics).
- **`VirtualFileSystem`**: manages the device registry, symbolic link table, and path resolution. Devices are resolved in registration order.

### Device Types

**`HostPathDevice`**: Maps a device mount path to a host directory. This is the primary device type. Constructor takes a mount path, a `std::filesystem::path` to the host directory, and a read-only flag. `ResolvePath()` walks the host directory tree to find the requested entry.

**`NullDevice`**: Accepts all I/O and returns success without performing actual operations. Used for paths that games expect to exist (cache partitions, raw disk) but whose data is not needed for recompilation. Constructor takes a base mount path and a list of sub-paths to handle (e.g., `\Partition0`, `\Cache0`, `\Cache1`).

## Default Mounts

`Runtime::SetupVfs()` configures the following devices:

| Device Path | Type | Host Path | Symlinks | Purpose |
|-------------|------|-----------|----------|---------|
| `\Device\Harddisk0\Partition1` | `HostPathDevice` | `game_data_root` | `game:`, `d:` | Game data (ROM contents) |
| `\Device\Harddisk0\PartitionUpdate` | `HostPathDevice` | `update_data_root` | `update:` | Title updates / DLC (only if path is non-empty and exists) |
| `\Device\Harddisk0` | `NullDevice` | (none) | (none) | Catches `\Partition0`, `\Cache0`, `\Cache1` (graceful no-op) |

The NullDevice is registered **after** `Partition1` because the VFS resolves devices in registration order. This ensures `Partition1` requests go to the real `HostPathDevice`, not the NullDevice.

Paths are configured via `PathConfig` in [[ReXApp::OnConfigurePaths()|ReXApp]], or via the `user_data_root` / `update_data_root` [[CVars|CVar System]].

> [!NOTE]
> VFS mounts may change as the filesystem subsystem evolves. Verify actual mount behavior against current source if you depend on specific device paths.

The `cache:` symbolic link is intentionally **not** registered. Games handle "device not found" for cache paths gracefully, but do not handle device errors (like `NAME_COLLISION`) well. Letting `cache:` fail with "not found" is the safer behavior.

## Path Resolution

When guest code opens a file:

1. The raw guest path (e.g., `game:\content\data.bin`) is passed to `VirtualFileSystem::ResolvePath()`.
2. Symbolic links are expanded: `game:` resolves to `\Device\Harddisk0\Partition1`.
3. The device registry is searched (in registration order) for a device whose mount path is a prefix of the resolved path.
4. The remaining path suffix is passed to `Device::ResolvePath()`, which walks the device's entry tree to locate the target.
5. Returns an `Entry*` (file or directory), or `nullptr` if not found.

Symbolic link resolution is recursive (a link can point to another link), but the VFS handles this internally.

## File I/O Flow

1. Guest code calls a file-open kernel import (e.g., `NtCreateFile`).
2. The [[kernel import|Kernel State & Objects]] implementation calls `VirtualFileSystem::OpenFile(root_entry, path, disposition, access, ...)`.
3. Path is resolved via `ResolvePath()` to an `Entry*`.
4. `Entry::Open(desired_access, &file)` creates a `File` object from the device.
5. An [[XFile|Kernel State & Objects]] kernel object is created wrapping the `File`, and a handle is returned to guest code.

**`XFile` operations:**

| Operation | Description |
|-----------|-------------|
| `Read` | Synchronous read at current or specified offset |
| `ReadScatter` | Scatter-gather read into multiple buffers |
| `Write` | Synchronous write |
| `SetLength` | Truncate or extend the file |
| `Rename` | Rename the file |
| `QueryDirectory` | Iterate directory children with wildcard matching |

**Async I/O:** `XFile` supports overlapped I/O via `CompleteOverlapped` and `CompleteOverlappedDeferred` on the `KernelState`. Completion is routed through the [[DPC|Kernel State & Objects]] dispatch queue, matching Xbox 360 I/O completion port semantics.

**File disposition modes** (matching Windows/Xbox 360 `NtCreateFile` semantics):

| Disposition | Exists | Does Not Exist |
|-------------|--------|----------------|
| Supersede | Replace | Create |
| Open | Open | Error |
| Create | Error | Create |
| OpenIf | Open | Create |
| Overwrite | Overwrite | Error |
| OverwriteIf | Overwrite | Create |

## Entry Attributes

Entries carry `FileAttributeFlags` matching Xbox 360 semantics:

| Flag | Value | Meaning |
|------|-------|---------|
| `kFileAttributeReadOnly` | `0x0001` | File is read-only |
| `kFileAttributeHidden` | `0x0002` | Hidden file |
| `kFileAttributeSystem` | `0x0004` | System file |
| `kFileAttributeDirectory` | `0x0010` | Entry is a directory |
| `kFileAttributeArchive` | `0x0020` | Archive flag |
| `kFileAttributeNormal` | `0x0080` | No other attributes set |
| `kFileAttributeTemporary` | `0x0100` | Temporary file |

Entries also carry timestamps: `create_timestamp`, `access_timestamp`, `write_timestamp`.

Directory entries support child iteration via `IterateChildren(wildcard_engine, &index)` for `QueryDirectory` operations with glob pattern matching.
