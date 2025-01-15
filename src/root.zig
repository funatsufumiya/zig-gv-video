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

const assert = std.debug.assert;

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
    stream: *std.io.StreamSource,
    reader: std.io.StreamSource.Reader,
    allocator: std.mem.Allocator,

    fn readFloat(reader: anytype) !f32 {
        const bytes = try reader.readBytesNoEof(4);
        return @as(f32, @bitCast(bytes));
    }

    fn decodeLZ4(self: *GVVideo, data: []const u8) ![]const u8 {
        const width: usize = @intCast(self.header.width);
        const height: usize = @intCast(self.header.height);
        const uncompressed_size_u8: usize = @as(usize, width) * @as(usize, height) * 4;
        const lz4_decoded_data: []const u8 = try lz4.Standard.decompress(self.allocator, data, uncompressed_size_u8);
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

    fn decodeLZ4AndDXT(self: *GVVideo, data: []const u8) ![]const u32 {
        const width: u16 = @intCast(self.header.width);
        const height: u16 = @intCast(self.header.height);
        const format = self.header.format;
        const uncompressed_size_u8: usize = @as(usize, width) * @as(usize, height) * 4;
        // const uncompressed_size_u32 = (width * height);
        const lz4_decoded_data: []const u8 = try lz4.Standard.decompress(self.allocator, data, uncompressed_size_u8);

        const size: usize = width * height;
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

    /// only for testing
    fn _decodeDXT(self: *GVVideo, data: []const u8) ![]const u32 {
        const width: u16 = @intCast(self.header.width);
        const height: u16 = @intCast(self.header.height);
        const format = self.header.format;
        const uncompressed_size_u32: usize = @as(usize, width) * @as(usize, height);
        const uncompressed_size_u8: usize = uncompressed_size_u32 * 4;
        const lz4_decoded = try lz4.Standard.decompress(self.allocator, data, uncompressed_size_u8);
        const result: []u32 = try self.allocator.alloc(u32, uncompressed_size_u32);
        switch (format) {
            .DXT1 => {
                bc1_decoder.decodeBc1Block(lz4_decoded, result);
                return result;
            },
            .DXT3 => {
                bc2_decoder.decodeBc2Block(lz4_decoded, result);
                return result;
            },
            .DXT5 => {
                bc3_decoder.decodeBc3Block(lz4_decoded, result);
                return result;
            },
            .BC7 => {
                bc7_decoder.decodeBc7Block(lz4_decoded, result);
                return result;
            },
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

        const data: []u8 = try self.allocator.alloc(u8, size);
        defer self.allocator.free(data);

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

    // // reader.readAllAlloc always causes error, so this is workaround
    // fn readAllAlloc(self: *GVVideo, size: usize) ![]u8 {
    //     const data: []u8 = try self.allocator.alloc(u8, size);
    //     if (data.len != size) {
    //         return error.ErrorAllocatingFrameData;
    //     }

    //     // as workaround, read each bytes
    //     var i: usize = 0;
    //     while (i < size) : (i += 1) {
    //         std.debug.print("i: {}\n", .{i});
    //         const byte: u8 = try self.reader.readByte();
    //         data[i] = byte;
    //     }

    //     return data;
    // }

    /// decompress lz4 block, then return compressed frame data (BC1, BC2, BC3, BC7)
    pub fn readFrameCompressed(self: *GVVideo, frame_id: u32) ![]const u8 {
        if (frame_id >= self.header.frame_count) {
            return error.EndOfVideo;
        }

        const block = self.address_size_blocks[frame_id];
        // std.debug.print("frame_id: {}\n", .{frame_id});
        // std.debug.print("block.address: {}\n", .{block.address});
        // std.debug.print("block.size: {}\n", .{block.size});
        const address = block.address;
        const size = block.size;

        try self.stream.seekTo(address);
        if (try self.stream.getPos() != address) {
            return error.ErrorSeekingFrameData;
        }

        // print EOF - pos
        std.debug.print("EOF: {}\n", .{try self.stream.getEndPos()});
        std.debug.print("EOF - pos: {}\n", .{(try self.stream.getEndPos()) - address});
        std.debug.print("expected size: {}\n", .{size});

        const data = self.reader.readAllAlloc(self.allocator, size) catch |err| {   
            std.debug.print("error: {}\n", .{err});
            return err;
        };

        // const data = try self.readAllAlloc(size);
        defer self.allocator.free(data);

        // const data = try self.reader.readAllAlloc(self.allocator, size);
        std.debug.print("data_size: {}\n", .{data.len});

        if (data.len != size) {
        // if (try self.reader.readAll(data) != size) {
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

test "seekable stream test with fixed bytes" {
    const testing = std.testing;
    // const stream: std.io.StreamSource = std.io.fixedBufferStream("Hello, world!");
    var stream: std.io.StreamSource = std.io.StreamSource{ .const_buffer = std.io.fixedBufferStream("Hello, world!") };
    const reader = stream.reader();

    try testing.expectEqual(("H")[0], try reader.readByte());
    try testing.expectEqual(("e")[0], try reader.readByte());
    try testing.expectEqual(("l")[0], try reader.readByte());

    try stream.seekTo(0);
    try testing.expectEqual(("H")[0], try reader.readByte());

    try stream.seekTo(6);
    try testing.expectEqual((" ")[0], try reader.readByte());
    try testing.expectEqual(("w")[0], try reader.readByte());

    try stream.seekTo(4);
    try testing.expectEqual(("o")[0], try reader.readByte());
    try testing.expectEqual((",")[0], try reader.readByte());
}

test "seekable stream test with fixed bytes 0x0, 0x1, ..." {
    const testing = std.testing;
    const n: u8 = 200;
    const buffer = try testing.allocator.alloc(u8, n);
    defer testing.allocator.free(buffer);

    var i: u8 = 0;
    while (i < buffer.len) : (i += 1) {
        buffer[i] = i;
    }

    var stream: std.io.StreamSource = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(buffer) };
    const reader = stream.reader();

    try testing.expectEqual(0x0, try reader.readByte());
    try testing.expectEqual(0x1, try reader.readByte());

    try stream.seekTo(0);
    try testing.expectEqual(0x0, try reader.readByte());
    try testing.expectEqual(0x1, try reader.readByte());

    try stream.seekTo(0x64);
    try testing.expectEqual(0x64, try reader.readByte());
    try testing.expectEqual(0x65, try reader.readByte());
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

test "header read" {
    const testing = std.testing;
    const header_data = [_]u8{
        0x02, 0x00, 0x00, 0x00, // width
        0x02, 0x00, 0x00, 0x00, // height
        0x02, 0x00, 0x00, 0x00, // frame count
        0x00, 0x00, 0x80, 0x3F, // fps (1.0)
        0x01, 0x00, 0x00, 0x00, // format (DXT1)
        0x04, 0x00, 0x00, 0x00, // frame bytes
        // Add dummy frame data
        0x00, 0x00, 0x00, 0x00,
        // Add address size blocks
        0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // address=24
        0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // size=4
        0x1C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // address=28 
        0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // size=4
    };

    var stream = std.io.StreamSource{ .const_buffer = std.io.fixedBufferStream(&header_data) };
    var header = try GVVideo.load(testing.allocator, &stream);
    defer header.deinit(testing.allocator);
    
    try testing.expectEqual(@as(u32, 2), header.header.width);
    try testing.expectEqual(@as(u32, 2), header.header.height);
    try testing.expectEqual(@as(u32, 2), header.header.frame_count);
    try testing.expectEqual(@as(f32, 1.0), header.header.fps);
    try testing.expectEqual(GVFormat.DXT1, header.header.format);
    try testing.expectEqual(@as(u32, 4), header.header.frame_bytes);
}

test "header read of test.gv" {
    const testing = std.testing;

    var video = try GVVideo.loadFromFile(testing.allocator, "test_asset/test.gv");
    defer video.deinit(testing.allocator);

    // header assertions
    try testing.expectEqual(@as(u32, 640), video.getWidth());
    try testing.expectEqual(@as(u32, 360), video.getHeight());
    try testing.expectEqual(@as(u32, 1), video.getFrameCount());
    try testing.expectApproxEqAbs(30.0, video.getFps(), 0.001);
    try testing.expectEqual(@as(u32, 115200), video.getFrameBytes());

    // address size blocks
    try testing.expectEqual(1, video.address_size_blocks.len);
    try testing.expectEqual(@as(u64, 24), video.address_size_blocks[0].address);
    try testing.expectEqual(@as(u64, 1507), video.address_size_blocks[0].size);
}

test "read rgba" {
    return error.SkipZigTest;

    // const testing = std.testing;

    // var video = try GVVideo.loadFromFile(testing.allocator, "test_asset/test.gv");
    // defer video.deinit(testing.allocator);

    // // header assertions
    // try testing.expectEqual(@as(u32, 640), video.getWidth());
    // try testing.expectEqual(@as(u32, 360), video.getHeight());
    // try testing.expectEqual(@as(u32, 1), video.getFrameCount());
    // try testing.expectApproxEqAbs(30.0, video.getFps(), 0.001);

    // const frame = try video.readFrame(0);
    // defer testing.allocator.free(frame);

    // // Test specific pixel colors
    // try testing.expectEqual(RGBAColor{ .r = 189, .g = 190, .b = 189, .a = 255 }, getRgba(frame[0]));
    // try testing.expectEqual(RGBAColor{ .r = 192, .g = 190, .b = 0, .a = 255 }, getRgba(frame[130]));
    // try testing.expectEqual(RGBAColor{ .r = 0, .g = 188, .b = 0, .a = 255 }, getRgba(frame[320]));
    // try testing.expectEqual(RGBAColor{ .r = 0, .g = 0, .b = 192, .a = 255 }, getRgba(frame[595]));

    // // Test specific coordinates
    // try testing.expectEqual(RGBAColor{ .r = 255, .g = 255, .b = 255, .a = 255 }, getRgba(frame[160 + 300 * 640]));
    // try testing.expectEqual(RGBAColor{ .r = 62, .g = 0, .b = 118, .a = 255 }, getRgba(frame[300 + 300 * 640]));
}

test "read compressed and _decodeDXT" {
    return error.SkipZigTest;

//     const testing = std.testing;
//     var video = try GVVideo.loadFromFile(testing.allocator, "test_asset/test.gv");
//     defer video.deinit(testing.allocator);

//     const frame = try video.readFrameCompressed(0);
//     defer testing.allocator.free(frame);

//     const frame_raw = try video._decodeDXT(frame);
//     defer testing.allocator.free(frame_raw);

//     try testing.expectEqual(640 * 360, frame_raw.len);
}

test "duration calculation" {
    const testing = std.testing;
    
    const video = GVVideo{
        .header = .{
            .width = 640,
            .height = 360,
            .frame_count = 1,
            .fps = 30.0,
            .format = .DXT1,
            .frame_bytes = 115200,
        },
        .address_size_blocks = &[_]GVAddressSizeBlock{},
        .stream = undefined,
        .reader = undefined,
        .allocator = undefined,
    };
    
    const duration = video.getDuration();
    try testing.expectEqual(@as(u64, 33333333), duration); // ~33.33ms in nanoseconds (1/30 sec)
}