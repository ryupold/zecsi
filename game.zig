const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("./log.zig");
const raylib = @import("raylib/raylib.zig");
const _ecs = @import("ecs/ecs.zig");
pub const ECS = _ecs.ECS;
const camera = @import("camera_system.zig");

const Self = @This();

pub var isInitialized = false;
var _allocator: Allocator = undefined;
var arena: std.heap.ArenaAllocator = undefined;
var windowsInitialized = false;
var screenWidth: i32 = 100;
var screenHeight: i32 = 100;
var ecs: *_ecs.ECS = undefined;
var gameEntryPoint: fn (ecs: *ECS) anyerror!void = undefined;
var cleanup: ?fn (ecs: *ECS) anyerror!void = null;
var config: GameConfig = undefined;

pub fn getECS() *_ecs.ECS {
    if (!isInitialized) @panic("call init first to initialize a game");
    return ecs;
}

pub const GameConfig = struct {
    gameName: [:0]const u8,
    cwd: []const u8,
    initialWindowSize: ?struct {
        width: i32,
        height: i32,
    } = null,
    exitKey: raylib.KeyboardKey = .KEY_ESCAPE,
};

pub fn init(
    allocator: Allocator,
    initialConfig: GameConfig,
    start: fn (ecs: *ECS) anyerror!void,
    stop: ?fn (ecs: *ECS) anyerror!void,
) !void {
    if (isInitialized) return error.AlreadyStarted;
    _allocator = allocator;
    config = initialConfig;
    gameEntryPoint = start;
    cleanup = stop;

    ecs = try _allocator.create(ECS);
    ecs.* = try _ecs.ECS.init(_allocator, _allocator);
    isInitialized = true;
    if (isInitialized) {
        ecs.window.size.x = @intToFloat(f32, screenWidth);
        ecs.window.size.y = @intToFloat(f32, screenWidth);
    }

    if (config.initialWindowSize) |size| {
        setWindowSize(size.width, size.height);
    }
    if (!windowsInitialized) {
        setWindowSize(64, 64);
    }

    try gameEntryPoint(ecs);
}

pub fn setWindowSize(width: i32, height: i32) void {
    screenWidth = width;
    screenHeight = height;
    if (isInitialized) {
        ecs.window.size.x = @intToFloat(f32, width);
        ecs.window.size.y = @intToFloat(f32, height);
    }

    if (!windowsInitialized) {
        windowsInitialized = true;
        raylib.InitWindow(screenWidth, screenHeight, config.gameName);
    } else {
        raylib.SetWindowSize(screenWidth, screenHeight);
    }
}

pub fn mainLoop() !void {
    {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();

        raylib.ClearBackground(raylib.DARKGRAY);
        try ecs.update(raylib.GetFrameTime());
    }

    //TODO: call system.ui for each system in ecs
}

pub fn deinit() void {
    if (cleanup) |c| {
        c(ecs) catch |err| @panic(std.fmt.allocPrint(_allocator, "{?}", .{err}));
    }
    ecs.deinit();
    raylib.CloseWindow();
    _allocator.destroy(ecs);
}
