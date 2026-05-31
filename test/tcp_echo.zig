// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 BrainGang

// Smoke test for the tigerbeetle_io port.
//
// First wave: verify the port compiles, exposes the expected Backend, and
// can allocate + free a real IO instance for the host platform. Real TCP
// echo benchmarking lives in BENCH.md / a separate harness.

const std = @import("std");
const builtin = @import("builtin");
const tbio = @import("tigerbeetle_io");

test "backend matches host platform" {
    const expected: tbio.Backend = switch (builtin.target.os.tag) {
        .linux => .tigerbeetle_linux_io_uring,
        .macos, .ios, .tvos, .watchos => .tigerbeetle_darwin_kqueue,
        else => unreachable,
    };
    try std.testing.expectEqual(expected, tbio.backend);
}

test "IO.init then deinit on host" {
    var io = try tbio.IO.init(32, 0);
    defer io.deinit();
}
