const std = @import("std");
const ezdxt = @import("ezdxt");
const gvvideo = @import("gvvideo");

pub fn main() !void {
    // load video
    const file = try std.fs.cwd().openFile("test_asset/test-10px.gv", .{});
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var video = try gvvideo.GVVideo.load(reader);

    // or, simply use load_from_file
    // var video = try gvvideo.GVVideo.loadFromFile("test_asset/test-10px.gv");

    const w: u32 = 10;
    const h: u32 = 10;

    try std.testing.expectEqual(video.header.width, 10);
    try std.testing.expectEqual(video.header.height, 10);
    try std.testing.expectEqual(video.header.frame_count, 5);
    try std.testing.expectEqual(video.header.fps, 1.0);
    try std.testing.expectEqual(video.header.format, .DXT1);
    try std.testing.expectEqual(video.header.frame_bytes, 72);
    try std.testing.expectEqual(video.getDuration(), std.time.ns_per_s * 5);

    // get frame ([]u32 RGBA)
    var frame = try video.readFrameAt(std.time.ns_per_s * 3.5);
    try std.testing.expectEqual(frame.len, w * h);
    try std.testing.expectEqual(frame[0], 0xFFFF0000); // x,y=0,0: red (0xAARRGGBB)
    try std.testing.expectEqual(frame[6], 0xFF0000FF); // x,y=6,0: blue (0xAARRGGBB)
    try std.testing.expectEqual(frame[0 + w*6], 0xFF00FF00); // x,y=0,6: green (0xAARRGGBB)
    try std.testing.expectEqual(frame[6 + w*6], 0xFFE7FF00); // x,y=6,6: yellow (0xAARRGGBB)

    // 4.99 sec
    frame = try video.readFrameAt(std.time.ns_per_s * 4.99);
    try std.testing.expectEqual(frame.len, w * h);

    // 5.01 sec is out of range
    if (video.readFrameAt(std.time.ns_per_s * 5.01)) |_| {
        return error.TestUnexpectedResult;
    } else |err| {
        try std.testing.expectEqual(err, error.EndOfVideo);
    }

    std.debug.print("All tests passed\n", .{});
}