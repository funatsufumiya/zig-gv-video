const std = @import("std");

pub fn build(b: *std.Build) void {
    const enable_uncompressed = b.option(bool, "enable-uncompressed", "enable uncompressed functions") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "enable_uncompressed", enable_uncompressed);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lz4_dependency = b.dependency("lz4", .{
        .target = target,
        .optimize = optimize,
    });

    const ziglz4_module = b.createModule(.{
        .root_source_file = b.path("../zig-lz4/src/lib.zig"),
    });

    const gvvideo_module = b.createModule(.{
        .root_source_file = b.path("../src/root.zig"),
        .imports = &.{
            .{ .name = "lz4", .module = ziglz4_module },
        },
    });
    gvvideo_module.addOptions("config", options);
    if(enable_uncompressed){
        gvvideo_module.addIncludePath(b.path("../texture2ddecoder"));
        gvvideo_module.addCSourceFiles(.{
            .files = &.{
                "../texture2ddecoder/bcn.cpp",
            },
        });
    }

    const lib = b.addExecutable(.{
        .name = "gvvideo-example",
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
    });
    if(enable_uncompressed){
        lib.linkSystemLibrary("c++");
        lib.linkLibCpp();
    }
    lib.linkLibrary(lz4_dependency.artifact("lz4"));
    lib.root_module.addImport("gvvideo", gvvideo_module);
    b.installArtifact(lib);
}