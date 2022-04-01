const std = @import("std");
const ECS = @import("ecs/ecs.zig").ECS;
const r = @import("./raylib/raylib.zig");
const log = @import("log.zig");
const camera = @import("camera_system.zig");
const CameraSystem = camera.CameraSystem;
const screenToWorld = camera.screenToWorld;
const builtin = @import("builtin");

pub const Vector2 = if (!@import("builtin").is_test) r.Vector2 else struct { x: f32, y: f32 };

pub const GridPosition = struct {
    x: i32,
    y: i32,

    /// [0] [1] [2]
    /// [7] [X] [3]
    /// [6] [5] [4]
    pub fn neigbours(self: @This()) [8]GridPosition {
        const x = self.x;
        const y = self.y;
        return [_]GridPosition{
            .{ .x = x - 1, .y = y - 1 },
            .{ .x = x, .y = y - 1 },
            .{ .x = x + 1, .y = y - 1 },
            .{ .x = x + 1, .y = y },
            .{ .x = x + 1, .y = y + 1 },
            .{ .x = x, .y = y + 1 },
            .{ .x = x - 1, .y = y + 1 },
            .{ .x = x - 1, .y = y },
        };
    }

    pub fn add(self: @This(), other: @This()) @This() {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
    pub fn sub(self: @This(), other: @This()) @This() {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }
    pub fn eql(self: @This(), other: @This()) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const GridPlacementSystem = struct {
    pub const cellSize: f32 = 64;
    var random = std.rand.DefaultPrng.init(0);
    ecs: *ECS,
    rng: std.rand.Random,
    isGridVisible: bool = builtin.mode == .Debug,
    cameraSystem: ?*CameraSystem = null,

    pub fn init(ecs: *ECS) !@This() {
        return @This(){
            .ecs = ecs,
            .rng = random.random(),
        };
    }

    pub fn deinit(_: *@This()) void {}

    pub fn update(self: *@This(), dt: f32) !void {
        if (r.IsKeyReleased(.KEY_G))
            self.isGridVisible = !self.isGridVisible;

        self.drawGrid();

        _ = self;
        _ = dt;
    }

    fn drawGrid(self: *@This()) void {
        if (!self.isGridVisible) return;

        if (self.cameraSystem == null)
            self.cameraSystem = self.ecs.getSystem(CameraSystem);

        const min = screenToWorld(.{
            .x = -cellSize * 2,
            .y = -cellSize * 2,
        });
        const max = screenToWorld(.{
            .x = self.ecs.window.size.x + cellSize * 2,
            .y = self.ecs.window.size.y + cellSize * 2,
        });
        const scale = 1 / camera.zoom();
        const halfCell: f32 = cellSize / 2;

        //vertical lines
        var x: f32 = min.x;
        while (x <= max.x) : (x += cellSize) {
            const from = toWorldPosition(toGridPosition(Vector2{ .x = x, .y = min.y }))
                .add(.{ .x = halfCell, .y = 0 });
            const to = toWorldPosition(toGridPosition(Vector2{ .x = x, .y = max.y }))
                .add(.{ .x = halfCell, .y = 0 });
            r.DrawLineEx(
                from,
                to,
                scale,
                r.GREEN.set(.{ .a = @floatToInt(u8, std.math.clamp(100 / scale, 0, 255)) }),
            );
        }

        //horizontal lines
        var y: f32 = min.y;
        while (y <= max.y) : (y += cellSize) {
            const from = toWorldPosition(toGridPosition(Vector2{ .x = min.x, .y = y + halfCell }))
                .add(.{ .x = 0, .y = halfCell });
            const to = toWorldPosition(toGridPosition(Vector2{ .x = max.x, .y = y + halfCell }))
                .add(.{ .x = 0, .y = halfCell });
            r.DrawLineEx(
                from,
                to,
                scale,
                r.GREEN.set(.{ .a = @floatToInt(u8, std.math.clamp(100 / scale, 0, 255)) }),
            );
        }
    }
};

pub fn toGridPosition(pos: Vector2) GridPosition {
    const xRounder: f32 = if (pos.x < 0) -0.5 else 0.5;
    const yRounder: f32 = if (pos.y < 0) -0.5 else 0.5;
    return .{
        .x = @floatToInt(i32, pos.x / GridPlacementSystem.cellSize + xRounder),
        .y = @floatToInt(i32, pos.y / GridPlacementSystem.cellSize + yRounder),
    };
}

pub fn toWorldPosition(pos: GridPosition) Vector2 {
    return .{
        .x = @intToFloat(f32, pos.x) * GridPlacementSystem.cellSize,
        .y = @intToFloat(f32, pos.y) * GridPlacementSystem.cellSize,
    };
}
