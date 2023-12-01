const std = @import("std");
const fs = std.fs;

fn current_file() []const u8 {
    return @src().file;
}

const cwd = std.fs.path.dirname(current_file()).?;
const sep = std.fs.path.sep_str;
const raylibBindingSrc = cwd ++ sep ++ "src" ++ sep ++ "raylib" ++ sep;
const rayguiBindingSrc = cwd ++ sep ++ "src" ++ sep ++ "raygui" ++ sep;
const raylibSrc = raylibBindingSrc ++ "raylib" ++ sep ++ "src" ++ sep;
const rayguiSrc = rayguiBindingSrc ++ "raygui" ++ sep ++ "src" ++ sep;

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    switch (target.getOsTag()) {
        .wasi, .emscripten => {
            const lib: std.build.StaticLibraryOptions = .{
                .name = "zecsi",
                .root_source_file = std.build.FileSource.relative("src" ++ sep ++ "web.zig"),
                .optimize = mode,
                .target = target,
            };

            try installEmscripten(b, lib);
        },
        else => {
            const exe = b.addExecutable(.{
                .name = "zecsi",
                .root_source_file = std.build.FileSource.relative("src" ++ sep ++ "desktop.zig"),
                .optimize = mode,
                .target = target,
            });

            try addZecsiDesktop(b, exe);

            b.installArtifact(exe);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }
            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        },
    }
}

pub fn addZecsiDesktop(b: *std.build.Builder, exe: *std.build.Step.Compile) !void {
    const raylib = @import("src/raylib/build.zig");
    const raygui = @import("src/raygui/build.zig");
    raylib.addTo(b, exe, exe.target, exe.optimize, .{});
    raygui.addTo(b, exe, exe.target, exe.optimize);

    raylib.linkSystemDependencies(exe);

    exe.addAnonymousModule("zecsi", .{
        .source_file = .{
            .path = cwd ++ sep ++ "src" ++ sep ++ "zecsi.zig",
        },
        .dependencies = &.{
            .{ .name = "raylib", .module = exe.modules.get("raylib").? },
            .{ .name = "raygui", .module = exe.modules.get("raygui").? },
        },
    });
}

