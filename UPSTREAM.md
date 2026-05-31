# Upstream Tracking

This file records the TigerBeetle I/O port maintained under
`vendor/tigerbeetle-io/`. The port is **not** a verbatim mirror — it is a
BrainGang-curated subset of TigerBeetle's `src/io` and its peer modules, with
deliberate pruning, minimal patches, and a few synthesized shims. Faithful
attribution lives here; the right of the port to diverge from upstream lives
in `WORKSPACE.md` and the project DESIGN.

## Upstream

- Repository: <https://github.com/tigerbeetle/tigerbeetle>
- Release tag: `0.17.4`
- Commit SHA: `c93615ab7979034484711a6a201acd01a4e40f1b`
- Release date: 2026-05-08
- License: Apache-2.0 (preserved at `vendor/tigerbeetle-io/LICENSE-APACHE-2.0`)
- Initial vendoring date: 2026-05-31
- Vendored by: BrainGang

Upstream pins Zig 0.14.1 (see TigerBeetle's `zig/download.sh`). This port
builds on **Zig 0.16.0** (`/Users/wangtz/projects/BrainGang/.zig-version`).
Going from 0.14 → 0.16 crosses two major std API churns. The patches needed
so far for the Linux/Darwin paths we actually exercise are recorded in the
"Patched" table below; more will accumulate as relay/gate exercise more of
the IO surface (accept/recv/send/etc.).

## File Manifest

Three categories: **upstream-verbatim**, **patched**, **synthesized**.

### Upstream-verbatim (bit-for-bit identical to TigerBeetle 0.17.4)

| Local path                | Upstream path             |
| ------------------------- | ------------------------- |
| `src/io/common.zig`       | `src/io/common.zig`       |
| `src/io/linux.zig`        | `src/io/linux.zig`        |
| `src/list.zig`            | `src/list.zig`            |
| `src/stdx/time_units.zig` | `src/stdx/time_units.zig` |
| `src/stdx/windows.zig`    | `src/stdx/windows.zig`    |

Run `tools/check-manifest.sh` against an upstream checkout to verify these
SHAs remain identical.

### Patched (originally from upstream, modified by this port)

Every patched file carries a `// braingang port:` comment at the patch site
explaining the change. Patches must be re-applied on each upstream sync.

| Local path           | Upstream path        | Patch summary                                                                                                                                                       |
| -------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/io.zig`         | `src/io.zig`         | Removed the `IO_Windows = @import("io/windows.zig").IO` line and its branch in the platform switch. We do not vendor `io/windows.zig`.                              |
| `src/io/darwin.zig`  | `src/io/darwin.zig`  | **Zig 0.16 std API drift.** `IO.init`: `try posix.kqueue()` → `std.c.kqueue()` + manual errno check; `IO.deinit`: `posix.close(fd)` → `_ = std.c.close(fd)`. Other `posix.*` call sites further into the IO methods are not yet patched because the current test/relay/gate code paths don't analyze them (Zig is function-level lazy). They'll need similar patches when exercised. |
| `src/queue.zig`      | `src/queue.zig`      | Truncated the `test "Queue: fuzz"` block at line 257. The block imported `stdx.RingBufferType`, `stdx.PRNG`, and `testing/fuzz.zig` — none of which are vendored.   |
| `src/time.zig`       | `src/time.zig`       | Removed the `test Timer` block and its `const fixtures = @import("testing/fixtures.zig")` reference. `testing/fixtures.zig` is not vendored.                        |
| `src/stdx/stdx.zig`  | `src/stdx/stdx.zig`  | Three categories of changes: (a) Removed unused `pub const` exports referring to pruned submodules and the matching entries in the trailing `comptime { _ = @import(...) }` block. (b) Removed three test blocks (`hash_inline`, `ByteSize.parse_flag_value`, `fastrange`/`fastrange not modulo`) that depended on `Flags`, `Snap`, `PRNG`, or `testing/low_level_hash_vectors.zig`. (c) **Zig 0.16 std API drift**: `@Type(.enum_literal)` → `@EnumLiteral()` at two sites (`scoped` helper, `log_with_timestamp` signature); deleted the unreferenced `EnumUnionType` helper because its body used `@Type(.{.@"union"=...})` which Zig 0.16 split into a new 5-argument `@Union` builtin. |

### Synthesized (NOT copied from upstream — BrainGang-authored shims and surface)

Each file carries a header comment with rationale and the exact upstream
symbols it stands in for.

| Local path                  | Replaces (upstream)                            | Rationale                                                                                                                                                              |
| --------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/constants.zig`         | `src/constants.zig`                            | Upstream `constants.zig` imports `vsr.zig` (consensus) and `config.zig`, transitively pulling in the entire TigerBeetle database core. This shim exposes only `sector_size`, `tick_ms`, `verify` — the symbols `io/{linux,darwin}.zig`, `queue.zig`, and `list.zig` actually reference. |
| `src/trace.zig`             | `src/trace.zig`                                | Upstream `trace.zig` imports `trace/event.zig`, `trace/statsd.zig`, the testing harness, and forms a circular dependency with `io.zig`. This shim exposes a `Tracer` struct with a no-op `timing(self, anytype, anytype) void` method. `io/common.zig` references `?*Tracer = null`; consumers (relay, gate) never attach a tracer. |
| `src/vsr/superblock.zig`    | `src/vsr/superblock.zig`                       | Upstream definition computes the constant from `SuperBlockHeader` size and `constants.superblock_copies`. `io/linux.zig` line 1859 references only the constant, inside a block-device sanity check path that BrainGang's relay/gate never execute. This shim pins it to 4 MB (matches upstream production value). |
| `src/lib.zig`               | n/a                                            | BrainGang package boundary. Re-exports `IO`, `DirectIO`, `buffer_limit` from the upstream `io.zig` and adds a `Backend` enum + `backend` constant so consumers can inspect which backend is compiled in. Industrial-grade rule: only Linux (`io_uring`) and Darwin (`kqueue`); other platforms compile-error. |

### Removed (not vendored — deliberate scope cut from upstream `src/stdx/` and `src/io/`)

The following upstream files are **not** present in this port. The rationale
follows the BrainGang TigerStyle rule "references must really be used": if no
code in the kept closure references the file at module scope (non-test), it
does not enter the vendor tree.

- `src/io/test.zig` — upstream's own IO test suite; not needed for the
  library surface and pulls in `vsr/checksum.zig`.
- `src/io/windows.zig` — Windows IOCP backend; BrainGang targets Linux/Darwin only.
- `src/stdx/bit_set.zig`, `bounded_array.zig`, `debug.zig`, `flags.zig`,
  `huge_page_allocator.zig`, `iops.zig`, `mlock.zig`, `prng.zig`,
  `radix.zig`, `ring_buffer.zig`, `sort_test.zig`, `unshare.zig`,
  `zipfian.zig` — none referenced by the IO closure at module scope.
- `src/stdx/testing/` (full subdir) — pure test infrastructure (`snaptest`,
  `low_level_hash_vectors`).
- `src/stdx/vendored/aegis.zig` — cryptographic hash; not needed by IO.

If a future change requires any of the removed files, bring it in by name,
update this manifest, and re-run `tools/check-manifest.sh`.

## Sync Procedure (for future upstream bumps)

1. Pick the target upstream tag/commit. Update the commit SHA, release tag,
   and dates in the "Upstream" section above.
2. Diff upstream's `src/io/`, `src/queue.zig`, `src/time.zig`, `src/list.zig`,
   `src/stdx/{stdx,time_units,windows}.zig` against the vendored files in
   this directory.
3. For each **upstream-verbatim** file, copy the new version. Re-run
   `tools/check-manifest.sh`.
4. For each **patched** file, re-apply the named patch. The `// braingang
   port:` comments in the local files document each patch site.
5. For each **synthesized** shim, audit whether upstream changed the symbol
   set the IO closure references. If `io/` now references new fields from
   `constants.zig`, `trace.zig`, or `vsr/superblock.zig`, extend the shim
   accordingly and update this manifest.
6. Run `zig build test` from `vendor/tigerbeetle-io/` and verify the two
   smoke tests pass on this host.
7. If the sync diverges further from upstream than this port currently does,
   document the new divergence and consider whether to fork upstream
   instead.

## Notes

- Disk footprint of the port (src/): ~232 KB, down from ~460 KB before the
  initial prune.
- Zig version: 0.16.0. Upstream pins 0.14.1; the gap was bridged with a
  small number of in-place patches at each call site (see "Patched").
- Licensing: Apache-2.0 throughout. Every source file carries an SPDX
  header. Upstream-verbatim files credit `2020-2026 TigerBeetle Authors`.
  Patched files carry two `SPDX-FileCopyrightText` lines — `2020-2026
  TigerBeetle Authors` for the original code and `2026 BrainGang` for
  the modifications (permitted by the closing paragraph of Apache-2.0 §4). BrainGang
  originals (`lib.zig`, the three synthesized shims, `build.zig`,
  `build.zig.zon`, tests, `tools/check-manifest.sh`) carry a single
  `SPDX-FileCopyrightText: 2026 BrainGang`. The root `NOTICE` file lists
  the derived-from attribution and the per-category file manifest.
