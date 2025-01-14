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
    reader: std.fs.File.Reader,

    pub fn load(reader: anytype) !GVVideo {
        _ = reader;
        // @compileError("Unimplemented");
        @panic("Unimplemented");
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