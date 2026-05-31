// BrainGang minimal shim — NOT a verbatim copy of upstream `src/trace.zig`.
//
// Upstream's `src/trace.zig` (TigerBeetle 0.17.4) is a ~20KB tracing subsystem
// that:
//   1. Imports `trace/event.zig` and `trace/statsd.zig` (subdirectory).
//   2. Imports `io.zig` itself — creating a circular dependency.
//   3. Pulls in TigerBeetle's testing harness via `testing/fixtures.zig`.
//
// The `tigerbeetle_io` library references one symbol from this namespace:
//
//   - `Tracer` : declared in `io/common.zig` as a `?*Tracer = null` field.
//                The `Stats.trace()` function (lines 181-189 of io/common.zig)
//                guards its invocation with `if (stats.tracer) |tracer| { ... }`,
//                so when no tracer is attached the body is dead at runtime.
//                But the call site `tracer.timing(.event_tag, duration)` must
//                still type-check, so this shim declares a `timing` method
//                with `anytype` parameters that compiles to a no-op.
//
// Consumers (relay, gate) never attach a tracer, so this shim's bodies are
// genuinely unreachable. If real tracing is needed later, vendor upstream
// `trace.zig` along with its full peer dependency closure (trace/, testing/).
//
// See: vendor/tigerbeetle-io/UPSTREAM.md — "Synthesized shims".

pub const Tracer = struct {
    pub fn timing(_: *Tracer, _: anytype, _: anytype) void {}
};
