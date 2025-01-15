// Extreme Gpu Friendly Video Format
//
// binary file format:
// 
// 0: uint32_t width
// 4: uint32_t height
// 8: uint32_t frame count
// 12: float fps
// 16: uint32_t format (DXT1 = 1, DXT3 = 3, DXT5 = 5, BC7 = 7)
// 20: uint32_t frame bytes
// 24: raw frame storage (lz4 compressed)
// eof - (frame count) * 16: [(uint64_t, uint64_t)..<frame count] (address, size) of lz4, address is zero based from file head
//

const std = @import("std");

const lz4 = @import("lz4");
// const ezdxt = @import("ezdxt");
const bc1_decoder = @import("bc1_decoder.zig");
const bc2_decoder = @import("bc2_decoder.zig");
const bc3_decoder = @import("bc3_decoder.zig");
const bc7_decoder = @import("bc7_decoder.zig");

pub const GVFormat = enum(u32) {
    DXT1 = 1,
    DXT3 = 3,
    DXT5 = 5,
    BC7 = 7,
};

pub const GVHeader = struct {
    width: u32,
    height: u32,
    frame_count: u32,
    fps: f32,
    format: GVFormat,
    frame_bytes: u32,
};

pub const GVAddressSizeBlock = struct {
    address: u64,
    size: u64,
};

