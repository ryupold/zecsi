const std = @import("std");
const builtin = @import("builtin");
const ECS = @import("ecs/ecs.zig").ECS;
const r = @import("ray/raylib.zig");
const log = @import("log.zig");
const assets = @import("assets.zig");
const utils = @import("utils.zig");
const AssetLink = assets.AssetLink;
const Texture = r.Texture;
const TextureAtlas = assets.TextureAtlas;
const AnimatedTextureAtlas = assets.AnimatedTextureAtlas;

pub const AssetSystem = struct {
    pub const Self = @This();
    ecs: *ECS,
    reloadInterval: utils.Timer = .{
        .time = 2,
        .repeat = true,
    },
    assets: std.StringHashMap(AssetLink),

    pub fn init(ecs: *ECS) !Self {
        var system = Self{
            .ecs = ecs,
            .assets = std.StringHashMap(AssetLink).init(ecs.allocator),
        };

        return system;
    }

    pub fn deinit(self: *Self) void {
        // var vit = self.assets.valueIterator();
        // while (vit.next()) |link| {
        //     link.deinit();
        // }
        self.assets.deinit();
    }

    pub fn get(self: *Self, path: []const u8) ?*AssetLink {
        return self.assets.getPtr(path);
    }

    pub fn loadTexture(self: *Self, path: []const u8) !*AssetLink {
        try self.assets.put(path, try AssetLink.init(
            path,
            .{ .Texture = r.LoadTexture(path) },
        ));
        return self.assets.getPtr(path).?;
    }

    pub fn loadTextureAtlas(
        self: *Self,
        path: []const u8,
        horizontalCells: u32,
        verticalCells: u32,
    ) !*AssetLink {
        try self.assets.put(path, try AssetLink.init(
            path,
            .{ .TextureAtlas = TextureAtlas.load(path, horizontalCells, verticalCells) },
        ));
        return self.assets.getPtr(path).?;
    }

    pub fn loadJson(self: *Self, path: []const u8) !*AssetLink {
        try self.assets.put(path, try AssetLink.init(
            path,
            .{ .Json = try assets.Json.load(path) },
        ));
        return self.assets.getPtr(path).?;
    }

    pub fn loadJsonObject(self: *Self, comptime T: type, path: []const u8) !assets.JsonObject(T) {
        return try assets.JsonObject(T).init(try self.loadJson(path));
    }

    pub fn unload(self: *Self, asset: *AssetLink) void {
        asset.deinit();
        _ = self.assets.remove(asset.path);
    }

    pub fn update(self: *Self, dt: f32) !void {
        if (builtin.mode != .Debug) return;

        if (self.reloadInterval.tick(dt)) {
            var vit = self.assets.valueIterator();
            while (vit.next()) |asset| {
                const needsReload: bool = asset.check() catch |err| {
                    try log.errAlloc(self.ecs.allocator, "Error when checking AssetLink [{s}]: {?}", .{ asset.path, err });
                    continue;
                };
                if (needsReload) {
                    std.log.debug("reloading {s}", .{asset.path});
                    _ = asset.reload() catch |err| try log.errAlloc(self.ecs.allocator, "Error loading AssetLink [{s}]: {?}", .{ asset.path, err });
                }
            }
        }
    }
};
