const std = @import("std");
const testing = @import("testing");

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

pub const GVVideo = struct {
    header: GVHeader,
    address_size_blocks: []GVAddressSizeBlock,
    stream: *std.io.StreamSource,

    pub fn load(allocator: std.mem.Allocator, stream: *std.io.StreamSource) !GVVideo {
        const reader = stream.reader();

        // Read header fields
        const endian = std.builtin.Endian.little;
        const width = try reader.readInt(u32, endian);
        const height = try reader.readInt(u32, endian);
        const frame_count = try reader.readInt(u32, endian);
        const fps = @as(f32, @floatFromInt(try reader.readInt(u32, endian)));
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
        };
    }

    pub fn loadFromFile(path: []const u8) !GVVideo {
        _ = path;
        // @compileError("Unimplemented");
        @panic("Unimplemented");
    }

    pub fn readFrame(self: *GVVideo, frame_id: u32) ![]u32 {
        _ = self;
        _ = frame_id;
        // @compileError("Unimplemented");
        @panic("Unimplemented");
    }

    pub fn readFrameAt(self: *GVVideo, duration: u64) ![]u32 {
        _ = self;
        _ = duration;
        // @compileError("Unimplemented");
        @panic("Unimplemented");
    }

    pub fn getDuration(self: *const GVVideo) u64 {
        _ = self;
        // @compileError("Unimplemented");
        @panic("Unimplemented");
    }

    pub fn deinit(self: *GVVideo, allocator: std.mem.Allocator) void {
        allocator.free(self.address_size_blocks);
    }
};

pub fn getRgba(color: u32) RGBAColor {
    _ = color;
    // @compileError("Unimplemented");
    @panic("Unimplemented");
}

pub fn getRgbaFromFrame(frame: []const u32, x: usize, y: usize, width: usize) RGBAColor {
    _ = frame;
    _ = x;
    _ = y;
    _ = width;
    // @compileError("Unimplemented");
    @panic("Unimplemented");
}

test "basic GVVideo functionality" {
    // Add tests here once implementation is complete
}