pub const RGBAColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const GVVideo = struct {
    header: GVHeader,
    address_size_blocks: []GVAddressSizeBlock,
    reader: std.io.StreamSource.Reader,
    stream: *std.io.StreamSource,
    allocator: std.mem.Allocator,

    fn readFloat(reader: anytype) !f32 {
        const bytes = try reader.readBytesNoEof(4);
        return @as(f32, @bitCast(bytes));
    }

    fn decodeLZ4(self: *GVVideo, data: []const u8) ![]u8 {
        const width: usize = @intCast(self.header.width);
        const height: usize = @intCast(self.header.height);
        const uncompressed_size: usize = (width * height * 4);
        const lz4_decoded_data: []const u8 = try lz4.Standard.decompress(self.allocator, data, uncompressed_size);
        return lz4_decoded_data;
    }

    pub fn load(allocator: std.mem.Allocator, stream: *std.io.StreamSource) !GVVideo {
        const reader = stream.reader();

        // Read header fields
        const endian = std.builtin.Endian.little;
        const width = try reader.readInt(u32, endian);
        const height = try reader.readInt(u32, endian);
        const frame_count = try reader.readInt(u32, endian);
        // const fps = @as(f32, @floatFromInt(try reader.readInt(u32, endian)));
        const fps = try readFloat(reader);
        const format_raw = try reader.readInt(u32, endian);
        const frame_bytes = try reader.readInt(u32, endian);

        // Convert format to enum
        const format = switch (format_raw) {
            1 => GVFormat.DXT1,
            3 => GVFormat.DXT3,
            5 => GVFormat.DXT5,
            7 => GVFormat.BC7,
            else => return error.InvalidFormat,
        };

        // Create header
        const header = GVHeader{
            .width = width,
            .height = height,
            .frame_count = frame_count,
            .fps = fps,
            .format = format,
            .frame_bytes = frame_bytes,
        };

        // Get current position for address blocks calculation
        const current_pos = try stream.getPos();
        // direct specify the position

        // Seek to address blocks (located at end of file)
        const end_pos = try stream.getEndPos();
        const blocks_offset = end_pos - (@as(u64, frame_count) * @sizeOf(GVAddressSizeBlock));
        try stream.seekTo(blocks_offset);

        // Read address size blocks
        var blocks = try allocator.alloc(GVAddressSizeBlock, frame_count);
        var i: usize = 0;
        while (i < frame_count) : (i += 1) {
            blocks[i] = .{
                .address = try reader.readInt(u64, endian),
                .size = try reader.readInt(u64, endian),
            };
        }

        // Seek back to data start
        try stream.seekTo(current_pos);

        return GVVideo{
            .header = header,
            .address_size_blocks = blocks,
            .stream = stream,
            .reader = reader,
            .allocator = allocator,
        };
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !GVVideo {
        // Open the file with read-only access
        const file = try std.fs.cwd().openFile(path, .{});
        
        // Create a stream source from the file
        var stream = std.io.StreamSource{ .file = file };
        
        // Use the existing load function with a general purpose allocator
        return GVVideo.load(allocator, &stream);
    }

    fn decodeLZ4AndDXT(self: *GVVideo, data: []u8) ![]const u32 {
        const width: u16 = @intCast(self.header.width);
        const height: u16 = @intCast(self.header.height);
        const format = self.header.format;
        const uncompressed_size_u8 = (width * height * 4);
        // const uncompressed_size_u32 = (width * height);
        const lz4_decoded_data: []const u8 = try lz4.Standard.decompress(self.allocator, data, uncompressed_size_u8);
        // var result = std.ArrayList(u32).init(self.allocator);

        const size: usize = width * height;
        // const result: []ezdxt.Rgba = try self.allocator.alloc(ezdxt.Rgba, size);
        const result: []u32 = try self.allocator.alloc(u32, size);

        switch (format) {
            .DXT1 => {
                bc1_decoder.decodeBc1Block(lz4_decoded_data, result);
                return result;
            },
            .DXT3 => {
                bc2_decoder.decodeBc2Block(lz4_decoded_data, result);
                return result;
            },
            .DXT5 => {
                bc3_decoder.decodeBc3Block(lz4_decoded_data, result);
                return result;
            },
            .BC7 => {
                bc7_decoder.decodeBc7Block(lz4_decoded_data, result);
                return result;
            }
        }
    }

    // decompress lz4 block and decode dxt, then return decompressed frame data (BGRA u32)
    pub fn readFrame(self: *GVVideo, frame_id: u32) ![]const u32 {
        if (frame_id >= self.header.frame_count) {
            return error.EndOfVideo;
        }

        // std.debug.print("frame_id: {}\n", .{frame_id});
        // std.debug.print("debug: {}\n", @as(i64, @intCast(-(self.header.frame_count * 16)))  + @as(i64, @intCast(frame_id * 16)));

        const block = self.address_size_blocks[frame_id];
        const address = block.address;
        const size = block.size;

        const data = try self.allocator.alloc(u8, size);
        try self.stream.seekTo(address);
        if (try self.stream.getPos() != address) {
            return error.ErrorSeekingFrameData;
        }
        if (try self.reader.readAll(data) != size) {
            return error.ErrorReadingFrameData;
        }
        return self.decodeLZ4AndDXT(data);
    }

    /// decompress lz4 block and decode dxt, then return decompressed frame data (BGRA u32), at specified time
    pub fn readFrameAt(self: *GVVideo, duration: u64) ![]const u32 {
        const frame_id: u32 = @as(u32, @intFromFloat(self.header.fps * @as(f32, @floatFromInt(duration / 1_000_000_000))));
        return self.readFrame(frame_id);
    }

    /// decompress lz4 block, then return compressed frame data (BC1, BC2, BC3, BC7)
    pub fn readFrameCompressed(self: *GVVideo, frame_id: u32) ![]const u8 {
        if (frame_id >= self.header.frame_count) {
            return error.EndOfVideo;
        }

        const block = self.address_size_blocks[frame_id];
        const address = block.address;
        const size = block.size;
        const data = try self.allocator.alloc(u8, size);
        try self.stream.seekTo(address);
        if (try self.stream.getPos() != address) {
            return error.ErrorSeekingFrameData;
        }
        if (try self.reader.readAll(data) != size) {
            return error.ErrorReadingFrameData;
        }
        return self.decodeLZ4(data);
    }

    /// decompress lz4 block, then return compressed frame data (BC1, BC2, BC3, BC7), at specified time
    pub fn readFrameCompressedAt(self: *GVVideo, duration: u64) ![]const u8 {
        const frame_id: u32 = @as(u32, @intFromFloat(self.header.fps * @as(f32, @floatFromInt(duration / 1_000_000_000))));
        return self.readFrameCompressed(frame_id);
    }

    pub fn getDuration(self: *const GVVideo) u64 {
        // Calculate duration in nanoseconds (frame_count / fps * 1_000_000_000)
        const seconds = @as(f64, @floatFromInt(self.header.frame_count)) / @as(f64, @floatCast(self.header.fps));
        return @intFromFloat(seconds * 1_000_000_000);
    }

    pub fn getWidth(self: *const GVVideo) u32 {
        return self.header.width;
    }

    pub fn getHeight(self: *const GVVideo) u32 {
        return self.header.height;
    }

    pub fn getResolution(self: *const GVVideo) [2]u32 {
        return [2]u32{ self.header.width, self.header.height };
    }

    pub fn getFrameCount(self: *const GVVideo) u32 {
        return self.header.frame_count;
    }

    pub fn getFps(self: *const GVVideo) f32 {
        return self.header.fps;
    }

    pub fn getFormat(self: *const GVVideo) GVFormat {
        return self.header.format;
    }

    pub fn getFrameBytes(self: *const GVVideo) u32 {
        return self.header.frame_bytes;
    }

    pub fn deinit(self: *GVVideo, allocator: std.mem.Allocator) void {
        allocator.free(self.address_size_blocks);
    }
};

/// color should be BGRA
pub fn getRgba(color: u32) RGBAColor {
    return RGBAColor{
        .r = @as(u8, @truncate((color >> 16) & 0xFF)),
        .g = @as(u8, @truncate((color >> 8) & 0xFF)),
        .b = @as(u8, @truncate(color & 0xFF)),
        .a = @as(u8, @truncate((color >> 24) & 0xFF)),
        };
}

/// color should be BGRA
pub fn getRgb(color: u32) RGBColor {
    return RGBColor{
        .r = @as(u8, @truncate((color >> 16) & 0xFF)),
        .g = @as(u8, @truncate((color >> 8) & 0xFF)),
        .b = @as(u8, @truncate(color & 0xFF)),
        };
}

/// color should be BGRA
pub fn getAlpha(color: u32) u8 {
    return @as(u8, @truncate((color >> 24) & 0xFF));
}

pub fn getRgbaFromFrame(frame: []const u32, x: usize, y: usize, width: usize) RGBAColor {
    _ = frame;
    _ = x;
    _ = y;
    _ = width;
    // @compileError("Unimplemented");
    @panic("Unimplemented");
}

test "rgb / rgba basic tests" {
    const testing = std.testing;

    // rgba: 189, 190, 189, 255
    const color = 0xFFBDBEBD;
    const rgba = getRgba(color);
    const rgb = getRgb(color);
    const alpha = getAlpha(color);
    try testing.expectEqual(189, rgba.r);
    try testing.expectEqual(190, rgba.g);
    try testing.expectEqual(189, rgba.b);
    try testing.expectEqual(255, rgba.a);
    try testing.expectEqual(189, rgb.r);
    try testing.expectEqual(190, rgb.g);
    try testing.expectEqual(189, rgb.b);
    try testing.expectEqual(255, alpha);

    // rgba: 192, 190, 0, 255
    const color2 = 0xFFC0BE00;
    const rgba2 = getRgba(color2);
    const rgb2 = getRgb(color2);
    const alpha2 = getAlpha(color2);
    try testing.expectEqual(192, rgba2.r);
    try testing.expectEqual(190, rgba2.g);
    try testing.expectEqual(0, rgba2.b);
    try testing.expectEqual(255, rgba2.a);
    try testing.expectEqual(192, rgb2.r);
    try testing.expectEqual(190, rgb2.g);
    try testing.expectEqual(0, rgb2.b);
    try testing.expectEqual(255, alpha2);
}

test "basic GVVideo functionality" {
    // Add tests here once implementation is complete
}