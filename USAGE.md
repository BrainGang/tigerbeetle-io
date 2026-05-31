# Using tigerbeetle_io

This document is the consumer-facing contract for the `tigerbeetle_io` Zig
package. It documents the API shape, the memory ownership rules, and the
state-machine pattern that BrainGang services (`relay`, `gate`, and anything
that comes after) follow when they consume this library.

It is **not** a port of TigerBeetle's own internal docs. It is a BrainGang
synthesis of what was learned the first time we wired this into a working
service. Future consumers should read this first; then look at upstream
TigerBeetle's IO source if they need the syscall-level detail.

## The model in one paragraph

`tbio.IO` is a queue of pending operations and a dispatcher. You hand the
queue a "Completion" (a small struct **you own**) along with a callback
function. The IO library calls your callback when the underlying kernel
syscall finishes. There are no futures, no promises, no async/await.
Everything happens through callbacks on Completions. Your state machine
lives in your own structs; the IO library is just the engine room that
turns kernel completions into callback dispatches.

## API surface (Darwin/Linux symmetric)

```zig
// Construction
var io = try tbio.IO.init(entries: u12, flags: u32);
defer io.deinit();

// Drive the loop
try io.run();                    // forever
try io.run_for_ns(50_000_000);   // 50 ms slice, returns to caller

// Submit operations — pattern is identical for all of them:
io.<op>(self_ptr, ContextType, ctx, comptime callback, *Completion, ...op-specific args);

// Operations available:
io.accept(...,  *Completion, listener_fd)         -> AcceptError!socket_t
io.connect(..., *Completion, socket, address)     -> ConnectError!void
io.recv(...,    *Completion, socket, buf)         -> RecvError!usize     // 0 = peer EOF
io.send(...,    *Completion, socket, buf)         -> SendError!usize     // partial OK
io.close(...,   *Completion, fd)                  -> CloseError!void
io.timeout(..., *Completion, ns)                  -> TimeoutError!void
io.cancel(...,  *Completion, target_completion)   -> CancelError!void
// plus read/write/openat/fsync/next_tick/event_listen for non-net work

// Callback shape
fn on_done(ctx: *MyContext, comp: *Completion, result: OpError!ResultType) void {
    // result is an error union; check it.
    // To do the next operation, call another io.<op>(...) with another Completion.
}
```

The IO struct itself is the only globally shared state. One per process —
one per thread, if you ever want multiple threads, but BrainGang stays
single-threaded.

## Memory ownership

This is the rule that makes "zero malloc in steady state" actually true:

> **Every `*Completion` passed to an `io.<op>(...)` call must remain valid
> until the callback fires.** The IO library does not allocate the
> Completion; you do. The IO library does not own it; you do.

Practically, this means Completions live inside long-lived application
structs:

- A *listener* owns one Completion for its in-flight `accept`.
- A *Connection* owns one Completion per direction for in-flight
  recv/send (because at most one of those is active per direction).
- A *timer* owns one Completion for its in-flight `timeout`.
- A *shutdown sequence* may need a Completion per close in flight.

If you allocate Connections from a pre-built pool, every Completion address
is stable for the Connection's lifetime, and you never touch the allocator
during normal operation.

Anti-pattern: **do not** `var comp: Completion = undefined;` on the stack
and pass `&comp` to `io.send(...)` then return. The callback will fire
after your function returns and the Completion's stack memory is gone.

## The one-in-flight pattern

This is the central state-machine shape. For any "logical direction" of
data (e.g. agent → upstream), maintain at most one operation in flight
through a single Completion. Alternate it between recv and send across
calls:

