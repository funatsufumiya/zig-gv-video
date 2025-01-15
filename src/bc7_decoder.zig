// ported from https://github.com/UniversalGameExtraction/texture2ddecoder/blob/master/src/bcn/bc7.rs
// WARNING: IMCOMPLETED

const std = @import("std");
const bptc = @import("bptc_consts.zig");

const Bc7ModeInfo = struct {
    num_subsets: usize,
    partition_bits: usize,
    rotation_bits: usize,
    index_selection_bits: usize,
    color_bits: usize,
    alpha_bits: usize,
    endpoint_pbits: usize,
    shared_pbits: usize,
    index_bits: [2]usize,
};

// BC7 mode information table
const S_BP7_MODE_INFO = [8]Bc7ModeInfo{
    .{ .num_subsets = 3, .partition_bits = 4, .rotation_bits = 0, .index_selection_bits = 0, .color_bits = 4, .alpha_bits = 0, .endpoint_pbits = 1, .shared_pbits = 0, .index_bits = .{ 3, 0 } },
    .{ .num_subsets = 2, .partition_bits = 6, .rotation_bits = 0, .index_selection_bits = 0, .color_bits = 6, .alpha_bits = 0, .endpoint_pbits = 0, .shared_pbits = 1, .index_bits = .{ 3, 0 } },
    .{ .num_subsets = 3, .partition_bits = 6, .rotation_bits = 0, .index_selection_bits = 0, .color_bits = 5, .alpha_bits = 0, .endpoint_pbits = 0, .shared_pbits = 0, .index_bits = .{ 2, 0 } },
    .{ .num_subsets = 2, .partition_bits = 6, .rotation_bits = 0, .index_selection_bits = 0, .color_bits = 7, .alpha_bits = 0, .endpoint_pbits = 1, .shared_pbits = 0, .index_bits = .{ 2, 0 } },
    .{ .num_subsets = 1, .partition_bits = 0, .rotation_bits = 2, .index_selection_bits = 1, .color_bits = 5, .alpha_bits = 6, .endpoint_pbits = 0, .shared_pbits = 0, .index_bits = .{ 2, 3 } },
    .{ .num_subsets = 1, .partition_bits = 0, .rotation_bits = 2, .index_selection_bits = 0, .color_bits = 7, .alpha_bits = 8, .endpoint_pbits = 0, .shared_pbits = 0, .index_bits = .{ 2, 2 } },
    .{ .num_subsets = 1, .partition_bits = 0, .rotation_bits = 0, .index_selection_bits = 0, .color_bits = 7, .alpha_bits = 7, .endpoint_pbits = 1, .shared_pbits = 0, .index_bits = .{ 4, 0 } },
    .{ .num_subsets = 2, .partition_bits = 6, .rotation_bits = 0, .index_selection_bits = 0, .color_bits = 5, .alpha_bits = 5, .endpoint_pbits = 1, .shared_pbits = 0, .index_bits = .{ 2, 0 } },
};

// BitReader implementation
const BitReader = struct {
    data: []const u8,
    offset: usize,

    fn init(data: []const u8) BitReader {
        return .{
            .data = data,
            .offset = 0,
        };
    }

    fn read(self: *BitReader, bits: usize) u32 {
        var result: u32 = 0;
        var remaining = bits;
        var current_offset = self.offset;

        while (remaining > 0) {
            const byte_offset = current_offset >> 3;
            const bit_offset = @as(u3, @intCast(current_offset & 7));
            const _8_u4: u4 = @as(u4, @intCast(8));
            // const bits_available: u3 = 8 - bit_offset;
            const bits_available: u3 = @as(u3, @truncate(_8_u4 - @as(u4, @intCast(bit_offset))));
            const bits_to_read = @min(remaining, bits_available);
            const mask = (@as(u32, 1) << @intCast(bits_to_read)) - 1;
            const value = (self.data[byte_offset] >> bit_offset) & @as(u8, @intCast(mask));
            
            result |= @as(u32, value) << @intCast(bits - remaining);
            remaining -= bits_to_read;
            current_offset += bits_to_read;
        }

        self.offset = current_offset;
        return result;
    }

    fn peek(self: *BitReader, offset: usize, bits: usize) u32 {
        const saved_offset = self.offset;
        self.offset = offset;
        const result = self.read(bits);
        self.offset = saved_offset;
        return result;
    }
};

