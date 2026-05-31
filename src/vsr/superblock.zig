// BrainGang minimal shim — NOT a verbatim copy of upstream `src/vsr/superblock.zig`.
//
// `io/linux.zig` line 1859 references `superblock_zone_size` from this module:
//
//     const superblock_zone_size =
//         @import("../vsr/superblock.zig").superblock_zone_size;
//     var read_buf: [superblock_zone_size]u8 align(constants.sector_size) = undefined;
//
// The call site is inside a block-device sanity check (verifies the first
// `superblock_zone_size` bytes of a raw block device are zero before allowing
// TigerBeetle to format it). BrainGang's relay/gate never open block devices,
// so this code path is unreachable.
//
// We expose only the constant. Upstream computes it as
// `superblock_copy_size * constants.superblock_copies` (≈ 4 MB in production).
// Pinning a fixed 4 MB here is safe because the value affects only a buffer
// declaration on an unreachable code path; replacing it with the real upstream
// computation requires vendoring `vsr/`, the consensus protocol, and the
// entire database core — out of scope for this library.
//
// See: vendor/tigerbeetle-io/UPSTREAM.md — "Synthesized shims".

pub const superblock_zone_size: usize = 4 * 1024 * 1024;