```zig
const Direction = struct {
    buf: [16 * 1024]u8,
    buf_len: u32 = 0,
    comp: tbio.IO.Completion = undefined,
    state: enum { reading, writing, closed } = .reading,
};

// Kick off the loop:
io.recv(self, *Conn, conn, on_recv, &dir.comp, src_fd, &dir.buf);

fn on_recv(conn: *Conn, _: *Completion, result: RecvError!usize) void {
    const n = result catch |err| { conn.fail(err); return; };
    if (n == 0) { conn.peer_eof(.src_side); return; }
    conn.a_to_u.buf_len = @intCast(n);
    conn.a_to_u.state = .writing;
    // Note: we re-use the same Completion. It's idle here (callback returned).
    io.send(self, *Conn, conn, on_send_done, &conn.a_to_u.comp,
            conn.dst_fd, conn.a_to_u.buf[0..n]);
}

fn on_send_done(conn: *Conn, _: *Completion, result: SendError!usize) void {
    const sent = result catch |err| { conn.fail(err); return; };
    if (sent < conn.a_to_u.buf_len) {
        // Partial send — re-submit with the remainder. Same Completion.
        const remaining = conn.a_to_u.buf[sent..conn.a_to_u.buf_len];
        conn.a_to_u.buf_len -= @intCast(sent);
        std.mem.copyForwards(u8, &conn.a_to_u.buf, remaining);
        io.send(self, *Conn, conn, on_send_done, &conn.a_to_u.comp,
                conn.dst_fd, conn.a_to_u.buf[0..conn.a_to_u.buf_len]);
        return;
    }
    // Full send. Read again.
    conn.a_to_u.state = .reading;
    io.recv(self, *Conn, conn, on_recv, &conn.a_to_u.comp,
            conn.src_fd, &conn.a_to_u.buf);
}
```

Why this matters for performance: because we never have two operations on
one direction in flight, we cannot "overflow" any buffer. We cannot
allocate. We cannot deadlock waiting for the peer's buffer to drain. The
kernel's TCP window is the only flow-control mechanism in the system.

## Backpressure is a property, not a feature

If `src` is fast and `dst` is slow, here is what happens **automatically**
with the one-in-flight pattern:

1. `recv` returns 16 KB. We submit `send` and wait.
2. `dst` is slow, `send` takes a long time to complete.
3. We do not submit another `recv` until `send` returns. So we are not
   reading from `src`.
4. `src`'s outgoing TCP buffer fills. Kernel sets the TCP window to 0.
5. `src`'s upstream (the real sender) stops getting acks. It blocks at
   the TCP layer.

No application-level "please slow down" message. No buffer expansion. No
out-of-memory failure mode. Backpressure flows backward from the slow side
to the original sender through the kernel.

To preserve this property: **do not** add a queue of pending writes "for
flexibility". The moment you have multiple outstanding writes per
direction, you've reintroduced unbounded buffering. The state machine
above is the right shape.

## Partial sends are real

`send` may return fewer bytes than the buffer length. This is not an
error. It happens when:

- The kernel's socket send buffer is partially full.
- The peer's TCP window only allows partial.
- A signal interrupts.

Your `on_send_done` callback **must** check `bytes_sent < buf_len` and
re-submit `send` with `buf[bytes_sent..]`. This is shown in the snippet
above. Skipping this check gives you a slow stream of mysterious data
truncation in production.

Receives can also return less than the buffer length, but that's expected
behavior — `recv` returns whatever is available. Just keep calling it.

## run vs run_for_ns

`io.run()` blocks until the IO has no completions pending. For a server
that always has a listener accept in flight, this is "forever".

`io.run_for_ns(ns)` runs at most that many nanoseconds and returns.

BrainGang services should generally **not** use `io.run()`. The standard
service loop is:

```zig
while (!shutdown.load(.monotonic)) {
    try io.run_for_ns(50 * std.time.ns_per_ms);
    housekeeping();
}
```

This slices the loop so the thread can:

- Check for `SIGTERM` / shutdown signals.
- Rotate logs.
- Flush metrics.
- Verify pool consistency under debug builds.

50 ms is a reasonable default for "slice between housekeeping". Tune to
the workload; lower for low-latency interactive use, higher for batch
throughput.

## Timeouts and cancellation

`io.timeout(self, ctx, cb, &comp, ns)` fires the callback after `ns`
nanoseconds. Use this for:

- **Connect deadline.** Submit `io.connect(...)` and a parallel
  `io.timeout(...)`. Whichever fires first wins; cancel the other.
- **Idle deadline.** When a recv completes, arm a timeout for "N seconds
  without activity"; cancel and re-arm on next recv.
- **Total session budget.** Once per connection at start.

