const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("./log.zig");
pub const raylib = @import("./raylib/raylib.zig");
const _ecs = @import("ecs/ecs.zig");
pub const ECS = _ecs.ECS;
const camera = @import("camera_system.zig");

const Self = @This();

var allocator: Allocator = undefined;
var arena: std.heap.ArenaAllocator = undefined;
var windowsInitialized = false;
var screenWidth: usize = 100;
var screenHeight: usize = 100;
var ecsInitialized = false;
var ecs: *_ecs.ECS = undefined;
pub fn getECS() *_ecs.ECS {
    if (!ecsInitialized) @panic("call init first to initialize a game");
    return ecs;
}

pub const GameConfig = struct {
    cwd: []const u8,
    initialWindowSize: ?struct {
        width: usize,
        height: usize,
    } = null,
};

pub fn init(alloc: Allocator, config: GameConfig) !void {
    if (ecsInitialized) return error.AlreadyStarted;
    Self.allocator = alloc;

    ecs = try allocator.create(ECS);
    ecs.* = try _ecs.ECS.init(allocator, allocator);
    ecsInitialized = true;
    if (ecsInitialized) {
        ecs.window.size.x = @intToFloat(f32, screenWidth);
        ecs.window.size.y = @intToFloat(f32, screenWidth);
    }

    if (config.initialWindowSize) |size| {
        setWindowSize(size.width, size.height);
    }
    if (!windowsInitialized) {
        setWindowSize(800, 800);
    }

    _ = try ecs.registerSystem(@import("asset_system.zig").AssetSystem);
    _ = try ecs.registerSystem(@import("grid_placement_system.zig").GridPlacementSystem);
    var cameraSystem = try ecs.registerSystem(camera.CameraSystem);
    cameraSystem.initMouseDrag(camera.CameraMouseDrag{ .button = 2 });
    cameraSystem.initMouseZoomScroll(camera.CameraScrollZoom{ .factor = 0.1 });
    cameraSystem.initTouchZoomAndDrag(camera.TwoFingerZoomAndDrag{ .factor = 0.5 });
}

pub fn setWindowSize(width: usize, height: usize) void {
    screenWidth = width;
    screenHeight = height;
    if (ecsInitialized) {
        ecs.window.size.x = @intToFloat(f32, width);
        ecs.window.size.y = @intToFloat(f32, height);
    }
    if (!windowsInitialized) {
        windowsInitialized = true;
        raylib.InitWindow(@intCast(c_int, screenWidth), @intCast(c_int, screenHeight), "raylib with [zig]");
    } else {
        raylib.SetWindowSize(@intCast(c_int, screenWidth), @intCast(c_int, screenHeight));
    }
}

pub fn mainLoop() !void {
    raylib.BeginDrawing();
    defer raylib.EndDrawing();

    raylib.ClearBackground(raylib.DARKGRAY);
    try ecs.update(raylib.GetFrameTime());

    raylib.EndMode2D();

    raylib.DrawFPS(10, 10);
}

pub fn deinit() void {
    ecs.deinit();
    arena.deinit();
    raylib.CloseWindow();
    allocator.destroy(ecs);
}
