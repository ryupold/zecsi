const std = @import("std");
const ECS = @import("ecs/ecs.zig").ECS;
const r = @import("ray/raylib.zig");
const log = @import("log.zig");
const camera = @import("camera_system.zig");
const CameraSystem = camera.CameraSystem;
const screenToWorld = camera.screenToWorld;
const builtin = @import("builtin");
const AssetSystem = @import("asset_system.zig").AssetSystem;
const AssetLink = @import("assets.zig").AssetLink;
const JsonObject = @import("assets.zig").JsonObject;

pub const Vector2 = r.Vector2;

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

const GridConfig = struct {
    cellSize: f32,
};

pub const GridPlacementSystem = struct {
    ecs: *ECS,
    isGridVisible: bool = builtin.mode == .Debug,
    cameraSystem: ?*CameraSystem = null,
    config: JsonObject(GridConfig),

    pub fn init(ecs: *ECS) !@This() {
        const ass = ecs.getSystem(AssetSystem).?;

        return @This(){
            .ecs = ecs,
            .config = try ass.loadJsonObjectOrDefault(
                "assets/data/grid_config.json",
                GridConfig{ .cellSize = 64 },
            ),
        };
    }

    pub fn deinit(_: *@This()) void {}

    pub fn update(self: *@This(), dt: f32) !void {
        if (r.IsKeyReleased(r.KEY_G)) {
            self.isGridVisible = !self.isGridVisible;
        }

        self.drawGrid();

        _ = self;
        _ = dt;
    }

    fn drawGrid(self: *@This()) void {
        if (!self.isGridVisible) return;

        if (self.cameraSystem == null)
            self.cameraSystem = self.ecs.getSystem(CameraSystem);

        const min = screenToWorld(.{
            .x = -self.cellSize() * 2,
            .y = -self.cellSize() * 2,
        });
        const max = screenToWorld(.{
            .x = self.ecs.window.size.x + self.cellSize() * 2,
            .y = self.ecs.window.size.y + self.cellSize() * 2,
        });
        const scale = 1 / camera.zoom();
        const halfCell: f32 = self.cellSize() / 2;

        //vertical lines
        var x: f32 = min.x;
        while (x <= max.x) : (x += self.cellSize()) {
            const from = self.toWorldPosition(self.toGridPosition(Vector2{ .x = x, .y = min.y }))
                .add(.{ .x = halfCell, .y = 0 });
            const to = self.toWorldPosition(self.toGridPosition(Vector2{ .x = x, .y = max.y }))
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
        while (y <= max.y) : (y += self.cellSize()) {
            const from = self.toWorldPosition(self.toGridPosition(Vector2{ .x = min.x, .y = y + halfCell }))
                .add(.{ .x = 0, .y = halfCell });
            const to = self.toWorldPosition(self.toGridPosition(Vector2{ .x = max.x, .y = y + halfCell }))
                .add(.{ .x = 0, .y = halfCell });
            r.DrawLineEx(
                from,
                to,
                scale,
                r.GREEN.set(.{ .a = @floatToInt(u8, std.math.clamp(100 / scale, 0, 255)) }),
            );
        }
    }

    pub fn cellSize(self: *@This()) f32 {
        return self.config.get().cellSize;
    }

    pub fn toGridLen(self: *@This(), l: f32) i32 {
        const rounder: f32 = if (l < 0) -0.5 else 0.5;
        return @floatToInt(i32, l / self.cellSize() + rounder);
    }

    pub fn toWorldLen(self: *@This(), l: i32) f32 {
        return @intToFloat(f32, l) * self.cellSize();
    }

    pub fn toGridPosition(self: *@This(), pos: Vector2) GridPosition {
        const xRounder: f32 = if (pos.x < 0) -0.5 else 0.5;
        const yRounder: f32 = if (pos.y < 0) -0.5 else 0.5;
        return .{
            .x = @floatToInt(i32, pos.x / self.cellSize() + xRounder),
            .y = @floatToInt(i32, pos.y / self.cellSize() + yRounder),
        };
    }

    /// returns center world pos of the grid cell 
    /// (same as toWorldPositionEx(pos, .{.x=0.5, .y=0.5}))
    pub fn toWorldPosition(self: *@This(), pos: GridPosition) Vector2 {
        const cs = self.cellSize();
        return .{
            .x = @intToFloat(f32, pos.x) * cs,
            .y = @intToFloat(f32, pos.y) * cs,
        };
    }

    /// returns adjusted to an origin (0-1) of cellSize
    pub fn toWorldPositionEx(self: *@This(), pos: GridPosition, origin: Vector2) Vector2 {
        const cs = self.cellSize();
        const o = origin.scale(cs);
        return .{
            .x = (@intToFloat(f32, pos.x) * cs - cs / 2) + o.x,
            .y = (@intToFloat(f32, pos.y) * cs - cs / 2) + o.y,
        };
    }
};
