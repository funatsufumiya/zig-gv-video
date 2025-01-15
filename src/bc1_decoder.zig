// ported from https://github.com/UniversalGameExtraction/texture2ddecoder/blob/master/src/bcn/bc1.rs
// WARNING: IMCOMPLETED

const std = @import("std");

inline fn rgb565Le(value: u16) struct { u8, u8, u8 } {
    const r = @as(u8, @intCast((value >> 8 & 0xf8) | (value >> 13)));
    const g = @as(u8, @intCast((value >> 3 & 0xfc) | (value >> 9 & 3)));
    const b = @as(u8, @intCast(value & 0x1f)) << 3 | @as(u8, @intCast(value >> 2 & 7));
    return .{ r, g, b };
}

inline fn color(r: u8, g: u8, b: u8, a: u8) u32 {
    return @as(u32, b) | (@as(u32, g) << 8) | (@as(u32, r) << 16) | (@as(u32, a) << 24);
}

pub inline fn decodeBc1Block(data: []const u8, outbuf: []u32) void {
    // Read color endpoints as little-endian u16s
    const q0 = std.mem.readInt(u16, data[0..2], .little);
    const q1 = std.mem.readInt(u16, data[2..4], .little);

    // Convert RGB565 to RGB888
    const rgb0 = rgb565Le(q0);
    const rgb1 = rgb565Le(q1);
    const r0: u8 = rgb0[0];
    const g0: u8 = rgb0[1];
    const b0: u8 = rgb0[2];
    const r1: u8 = rgb1[0];
    const g1: u8 = rgb1[1];
    const b1: u8 = rgb1[2];

    // Initialize color palette
    var c: [4]u32 = undefined;
    c[0] = color(r0, g0, b0, 255);
    c[1] = color(r1, g1, b1, 255);

    // Convert to u16 for interpolation
    const r0_u16: u16 = @as(u16, r0);
    const g0_u16: u16 = @as(u16, g0);
    const b0_u16: u16 = @as(u16, b0);
    const r1_u16: u16 = @as(u16, r1);
    const g1_u16: u16 = @as(u16, g1);
    const b1_u16: u16 = @as(u16, b1);

    // Calculate interpolated colors based on whether q0 > q1
    if (q0 > q1) {
        c[2] = color(
            @intCast((r0_u16 * 2 + r1_u16) / 3),
            @intCast((g0_u16 * 2 + g1_u16) / 3),
            @intCast((b0_u16 * 2 + b1_u16) / 3),
            255,
        );
        c[3] = color(
            @intCast((r0_u16 + r1_u16 * 2) / 3),
            @intCast((g0_u16 + g1_u16 * 2) / 3),
            @intCast((b0_u16 + b1_u16 * 2) / 3),
            255,
        );
    } else {
        c[2] = color(
            @intCast((r0_u16 + r1_u16) / 2),
            @intCast((g0_u16 + g1_u16) / 2),
            @intCast((b0_u16 + b1_u16) / 2),
            255,
        );
        c[3] = color(0, 0, 0, 255);
    }

    // Read 32-bit color indices
    var d: usize = @as(usize, std.mem.readInt(u32, data[4..8], .little));

    // Apply color indices to output buffer
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        outbuf[i] = c[d & 3];
        d >>= 2;
    }
}
