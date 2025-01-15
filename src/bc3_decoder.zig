// ported from https://github.com/UniversalGameExtraction/texture2ddecoder/blob/master/src/bcn/bc3.rs
// WARNING: IMCOMPLETED

const std = @import("std");
const bc1_decoder = @import("bc1_decoder.zig");

pub inline fn decodeBc3Alpha(data: []const u8, outbuf: []u32, channel: usize) void {
    // Initialize alpha values array with first two reference values
    var a: [8]u16 = undefined;
    a[0] = @as(u16, data[0]);
    a[1] = @as(u16, data[1]);

    // Interpolate alpha values based on whether a[0] > a[1]
    if (a[0] > a[1]) {
        // 8-point interpolation
        a[2] = (a[0] * 6 + a[1]) / 7;
        a[3] = (a[0] * 5 + a[1] * 2) / 7;
        a[4] = (a[0] * 4 + a[1] * 3) / 7;
        a[5] = (a[0] * 3 + a[1] * 4) / 7;
        a[6] = (a[0] * 2 + a[1] * 5) / 7;
        a[7] = (a[0] + a[1] * 6) / 7;
    } else {
        // 6-point interpolation plus transparent and opaque
        a[2] = (a[0] * 4 + a[1]) / 5;
        a[3] = (a[0] * 3 + a[1] * 2) / 5;
        a[4] = (a[0] * 2 + a[1] * 3) / 5;
        a[5] = (a[0] + a[1] * 4) / 5;
        a[6] = 0;
        a[7] = 255;
    }

    // Read 48-bit alpha indices (6 bytes starting from byte 2)
    var d: usize = @as(usize, std.mem.readInt(u48, data[2..8], .little));

    const channel_shift = channel * 8;
    const channel_mask = 0xFFFFFFFF ^ (@as(u32, 0xFF) << @intCast(channel_shift));

    // Apply alpha values to each pixel
    for (outbuf) |*p| {
        p.* = (p.* & channel_mask) | (@as(u32, @intCast(a[d & 7])) << @intCast(channel_shift));
        d >>= 3;
    }
}

pub inline fn decodeBc3Block(data: []const u8, outbuf: []u32) void {
    bc1_decoder.decodeBc1Block(data[8..], outbuf);
    decodeBc3Alpha(data, outbuf, 3);
}
