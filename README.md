# tigerbeetle-io

![license: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)
![zig 0.16](https://img.shields.io/badge/zig-0.16.0-orange.svg)
![platforms: linux | darwin](https://img.shields.io/badge/platforms-linux%20%7C%20darwin-lightgrey.svg)
![upstream: TigerBeetle 0.17.4](https://img.shields.io/badge/upstream-TigerBeetle%200.17.4-yellow.svg)

> TigerBeetle's single-threaded async I/O engine, vendored as a Zig 0.16
> library. `io_uring` on Linux, `kqueue` on Darwin. Zero dependencies.

A BrainGang-curated port of TigerBeetle's single-threaded async I/O engine.
The substrate that `box`, `relay`, and `gate` share for Linux `io_uring` and
macOS `kqueue` event loops.

Upstream: TigerBeetle 0.17.4
(<https://github.com/tigerbeetle/tigerbeetle>, Apache-2.0). See
[`UPSTREAM.md`](./UPSTREAM.md) for the precise file manifest, the patches we
maintain, and the rationale for what was pruned.

## Why a separate vendor package

TigerBeetle's I/O loop is the tightest single-threaded async event loop we've
found for Linux + Darwin, but upstream doesn't ship it as a standalone
library — it lives inside the consensus database and pulls in VSR,
superblock, tracing, and the testing harness. Three reasons it's worth
carving out:

1. **One I/O loop, not three.** Without this package, `box`, `relay`, and
   `gate` would each either reimplement the loop or vendor TigerBeetle
   whole. Sharing this substrate is how the discipline stays consistent.
2. **Zig version bridge.** Upstream pins Zig 0.14.1; BrainGang runs on
   Zig 0.16. The std API churn between those versions needs patches with
   a single, audited home — see [`UPSTREAM.md`](./UPSTREAM.md).
3. **Pruned and auditable.** ~232 KB of source after pruning, no third-
   party dependencies. Every file is upstream-verbatim, patched (each
   patch site carries a `// braingang port:` comment), or synthesized
   (each shim has a header explaining the upstream symbols it replaces).

## Rules this port enforces

- Zero external dependencies (no third-party packages, no C libs to link).
- Zero new dynamic-allocation paths added by BrainGang. Anything upstream
  uses `allocator` for is left alone; we don't introduce new ones.
- Single-threaded event loop, no worker pool fallback.
- Platform `Backend` is `io_uring` (Linux) or `kqueue` (Darwin), no
  `fallback_poll`. Other platforms compile-error in `src/lib.zig`.

## Use

```zig
const tbio = @import("tigerbeetle_io");

var io = try tbio.IO.init(32, 0);
defer io.deinit();

// tbio.backend tells you which path is compiled in:
//   .tigerbeetle_linux_io_uring  on Linux
//   .tigerbeetle_darwin_kqueue   on macOS, iOS, tvOS, watchOS
```

`tbio.IO` is the upstream type re-exported unchanged from `src/io.zig`. The
TigerBeetle method surface (`io.accept`, `io.recv`, `io.send`, `io.close`,
`io.connect`, `io.timeout`, `io.cancel`, `io.run_for_ns`, etc.) is what you
call.

For the consumer-facing contract — how the Completion + callback model
works, who owns memory, why the one-in-flight pattern gives you TCP
backpressure for free, and what anti-patterns break the performance
promise — read [`USAGE.md`](./USAGE.md). It is the doc to read before
writing a new consumer.

## Building

```sh
zig build         # builds the library module
zig build test    # runs the smoke tests (init/deinit, backend assertion)
```

Smoke tests live in `test/`. They are platform-conditional: on macOS the
asserted backend is `tigerbeetle_darwin_kqueue`, on Linux it's
`tigerbeetle_linux_io_uring`. The Zig version this port targets is in the
root `.zig-version` file.

## What's in here

- `src/io.zig` — upstream entry point (1 patch: drop Windows branch).
- `src/io/{common,linux}.zig` — upstream backends, untouched.
- `src/io/darwin.zig` — upstream Darwin backend, small Zig 0.16 std-API patches.
- `src/queue.zig`, `src/time.zig`, `src/list.zig` — upstream peer modules
  (small patches to drop test blocks that referenced pruned submodules).
- `src/stdx/{time_units,windows}.zig` — upstream stdx, verbatim.
- `src/stdx/stdx.zig` — upstream stdx, pruned and Zig 0.16-patched.
- `src/constants.zig`, `src/trace.zig`, `src/vsr/superblock.zig` — BrainGang
  shims that expose only the symbols the IO closure actually uses, so we
  don't drag the TigerBeetle consensus protocol and tracing subsystem into
  the library.
- `src/lib.zig` — BrainGang package boundary, adds the `Backend` enum.
- `test/tcp_echo.zig` — smoke tests.
- `UPSTREAM.md` — full file manifest and sync procedure.

## Staying in sync with upstream

When TigerBeetle ships a new release and you want to bring it forward in
this port, follow the 7-step procedure in
[`UPSTREAM.md`](./UPSTREAM.md#sync-procedure-for-future-upstream-bumps).
The short version:

1. Update the upstream tag, commit SHA, and dates at the top of `UPSTREAM.md`.
2. Diff the upstream-verbatim files against the new upstream and copy them
   over. `tools/check-manifest.sh` against an upstream checkout will catch
   any SHA drift.
3. For each patched file, re-apply the named patches — every patch site
   carries a `// braingang port:` marker so they're easy to find.
4. Audit the three synthesized shims (`constants.zig`, `trace.zig`,
   `vsr/superblock.zig`): if upstream's IO closure now references new
   symbols from any of these namespaces, extend the shim accordingly.
5. `zig build test` from this directory; the smoke tests assert the
   right backend compiles in for the host platform.

If the new upstream diverges from this port further than the current
patch budget can absorb cleanly, the honest move is to forgo the bump
and document the divergence — or to fork upstream rather than continue
porting.

## Credits

This port stands entirely on
[TigerBeetle](https://github.com/tigerbeetle/tigerbeetle)'s work. The
single-threaded IO discipline, the `io_uring` and `kqueue` backends, the
intrusive queue and list, the stdx peer modules — all of it is the
TigerBeetle team's design and code. BrainGang's contribution is
mechanical: prune to the IO closure, bridge Zig 0.14.1 → 0.16, and write
the three shims that let the IO compile without the rest of the
TigerBeetle database core. To learn the real thing, read the upstream
codebase.

## License

Apache-2.0 throughout. Upstream-verbatim files credit the TigerBeetle
Authors via an SPDX header. Patched files carry **two**
`SPDX-FileCopyrightText` lines — TigerBeetle Authors for the original
code, BrainGang for the modifications — as Apache-2.0 §4 permits.
BrainGang originals (`lib.zig`, the three shims, `build.zig`, tests,
`tools/check-manifest.sh`) carry a single BrainGang copyright header.
The exact changes are listed in [`UPSTREAM.md`](./UPSTREAM.md) and
marked at the patch sites with `// braingang port:` comments.

- [`LICENSE-APACHE-2.0`](./LICENSE-APACHE-2.0) — full Apache-2.0 text.
- [`NOTICE`](./NOTICE) — derived-from attribution and file manifest summary.