pub fn installEmscripten(b: *std.build.Builder, lib: *std.build.Step.Compile) !void {
    std.debug.assert(lib.kind == .lib and lib.linkage == .static);

    const emscriptenSrc = cwd ++ sep ++ "src" ++ sep ++ "raylib" ++ sep ++ "emscripten" ++ sep;
    const webCachedir = b.fmt("{s}{s}web", .{ b.cache_root.path orelse cwd ++ sep ++ "zig-cache", sep });
    const webOutdir = b.fmt("{s}{s}web", .{ b.install_prefix, sep });

    std.log.info("building for emscripten\n", .{});
    if (b.sysroot == null) {
        std.log.err("\n\nUSAGE: Please build with 'zig build -Doptimize=ReleaseSmall -Dtarget=wasm32-wasi --sysroot \"$EMSDK/upstream/emscripten\"'\n\n", .{});
        return error.SysRootExpected;
    }

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

    fs.cwd().makePath(webCachedir) catch {};
    fs.cwd().makePath(webOutdir) catch {};

    const warnings = ""; //-Wall

    const rcoreO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rcore.c", "-o", b.fmt("{s}{s}rcore.o", .{ webCachedir, sep }), "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
    const rshapesO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rshapes.c", "-o", b.fmt("{s}{s}rshapes.o", .{ webCachedir, sep }), "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
    const rtexturesO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rtextures.c", "-o", b.fmt("{s}{s}rtextures.o", .{ webCachedir, sep }), "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
    const rtextO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rtext.c", "-o", b.fmt("{s}{s}rtext.o", .{ webCachedir, sep }), "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
    const rmodelsO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rmodels.c", "-o", b.fmt("{s}{s}rmodels.o", .{ webCachedir, sep }), "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
    const utilsO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "utils.c", "-o", b.fmt("{s}{s}utils.o", .{ webCachedir, sep }), "-Os", warnings, "-DPLATFORM_WEB" });
    const raudioO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "raudio.c", "-o", b.fmt("{s}{s}raudio.o", .{ webCachedir, sep }), "-Os", warnings, "-DPLATFORM_WEB" });

    const libraylibA = b.addSystemCommand(&.{
        emar_path,
        "rcs",
        b.fmt("{s}{s}libraylib.a", .{ webCachedir, sep }),
        b.fmt("{s}{s}rcore.o", .{ webCachedir, sep }),
        b.fmt("{s}{s}rshapes.o", .{ webCachedir, sep }),
        b.fmt("{s}{s}rtextures.o", .{ webCachedir, sep }),
        b.fmt("{s}{s}rtext.o", .{ webCachedir, sep }),
        b.fmt("{s}{s}rmodels.o", .{ webCachedir, sep }),
        b.fmt("{s}{s}utils.o", .{ webCachedir, sep }),
        b.fmt("{s}{s}raudio.o", .{ webCachedir, sep }),
    });
    const emranlib = b.addSystemCommand(&.{
        emranlib_path,
        b.fmt("{s}{s}libraylib.a", .{ webCachedir, sep }),
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
    _ = fs.cwd().statFile(b.fmt("{s}{s}libraylib.a", .{ webCachedir, sep })) catch {
        lib.step.dependOn(&emranlib.step);
    };

    lib.defineCMacro("__EMSCRIPTEN__", null);
    lib.defineCMacro("PLATFORM_WEB", null);
    std.log.info("emscripten include path: {s}", .{include_path});
    lib.addIncludePath(.{ .path = include_path });
    lib.addIncludePath(.{ .path = emscriptenSrc });
    lib.addIncludePath(.{ .path = raylibBindingSrc });
    lib.addIncludePath(.{ .path = rayguiBindingSrc });
    lib.addIncludePath(.{ .path = raylibSrc });
    lib.addIncludePath(.{ .path = rayguiSrc });
    lib.addIncludePath(.{ .path = raylibSrc ++ "extras" ++ sep });
    lib.addAnonymousModule("raylib", .{ .source_file = .{ .path = raylibBindingSrc ++ "raylib.zig" } });
    lib.addAnonymousModule("raygui", .{
        .source_file = .{ .path = rayguiBindingSrc ++ "raygui.zig" },
        .dependencies = &.{
            .{ .name = "raylib", .module = lib.modules.get("raylib").? },
        },
    });
    lib.addAnonymousModule("zecsi", .{
        .source_file = .{
            .path = cwd ++ sep ++ "src" ++ sep ++ "zecsi.zig",
        },
        .dependencies = &.{
            .{ .name = "raylib", .module = lib.modules.get("raylib").? },
        },
    });

    // this installs the lib (described by the 'entry' parameter linked with raylib) to `zig-out/lib`
    b.installArtifact(lib);
    const shell = switch (lib.optimize) {
        .Debug => emscriptenSrc ++ "shell.html",
        else => emscriptenSrc ++ "minshell.html",
    };

    const emcc = b.addSystemCommand(&.{
        emcc_path,
        "-o",
        b.fmt("{s}{s}game.html", .{ webOutdir, sep }),
        emscriptenSrc ++ "entry.c",
        raylibBindingSrc ++ "marshal.c",
        rayguiBindingSrc ++ "raygui_marshal.c",

        // libraryOutputFolder ++ "lib" ++ APP_NAME ++ ".a",
        b.fmt("{s}" ++ sep ++ "lib" ++ sep ++ "lib{s}.a", .{ b.install_prefix, lib.name }),
        "-I.",
        "-I" ++ raylibSrc,
        "-I" ++ rayguiSrc,
        "-I" ++ emscriptenSrc,
        "-I" ++ raylibBindingSrc,
        "-I" ++ rayguiBindingSrc,
        "-L.",
        // "-L" ++ webCachedir,
        b.fmt("-L{s}", .{webCachedir}),
        b.fmt("-L{s}" ++ sep ++ "lib" ++ sep, .{b.install_prefix}),
        "-lraylib",
        b.fmt("-l{s}", .{lib.name}),
        "--shell-file",
        shell,
        "-DPLATFORM_WEB",
        "-DRAYGUI_IMPLEMENTATION",
        "-sUSE_GLFW=3",
        "-sWASM=1",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sWASM_MEM_MAX=512MB", //going higher than that seems not to work on iOS browsers ¯\_(ツ)_/¯
        "-sTOTAL_MEMORY=512MB",
        "-sABORTING_MALLOC=0",
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
        // "-sLLD_REPORT_UNDEFINED",
        "-sERROR_ON_UNDEFINED_SYMBOLS=0",

        // optimizations
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

    std.log.info("\n\nOutput files will be in {s}\n---\ncd {s}\npython -m http.server\n---\n\nbuilding...", .{ webOutdir, webOutdir });
}
