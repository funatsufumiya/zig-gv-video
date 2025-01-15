// ported from https://github.com/UniversalGameExtraction/texture2ddecoder/blob/master/src/bcn/bc2.rs

const std = @import("std");
const bc1_decoder = @import("bc1_decoder.zig");

pub inline fn decodeBc2Alpha(data: []const u8, outbuf: []u32, channel: usize) void {
    const channel_shift = channel * 8;
    const channel_mask = 0xFFFFFFFF ^ (@as(u32, 0xFF) << @intCast(channel_shift));
    
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const bit_i = i * 4;
        const by_i = bit_i >> 3;
        const av = @as(u8, 0xf) & (data[by_i] >> @intCast(bit_i & 7));
        const alpha_value = (av << 4) | av;
        outbuf[i] = (outbuf[i] & channel_mask) | (@as(u32, alpha_value) << @intCast(channel_shift));
    }
}

pub inline fn decodeBc2Block(data: []const u8, outbuf: []u32) void {
    bc1_decoder.decodeBc1Block(data[8..], outbuf);
    decodeBc2Alpha(data, outbuf, 3);
}

pub inline fn copyBlockBuffer(
    bx: usize,
    by: usize,
    w: usize,
    h: usize,
    bw: usize,
    bh: usize,
    buffer: []const u32,
    image: []u32,
) void {
    const x: usize = bw * bx;
    const copy_width: usize = if (bw * (bx + 1) > w) w - bw * bx else bw;

    const y_0 = by * bh;
    const copy_height: usize = if (bh * (by + 1) > h) h - y_0 else bh;
    var buffer_offset: usize = 0;

    var y: usize = y_0;
    while (y < y_0 + copy_height) : (y += 1) {
        const image_offset = y * w + x;
        @memcpy(image[image_offset .. image_offset + copy_width], buffer[buffer_offset .. buffer_offset + copy_width]);
        buffer_offset += bw;
    }
}

pub inline fn color(r: u8, g: u8, b: u8, a: u8) u32 {
    return @as(u32, b) | (@as(u32, g) << 8) | (@as(u32, r) << 16) | (@as(u32, a) << 24);
}

pub fn decodeBc2(data: []const u8, width: usize, height: usize, image: []u32) !void {
    const BLOCK_WIDTH: usize = 4;
    const BLOCK_HEIGHT: usize = 4;
    const BLOCK_SIZE: usize = BLOCK_WIDTH * BLOCK_HEIGHT;
    const RAW_BLOCK_SIZE: usize = 16;

    const num_blocks_x: usize = (width + BLOCK_WIDTH - 1) / BLOCK_WIDTH;
    const num_blocks_y: usize = (height + BLOCK_HEIGHT - 1) / BLOCK_HEIGHT;

    var buffer: [BLOCK_SIZE]u32 = .{color(0, 0, 0, 255)} ** BLOCK_SIZE;

    if (data.len < num_blocks_x * num_blocks_y * RAW_BLOCK_SIZE) {
        return error.NotEnoughData;
    }

    if (image.len < width * height) {
        return error.ImageBufferTooSmall;
    }

    var data_offset: usize = 0;
    var by: usize = 0;
    while (by < num_blocks_y) : (by += 1) {
        var bx: usize = 0;
        while (bx < num_blocks_x) : (bx += 1) {
            decodeBc2Block(data[data_offset..], &buffer);
            copyBlockBuffer(
                bx,
                by,
                width,
                height,
                BLOCK_WIDTH,
                BLOCK_HEIGHT,
                &buffer,
                image,
            );
            data_offset += RAW_BLOCK_SIZE;
        }
    }
}