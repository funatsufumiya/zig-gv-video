const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const enable_uncompressed = b.option(bool, "enable-uncompressed", "enable uncompressed functions (using DXT/BC decoder)") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "enable_uncompressed", enable_uncompressed);

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lz4_dependency = b.dependency("lz4", .{
        .target = target,
        .optimize = optimize,
    });

    const ziglz4_module = b.createModule(.{
        .root_source_file = b.path("zig-lz4/src/lib.zig"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "zig-gv-video",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    if(enable_uncompressed){
        lib.root_module.addIncludePath(b.path("texture2ddecoder"));
        lib.addIncludePath(b.path("texture2ddecoder"));
        lib.root_module.addCSourceFiles(.{
            .files = &.{
                "texture2ddecoder/bcn.cpp",
            },
        });
        lib.linkSystemLibrary("c++");
        lib.linkLibCpp();
    }
    lib.linkLibrary(lz4_dependency.artifact("lz4"));
    lib.root_module.addImport("lz4", ziglz4_module);
    lib.root_module.addOptions("config", options);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    if(enable_uncompressed){
        lib_unit_tests.root_module.addIncludePath(b.path("texture2ddecoder"));
        lib_unit_tests.addIncludePath(b.path("texture2ddecoder"));
        lib_unit_tests.addCSourceFiles(.{
            .files = &.{
                "texture2ddecoder/bcn.cpp",
            },
        });
        lib_unit_tests.linkSystemLibrary("c++");
        lib_unit_tests.linkLibCpp();
    }
    lib_unit_tests.linkLibrary(lz4_dependency.artifact("lz4"));
    lib_unit_tests.root_module.addImport("lz4", ziglz4_module);
    lib_unit_tests.root_module.addOptions("config", options);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
