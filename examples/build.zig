const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ezdxt_module = b.createModule(.{
        .root_source_file = b.path("../ezdxt/src/main.zig"),
    });

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
            .{ .name = "ezdxt", .module = ezdxt_module },
        },
    });

    const lib = b.addExecutable(.{
        .name = "gvvideo-example",
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibrary(lz4_dependency.artifact("lz4"));
    lib.root_module.addImport("gvvideo", gvvideo_module);
    b.installArtifact(lib);
}