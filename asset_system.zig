const std = @import("std");
const builtin = @import("builtin");
const ECS = @import("ecs/ecs.zig").ECS;
const r = @import("raylib/raylib.zig");
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
    assets: std.StringHashMap(*AssetLink),

    pub fn init(ecs: *ECS) !Self {
        var system = Self{
            .ecs = ecs,
            .assets = std.StringHashMap(*AssetLink).init(ecs.allocator),
        };

        return system;
    }

    pub fn deinit(self: *Self) void {
        var kit = self.assets.keyIterator();
        while (kit.next()) |path| {
            if (self.assets.fetchRemove(path.*)) |kv| {
                kv.value.deinit();
                self.ecs.allocator.destroy(kv.value);
            }
            kit = self.assets.keyIterator();
        }

        self.assets.deinit();
    }

    pub fn get(self: *Self, path: [:0]const u8) ?*AssetLink {
        return self.assets.getPtr(path);
    }

    pub fn loadTexture(self: *Self, path: [:0]const u8) !*AssetLink {
        return self.cacheAssetLink(path, .{ .Texture = r.LoadTexture(path) });
    }

    pub fn loadTextureAtlas(
        self: *Self,
        path: [:0]const u8,
        horizontalCells: u32,
        verticalCells: u32,
    ) !*AssetLink {
        return self.cacheAssetLink(path, .{
            .TextureAtlas = TextureAtlas.load(path, horizontalCells, verticalCells),
        });
    }

    pub fn loadJson(self: *Self, path: [:0]const u8) !*AssetLink {
        return self.cacheAssetLink(path, .{ .Json = try assets.Json.load(path) });
    }

    fn cacheAssetLink(self: *Self, path: [:0]const u8, asset: assets.Asset) !*AssetLink {
        if (self.assets.get(path)) |contained| {
            return contained;
        }

        const ptr = try self.ecs.allocator.create(AssetLink);
        ptr.* = try AssetLink.init(path, asset);
        try self.assets.put(path, ptr);
        return ptr;
    }

    pub fn loadJsonObject(self: *Self, comptime T: type, path: [:0]const u8) !assets.JsonObject(T) {
        return try assets.JsonObject(T).init(try self.loadJson(path));
    }

    pub fn loadJsonObjectOrDefault(self: *Self, path: [:0]const u8, default: anytype) assets.JsonObject(@TypeOf(default)) {
        const T = @TypeOf(default);
        const json = self.loadJson(path) catch {
            return assets.JsonObject(T).initStatic(default);
        };
        return assets.JsonObject(T).initOrDefault(json, default);
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
                const needsReload: bool = asset.*.check() catch |err| {
                    try log.errAlloc(self.ecs.allocator, "Error when checking AssetLink [{s}]: {?}", .{ asset.*.path, err });
                    continue;
                };
                if (needsReload) {
                    std.log.debug("reloading {s}", .{asset.*.path});
                    _ = asset.*.reload() catch |err| try log.errAlloc(self.ecs.allocator, "Error loading AssetLink [{s}]: {?}", .{ asset.*.path, err });
                }
            }
        }
    }
};
