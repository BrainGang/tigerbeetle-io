// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 BrainGang

// BrainGang minimal shim — NOT a verbatim copy of upstream `src/constants.zig`.
//
// Upstream's `src/constants.zig` (TigerBeetle 0.17.4) imports `vsr.zig` (the
// consensus protocol implementation) and `config.zig`, which transitively pull
// in the entire TigerBeetle database core. The `tigerbeetle_io` library
// actually references only three symbols from the constants namespace:
//
//   - `sector_size`  — used by io/{linux,darwin}.zig for buffer alignment
//                      and direct-IO sector accounting.
//   - `tick_ms`      — used by io/linux.zig in run_for_ns() as a tick cadence.
//   - `verify`       — used by queue.zig and list.zig as a runtime-assertion
//                      gate (controls extra invariant checks).
//
// We expose only those three, with values copied verbatim from the upstream
// production defaults (TigerBeetle 0.17.4):
//
//   sector_size : 4096           — src/constants.zig line 489
//   tick_ms     : 10             — src/config.zig line 120 (Process.tick_ms default)
//   verify      : false          — Production default; debug builds may set true
//
// See: vendor/tigerbeetle-io/UPSTREAM.md — "Synthesized shims".
// Maintenance: when the upstream subset above changes shape, this shim must be
// updated alongside, and the change recorded in UPSTREAM.md.

pub const sector_size: u32 = 4096;
pub const tick_ms: u63 = 10;
pub const verify: bool = false;
