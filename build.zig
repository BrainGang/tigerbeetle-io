// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 BrainGang

const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const os_tag = target.result.os.tag;
    const platform_supported = switch (os_tag) {
        .linux, .macos, .ios, .tvos, .watchos => true,
        else => false,
    };
    if (!platform_supported) {
        std.debug.print(
            "tigerbeetle_io: unsupported target os '{s}' — only Linux (io_uring) and Darwin (kqueue) are supported.\n",
            .{@tagName(os_tag)},
        );
        std.process.exit(1);
    }

    const stdx_module = b.addModule("stdx", .{
        .root_source_file = b.path("src/stdx/stdx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tigerbeetle_io = b.addModule("tigerbeetle_io", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "stdx", .module = stdx_module },
        },
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/tcp_echo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tigerbeetle_io", .module = tigerbeetle_io },
            },
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tigerbeetle-io tests");
    test_step.dependOn(&run_tests.step);
}
