# tigerbeetle-io

A BrainGang-curated port of TigerBeetle's single-threaded async I/O engine.
The substrate that `box`, `relay`, and `gate` share for Linux `io_uring` and
macOS `kqueue` event loops.

Upstream: TigerBeetle 0.17.4
(<https://github.com/tigerbeetle/tigerbeetle>, Apache-2.0). See
[`UPSTREAM.md`](./UPSTREAM.md) for the precise file manifest, the patches we
maintain, and the rationale for what was pruned.

## Why TigerStyle

The single-threaded event-loop discipline is the whole point. The main thread
is either running short callbacks at nanosecond cadence or sleeping inside
`io_uring_enter` / `kevent` waiting for the kernel — never spinning between
threads. On Apple Silicon and other core-bounded targets this collapses
context-switch overhead and idle power to near zero. Hand-rolling that
loop per service is how it gets diluted; sharing this substrate is how it
stays disciplined.

Rules this port enforces:

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
TigerBeetle method surface (`io.tick`, `io.accept`, `io.recv`, etc.) is what
you call. See upstream documentation for the API.

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
- `src/io/{common,darwin,linux}.zig` — upstream backends, untouched.
- `src/queue.zig`, `src/time.zig`, `src/list.zig` — upstream peer modules
  (small patches to drop test blocks that referenced pruned submodules).
- `src/stdx/{stdx,time_units,windows}.zig` — upstream stdx, pruned.
- `src/constants.zig`, `src/trace.zig`, `src/vsr/superblock.zig` — BrainGang
  shims that expose only the symbols the IO closure actually uses, so we
  don't drag the TigerBeetle consensus protocol and tracing subsystem into
  the library.
- `src/lib.zig` — BrainGang package boundary, adds the `Backend` enum.
- `test/tcp_echo.zig` — smoke tests.
- `UPSTREAM.md` — full file manifest and sync procedure.

## License

Apache-2.0 for upstream-derived files (verbatim and patched). BrainGang-
authored files (`lib.zig`, the three shims, `build.zig`, tests, this
README) follow the project's overall license. `LICENSE-APACHE-2.0` is
preserved in this directory.
