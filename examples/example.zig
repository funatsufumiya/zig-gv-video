const std = @import("std");
const ezdxt = @import("ezdxt");
const gvvideo = @import("gvvideo");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) {
        std.debug.print("Usage: {s} <filename>\n", .{args[0]});
        return;
    }
}