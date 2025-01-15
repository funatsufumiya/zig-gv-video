const std = @import("std");
const ezdxt = @import("ezdxt");
const gvvideo = @import("gvvideo");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // load file
    var file = try std.fs.cwd().openFile("test_asset/test-10px.gv", .{});
    defer file.close();

    // load gvvideo
    var video = try gvvideo.GVVideo.loadFile(allocator, &file);
    defer video.deinit();

    const w: u32 = 10;
    const h: u32 = 10;

    try std.testing.expectEqual(10, video.header.width);
    try std.testing.expectEqual(10, video.header.height);
    try std.testing.expectEqual(5, video.header.frame_count);
    try std.testing.expectApproxEqAbs(1.0, video.header.fps, 0.01);
    try std.testing.expectEqual(.DXT1, video.header.format);
    try std.testing.expectEqual(72, video.header.frame_bytes);
    try std.testing.expectEqual(std.time.ns_per_s * 5, video.getDuration());

    // get frame ([]u32 RGBA)
    var frame = try video.readFrameAt(std.time.ns_per_s * 3.5);
    try std.testing.expectEqual(w * h, frame.len);
    try std.testing.expectEqual(0xFFFF0000, frame[0]); // x,y=0,0: red (0xAARRGGBB)
    try std.testing.expectEqual(0xFF0000FF, frame[6]); // x,y=6,0: blue (0xAARRGGBB)
    try std.testing.expectEqual(0xFF00FF00, frame[0 + w*6]); // x,y=0,6: green (0xAARRGGBB)
    try std.testing.expectEqual(0xFFE7FF00, frame[6 + w*6]); // x,y=6,6: yellow (0xAARRGGBB)



    // 4.99 sec
    frame = try video.readFrameAt(std.time.ns_per_s * 4.99);
    try std.testing.expectEqual(w * h, frame.len);

    // 5.01 sec is out of range
    if (video.readFrameAt(std.time.ns_per_s * 5.01)) |_| {
        return error.TestUnexpectedResult;
    } else |err| {
        try std.testing.expectEqual(error.EndOfVideo, err);
    }

    std.debug.print("All tests passed\n", .{});
}