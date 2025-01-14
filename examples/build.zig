const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gvvideo_module = b.createModule(.{
        .root_source_file = b.path("../src/main.zig"),
    });

    const lib = b.addExecutable(.{
        .name = "gvvideo-example",
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("gvvideo", gvvideo_module);
    b.installArtifact(lib);
}