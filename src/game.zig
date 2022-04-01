const std = @import("std");
const Allocator = std.mem.Allocator;
const fmt = std.fmt;
const log = @import("./log.zig");
const r = @import("./raylib/raylib.zig");
const _ecs = @import("ecs/ecs.zig");
const ECS = _ecs.ECS;
const camera = @import("camera_system.zig");

const Self = @This();

var allocator: Allocator;
var arena: std.heap.ArenaAllocator = undefined;
var windowsInitialized = false;
var screenWidth: usize = 100;
var screenHeight: usize = 100;
var ecsInitialized = false;
var ecs: *_ecs.ECS = undefined;

pub const GameConfig = struct {
    cwd: []const u8,
    initialWindowSize: ?struct {
        width: usize,
        height: usize,
    } = null,
};

pub fn init(allocator: Allocator, config: GameConfig) !void {
    if(ecsInitialized) return error.AlreadyStarted;
    Self.allocator = allocator;

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
        r.InitWindow(@intCast(c_int, screenWidth), @intCast(c_int, screenHeight), "raylib with [zig]");
    } else {
        r.SetWindowSize(@intCast(c_int, screenWidth), @intCast(c_int, screenHeight));
    }
}

pub fn mainLoop() !void {
    r.BeginDrawing();
    defer r.EndDrawing();

    r.ClearBackground(r.DARKGRAY);
    try ecs.update(r.GetFrameTime());

    r.EndMode2D();

    r.DrawFPS(10, 10);
}

pub fn deinit() void {
    ecs.deinit();
    arena.deinit();
    r.CloseWindow();
    allocator.destroy(ecs);
}
