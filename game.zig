const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("log.zig");
const raylib = @import("raylib");
const _ecs = @import("ecs/ecs.v2.zig");
pub const ECS = _ecs.ECS;

const Self = @This();

var allocator: Allocator = undefined;
var arena: std.heap.ArenaAllocator = undefined;
var windowsInitialized = false;
var screenWidth: i32 = 100;
var screenHeight: i32 = 100;
var ecsInitialized = false;
var config: GameConfig = undefined;
var ecs: *_ecs.ECS = undefined;

pub fn getECS() *_ecs.ECS {
    if (!ecsInitialized) @panic("call init first to initialize a game");
    return ecs;
}

pub const GameConfig = struct {
    gameName: [:0]const u8,
    cwd: []const u8,
    initialWindowSize: ?struct {
        width: i32,
        height: i32,
    } = null,
};

pub fn init(alloc: Allocator, c: GameConfig) !void {
    config = c;
    if (ecsInitialized) return error.AlreadyStarted;
    Self.allocator = alloc;

    ecs = try allocator.create(ECS);
    ecs.* = try _ecs.ECS.init(allocator);
    ecsInitialized = true;
    if (ecsInitialized) {
        ecs.window.size.x = @as(f32, @floatFromInt(screenWidth));
        ecs.window.size.y = @as(f32, @floatFromInt(screenWidth));
    }

    if (config.initialWindowSize) |size| {
        setWindowSize(size.width, size.height);
    }
    if (!windowsInitialized) {
        setWindowSize(64, 64);
    }
}

pub fn setWindowSize(width: i32, height: i32) void {
    screenWidth = width;
    screenHeight = height;
    if (ecsInitialized) {
        ecs.window.size.x = @as(f32, @floatFromInt(width));
        ecs.window.size.y = @as(f32, @floatFromInt(height));
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
    ecs.deinit();
    // arena.deinit(); //TODO: find out if this is needed
    raylib.CloseWindow();
    allocator.destroy(ecs);
}
