const std = @import("std");
const fs = std.fs;
const utf8 = @import("src/utf8.zig");

const raylibSrc = "raylib/src/";
const webOutdir = "zig-out/web/";

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    switch (target.toTarget().os.tag) {
        .wasi, .emscripten, .freestanding => {
            std.log.info("building for emscripten\n", .{});
            if (b.sysroot == null) {
                std.log.err("Please build with 'zig build -Dtarget=wasm32-wasi --sysroot \"$EMSDK/upstream/emscripten\"", .{});
                @panic("error.SysRootExpected");
            }
            const lib = b.addStaticLibrary("zecsi", "src/web.zig");
            lib.addIncludeDir("./raylib/src/");

            const outdir = webOutdir;

            const emcc_file = switch (b.host.target.os.tag) {
                .windows => "emcc.bat",
                else => "emcc",
            };
            const emar_file = switch (b.host.target.os.tag) {
                .windows => "emar.bat",
                else => "emar",
            };
            const emranlib_file = switch (b.host.target.os.tag) {
                .windows => "emranlib.bat",
                else => "emranlib",
            };

            const emcc_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, emcc_file });
            defer b.allocator.free(emcc_path);
            const emranlib_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, emranlib_file });
            defer b.allocator.free(emranlib_path);
            const emar_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, emar_file });
            defer b.allocator.free(emar_path);
            const include_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, "cache", "sysroot", "include" });
            defer b.allocator.free(include_path);

            fs.cwd().makePath(outdir) catch {};

            const warnings = ""; //-Wall

            const rcoreO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rcore.c", "-o", outdir ++ "rcore.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const rshapesO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rshapes.c", "-o", outdir ++ "rshapes.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const rtexturesO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rtextures.c", "-o", outdir ++ "rtextures.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const rtextO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rtext.c", "-o", outdir ++ "rtext.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const rmodelsO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rmodels.c", "-o", outdir ++ "rmodels.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const utilsO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "utils.c", "-o", outdir ++ "utils.o", "-Os", warnings, "-DPLATFORM_WEB" });
            const raudioO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "raudio.c", "-o", outdir ++ "raudio.o", "-Os", warnings, "-DPLATFORM_WEB" });
            const libraylibA = b.addSystemCommand(&.{
                emar_path,
                "rcs",
                outdir ++ "libraylib.a",
                outdir ++ "rcore.o",
                outdir ++ "rshapes.o",
                outdir ++ "rtextures.o",
                outdir ++ "rtext.o",
                outdir ++ "rmodels.o",
                outdir ++ "utils.o",
                outdir ++ "raudio.o",
            });
            const emranlib = b.addSystemCommand(&.{
                emranlib_path,
                outdir ++ "libraylib.a",
            });

            libraylibA.step.dependOn(&rcoreO.step);
            libraylibA.step.dependOn(&rshapesO.step);
            libraylibA.step.dependOn(&rtexturesO.step);
            libraylibA.step.dependOn(&rtextO.step);
            libraylibA.step.dependOn(&rmodelsO.step);
            libraylibA.step.dependOn(&utilsO.step);
            libraylibA.step.dependOn(&raudioO.step);
            emranlib.step.dependOn(&libraylibA.step);

            //only build raylib if not already there
            _ = fs.cwd().statFile(outdir ++ "libraylib.a") catch {
                lib.step.dependOn(&emranlib.step);
            };

            lib.setTarget(target);
            lib.setBuildMode(mode);
            lib.defineCMacro("__EMSCRIPTEN__", "1");
            std.log.info("emscripten include path: {s}", .{include_path});
            lib.addIncludeDir(include_path);
            lib.addIncludeDir("src/emscripten");

            lib.setOutputDir(outdir);
            lib.install();

            const shell = switch (mode) {
                .Debug => "src/emscripten/shell.html",
                else => "src/emscripten/minshell.html",
            };

            const emcc = b.addSystemCommand(&.{
                emcc_path,
                "-o",
                outdir ++ "game.html",
                "src/emscripten/entry.c",
                "src/emscripten/raylib_marshall.c",
                // outdir ++ "libraylib.a",
                outdir ++ "libzecsi.a",
                "-I.",
                "-I" ++ raylibSrc,
                "-I" ++ raylibSrc ++ "emscripten/",
                "-L.",
                "-L" ++ outdir,
                "-lraylib",
                "-lzecsi",
                "--shell-file",
                shell,
                "-DPLATFORM_WEB",
                "-sUSE_GLFW=3",
                // "-sWASM=0",
                "-sALLOW_MEMORY_GROWTH=1",
                //"-sTOTAL_MEMORY=1024MB",
                "-sASYNCIFY",
                "-sFORCE_FILESYSTEM=1",
                "-sASSERTIONS=1",
                "--memory-init-file",
                "0",
                "--preload-file",
                "assets",
                "--source-map-base",
                "-O1",
                "-Os",
                // "-sUSE_PTHREADS=1",
                // "--profiling",
                // "-sTOTAL_STACK=128MB",
                // "-sMALLOC='emmalloc'",
                // "--no-entry",
                "-sEXPORTED_FUNCTIONS=['_malloc','_free','_main', '_emsc_main','_emsc_set_window_size']",
                "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap",
            });

            emcc.step.dependOn(&lib.step);

            b.getInstallStep().dependOn(&emcc.step);
            //-------------------------------------------------------------------------------------
        },
        else => {
            std.log.info("building for desktop (windows, macos, linux)\n", .{});
            const exe = b.addStaticLibrary("zecsi", "src/desktop.zig");
            exe.setTarget(target);
            exe.setBuildMode(mode);

            const rayBuild = @import("./raylib/src/build.zig");
            const raylib = rayBuild.addRaylib(b, target);
            exe.linkLibrary(raylib);
            exe.addIncludeDir("./raylib/src/");
            exe.addIncludeDir("./src/emscripten/");
            exe.addCSourceFile("./src/emscripten/raylib_marshall.c", &.{});

            switch (raylib.target.toTarget().os.tag) {
                //dunno why but macos target needs sometimes 2 tries to build
                .macos => {
                    exe.linkFramework("Foundation");
                    exe.linkFramework("Cocoa");
                    exe.linkFramework("OpenGL");
                    exe.linkFramework("CoreAudio");
                    exe.linkFramework("CoreVideo");
                    exe.linkFramework("IOKit");
                },
                else => {},
            }

            exe.linkLibC();
            exe.install();

            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }
        },
    }


    const exe_tests = b.addTest("src/tests.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&exe_tests.step);
}

pub const Pkg = struct {
    
};