// Helper functions
inline fn expandQuantized(v: u8, bits: usize) u8 {
    const s = v << @intCast(8 - bits);
    return s | (s >> @intCast(bits));
}

inline fn color(r: u8, g: u8, b: u8, a: u8) u32 {
    return @as(u32, b) | (@as(u32, g) << 8) | (@as(u32, r) << 16) | (@as(u32, a) << 24);
}

pub fn decodeBc7Block(data: []const u8, outbuf: []u32) void {
    var bit = BitReader.init(data);

    // Find mode
    var mode: usize = 0;
    while (bit.read(1) == 0 and mode < 8) : (mode += 1) {}
    
    if (mode == 8) {
        @memset(outbuf[0..16], 0);
        return;
    }

    const mi = &S_BP7_MODE_INFO[mode];
    // const mode_pbits = if (mi.endpoint_pbits != 0) mi.endpoint_pbits else mi.shared_pbits;
    const mode_pbits: u5 = @as(u5, @intCast(if (mi.endpoint_pbits != 0) mi.endpoint_pbits else mi.shared_pbits));

    // Read mode-specific data
    const partition_set_idx = bit.read(mi.partition_bits);
    const rotation_mode = @as(u8, @intCast(bit.read(mi.rotation_bits)));
    const index_selection_mode = bit.read(mi.index_selection_bits);

    // Initialize endpoint arrays
    var ep_r = [_]u8{0} ** 6;
    var ep_g = [_]u8{0} ** 6;
    var ep_b = [_]u8{0} ** 6;
    var ep_a = [_]u8{0xff} ** 6;

    // Read color endpoints
    var i: usize = 0;
    while (i < mi.num_subsets) : (i += 1) {
        ep_r[i * 2] = @intCast(bit.read(mi.color_bits) << mode_pbits);
        ep_r[i * 2 + 1] = @intCast(bit.read(mi.color_bits) << mode_pbits);
    }
    i = 0;
    while (i < mi.num_subsets) : (i += 1) {
        ep_g[i * 2] = @intCast(bit.read(mi.color_bits) << mode_pbits);
        ep_g[i * 2 + 1] = @intCast(bit.read(mi.color_bits) << mode_pbits);
    }
    i = 0;
    while (i < mi.num_subsets) : (i += 1) {
        ep_b[i * 2] = @intCast(bit.read(mi.color_bits) << mode_pbits);
        ep_b[i * 2 + 1] = @intCast(bit.read(mi.color_bits) << mode_pbits);
    }

    // Read alpha endpoints if present
    if (mi.alpha_bits > 0) {
        i = 0;
        while (i < mi.num_subsets) : (i += 1) {
            ep_a[i * 2] = @intCast(bit.read(mi.alpha_bits) << mode_pbits);
            ep_a[i * 2 + 1] = @intCast(bit.read(mi.alpha_bits) << mode_pbits);
        }
    }

    // Handle P-bits
    if (mode_pbits != 0) {
        i = 0;
        while (i < mi.num_subsets) : (i += 1) {
            const pda = @as(u8, @intCast(bit.read(mode_pbits)));
            const pdb = if (mi.shared_pbits == 0) 
                @as(u8, @intCast(bit.read(mode_pbits))) 
            else 
                pda;

            ep_r[i * 2] |= pda;
            ep_r[i * 2 + 1] |= pdb;
            ep_g[i * 2] |= pda;
            ep_g[i * 2 + 1] |= pdb;
            ep_b[i * 2] |= pda;
            ep_b[i * 2 + 1] |= pdb;
            ep_a[i * 2] |= pda;
            ep_a[i * 2 + 1] |= pdb;
        }
    }

    // Expand quantized endpoints
    const color_bits = mi.color_bits + mode_pbits;
    i = 0;
    while (i < mi.num_subsets) : (i += 1) {
        ep_r[i * 2] = expandQuantized(ep_r[i * 2], color_bits);
        ep_r[i * 2 + 1] = expandQuantized(ep_r[i * 2 + 1], color_bits);
        ep_g[i * 2] = expandQuantized(ep_g[i * 2], color_bits);
        ep_g[i * 2 + 1] = expandQuantized(ep_g[i * 2 + 1], color_bits);
        ep_b[i * 2] = expandQuantized(ep_b[i * 2], color_bits);
        ep_b[i * 2 + 1] = expandQuantized(ep_b[i * 2 + 1], color_bits);
    }

    if (mi.alpha_bits > 0) {
        const alpha_bits = mi.alpha_bits + mode_pbits;
        i = 0;
        while (i < mi.num_subsets) : (i += 1) {
            ep_a[i * 2] = expandQuantized(ep_a[i * 2], alpha_bits);
            ep_a[i * 2 + 1] = expandQuantized(ep_a[i * 2 + 1], alpha_bits);
        }
    }

    // Index decoding and color interpolation
    const has_index_bits1 = mi.index_bits[1] != 0;
    var offset = [2]usize{ 0, mi.num_subsets * (16 * mi.index_bits[0] - 1) };

    var yy: usize = 0;
    while (yy < 4) : (yy += 1) {
        var xx: usize = 0;
        while (xx < 4) : (xx += 1) {
            const idx = yy * 4 + xx;
            var subset_index: usize = 0;
            var index_anchor: usize = 0;

            // Handle partitioning
            switch (mi.num_subsets) {
                2 => {

                    subset_index = (@as(usize, bptc.S_BPTC_P2[partition_set_idx]) >> @intCast(idx)) & 1;
                    index_anchor = if (subset_index != 0) bptc.S_BPTC_A2[partition_set_idx] else 0;
                },
                3 => {

                    subset_index = (@as(usize, bptc.S_BPTC_P3[partition_set_idx]) >> @intCast(2 * idx)) & 3;
                    index_anchor = if (subset_index != 0) 
                        bptc.S_BPTC_A3[subset_index - 1][partition_set_idx] 
                    else 
                        0;
                },
                else => {},
            }

            const anchor = idx == index_anchor;
            const num = [2]usize{
                mi.index_bits[0] - @intFromBool(anchor),
                if (has_index_bits1) mi.index_bits[1] - @intFromBool(anchor) else 0,
            };

            const index = [2]usize{
                bit.peek(offset[0], num[0]),
                if (has_index_bits1) bit.peek(offset[1], num[1]) else bit.peek(offset[0], num[0]),
            };

            offset[0] += num[0];
            offset[1] += num[1];

            // Color interpolation
            const fc = @as(u16, bptc.S_BPTC_FACTORS[mi.index_bits[index_selection_mode] - 2][index[index_selection_mode]]);
            const fa = @as(u16, bptc.S_BPTC_FACTORS[mi.index_bits[1 - index_selection_mode] - 2][index[1 - index_selection_mode]]);

            const fca = 64 - fc;
            const fcb = fc;
            const faa = 64 - fa;
            const fab = fa;

            subset_index *= 2;

            var rr = @as(u8, @intCast(((@as(u16, ep_r[subset_index]) * fca + @as(u16, ep_r[subset_index + 1]) * fcb + 32) >> 6)));
            var gg = @as(u8, @intCast(((@as(u16, ep_g[subset_index]) * fca + @as(u16, ep_g[subset_index + 1]) * fcb + 32) >> 6)));
            var bb = @as(u8, @intCast(((@as(u16, ep_b[subset_index]) * fca + @as(u16, ep_b[subset_index + 1]) * fcb + 32) >> 6)));
            var aa = @as(u8, @intCast(((@as(u16, ep_a[subset_index]) * faa + @as(u16, ep_a[subset_index + 1]) * fab + 32) >> 6)));

            // Handle rotation
            switch (rotation_mode) {
                1 => std.mem.swap(u8, &aa, &rr),
                2 => std.mem.swap(u8, &aa, &gg),
                3 => std.mem.swap(u8, &aa, &bb),
                else => {},
            }

            outbuf[idx] = color(rr, gg, bb, aa);
        }
    }
}