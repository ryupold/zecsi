const std = @import("std");
const Allocator = std.mem.Allocator;
const fmt = std.fmt;
const game = @import("./game.zig");
const log = @import("./log.zig");
const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
const r = @import("raylib/raylib.zig");

pub var initFn: fn () anyerror!void = undefined;

//=== DESKTOP =====================================================================================
const updateWindowSizeEveryNthFrame = 30;

/// desktop entry point
pub fn main() anyerror!void {
    // r.SetConfigFlags(.FLAG_WINDOW_RESIZABLE);
    // r.SetExitKey(config.exitKey);
    // r.SetTargetFPS(60);

    var frame: usize = 0;
    var lastWindowSize: struct { w: u32 = 0, h: u32 = 0 } = .{};

    // game start/stop
    log.info("starting game...", .{});

    try initFn();
    defer {
        log.info("stopping game...", .{});
        game.deinit();
    }


    while (!r.WindowShouldClose()) {
        if (frame % updateWindowSizeEveryNthFrame == 0) {
            const newW = @intCast(u32, r.GetScreenWidth());
            const newH = @intCast(u32, r.GetScreenHeight());
            if (newW != lastWindowSize.w or newH != lastWindowSize.h) {
                log.debug("changed screen size {d}x{x}", .{ newW, newH });
                game.setWindowSize(@intCast(usize, newW), @intCast(usize, newH));
                lastWindowSize.w = newW;
                lastWindowSize.h = newH;
            }
        }
        frame += 1;
        try game.mainLoop();
    }
}

//=== WEB =========================================================================================

/// special entry point for Emscripten build, called from src/emscripten/entry.c
export fn emsc_main() callconv(.C) c_int {
    safeMain() catch |err| {
        log.err("ERROR: {?}", .{err});
        return 1;
    };

    return 0;
}

export fn emsc_set_window_size(width: usize, height: usize) callconv(.C) void {
    game.setWindowSize(width, height);
}

fn safeMain() !void {
    const emsdk = @cImport({
        @cDefine("__EMSCRIPTEN__", "1");
        @cInclude("emscripten/emscripten.h");
    });

    try log.info("starting da game  ...", .{});

    try initFn();
    defer {
        log.info("stopping game...", .{});
        game.deinit();
    }

    emsdk.emscripten_set_main_loop(gameLoop, 0, 1);
}

export fn gameLoop() callconv(.C) void {
    game.mainLoop() catch unreachable;
}