`io.cancel(self, ctx, cb, &cancel_comp, &target_comp)` cancels an
operation in flight. The original callback **still fires**, but with
`error.Canceled`. Your callback code must distinguish "real error" from
"we asked for this".

This means lifecycle code is explicit. To close a connection mid-recv:

1. Submit `io.cancel(..., &conn.recv_comp)` to cancel the recv.
2. In `on_recv` with `error.Canceled`, submit `io.close(..., &conn.close_comp, fd)`.
3. In `on_close`, mark the Connection slot free.

It's verbose but every step is visible. No magic destructors, no
double-free.

## Configuring sockets

Use `common.TCPOptions` (re-exported from upstream) to set socket flags
before handing the fd to `io.accept`/`io.recv`/`io.send`:

```zig
const tcp_opts = .{
    .rcvbuf = 256 * 1024,
    .sndbuf = 256 * 1024,
    .keepalive = .{ .keepidle = 30, .keepintvl = 10, .keepcnt = 3 },
    .user_timeout_ms = 30_000,
    .nodelay = false,  // see below
};
try common.tcp_options(fd, tcp_opts);
```

`TCP_NODELAY` is a footgun. Setting it disables Nagle's algorithm, which
helps for tiny request/response messages (REST APIs) but hurts throughput
for bulk transfer (file streaming, model token streams). Default to off
unless you know your workload pattern is small messages.

`keepalive` matters when the connection idles for minutes (model
streaming, persistent admin sessions). Without it, a network blip or NAT
table flush silently kills the connection and your app never knows.

## Sizing

Per-Connection memory is dominated by buffers:

```
Connection size ≈ 2 * (buf_size + sizeof(Completion))
              + sizeof(close completions, accept completion if applicable)
              + your own bookkeeping
```

With `buf_size = 16 KB`, `sizeof(Completion) ≈ 64 B`, the Direction
overhead is small. Headline number: a 1024-connection pool with 16 KB
buffers needs ~32 MB.

Buffer size guidance:

- **TCP forwarder** (relay): 16 KB. Saturates 10 Gbps with low syscall
  rate, fits well in L2 cache.
- **HTTP request/response** (gate): 4 KB is enough for request line +
  headers. If you ever serve big bodies, allocate a larger buffer just
  for response building, not for every connection.
- **Bulk file transfer**: 64 KB. Fewer syscalls per byte, but more memory
  per connection.

`tbio.IO.init(entries, flags)` takes a queue depth hint. Set it to the
total number of pending operations you expect at peak. For a relay with
1024 connections × 4 outstanding ops each = 4096. Round up to a power of
two. `flags` is currently unused on both backends; pass `0`.

## Anti-patterns

These break the contract or the performance promise:

- **Allocator in the hot path.** Pre-allocate the pool. Free-list it.
  Never `gpa.create(Connection)` inside `on_recv`.
- **Multiple outstanding writes per direction.** Reintroduces unbounded
  buffering and defeats backpressure.
- **`Completion` on the stack.** It must outlive the callback.
- **Sharing one Completion across overlapping operations.** A Completion
  is exclusive to one operation at a time. Once the callback fires, the
  Completion is yours again.
- **Blocking syscalls.** Anything that goes through libc directly
  (`std.posix.read`, `std.c.connect`) blocks the event thread. Always
  route net/disk work through `io.<op>(...)`.
- **`io.run()` without housekeeping.** You lose the ability to react to
  signals. Use `run_for_ns` slices.
- **Ignoring `error.Canceled`.** Every active Completion must handle
  Canceled, because cancellation can come from your own shutdown path.

## Verifying it works

A real consumer should be testable with simple invariants:

- Total memory after N connections drained = total memory at startup
  (no leak).
- Peak in-flight Completions ≤ pool_size × ops_per_connection
  (no completion leak).
- Throughput at N concurrent connections ≈ N × per-connection rate
  until CPU or kernel becomes the bottleneck (not userspace).

`vendor/tigerbeetle-io/test/tcp_echo.zig` is the seed test. Real
benchmarks belong in each consumer (relay's stress harness, gate's
load test) rather than here, because the library itself doesn't run
sockets — its consumers do.
