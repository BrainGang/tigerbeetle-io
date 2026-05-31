// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 BrainGang

// BrainGang library boundary for tigerbeetle_io.
//
// Upstream's `src/io.zig` is the IO entry point; this file is the
// `tigerbeetle_io` Zig package root that consumers (relay, gate, future Box
// services) import. It re-exports the upstream IO surface unchanged and adds
// a small BrainGang-side `Backend` declaration so callers can detect which
// platform-specific event loop is compiled in without poking at `builtin`.
//
// Industrial-grade rule: only Linux (io_uring) and Darwin (kqueue) are
// supported. Other platforms are rejected at compile time with no fallback.

const builtin = @import("builtin");
const upstream_io = @import("io.zig");

pub const IO = upstream_io.IO;
pub const DirectIO = upstream_io.DirectIO;
pub const buffer_limit = upstream_io.buffer_limit;

pub const Backend = enum {
    tigerbeetle_linux_io_uring,
    tigerbeetle_darwin_kqueue,
};

pub const backend: Backend = switch (builtin.target.os.tag) {
    .linux => .tigerbeetle_linux_io_uring,
    .macos, .ios, .tvos, .watchos => .tigerbeetle_darwin_kqueue,
    else => @compileError(
        "tigerbeetle_io: unsupported platform (Linux io_uring or Darwin kqueue only)",
    ),
};
