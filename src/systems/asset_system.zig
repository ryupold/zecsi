const std = @import("std");
const builtin = @import("builtin");
const ECS = @import("../ecs/ecs.v2.zig").ECS;
const r = @import("raylib");
const log = @import("../log.zig");
const assets = @import("../assets.zig");
const utils = @import("../utils.zig");

const Texture = r.Texture;
const TextureAtlas = assets.TextureAtlas;

const AssetLink = struct {
    ptr: usize,
    check: assets.CheckFn,
    deinit: assets.DeinitFn,
};

pub const AssetSystem = struct {
    const This = @This();
    ecs: *ECS,
    reloadInterval: utils.Timer = .{
        .time = 2,
        .repeat = true,
    },
    assets: std.StringHashMap(AssetLink),

    pub fn init(ecs: *ECS) !This {
        const system = This{
            .ecs = ecs,
            .assets = std.StringHashMap(AssetLink).init(ecs.allocator),
        };

        return system;
    }

    pub fn deinit(this: *This) void {
        var kit = this.assets.keyIterator();
        while (kit.next()) |path| {
            if (this.assets.fetchRemove(path.*)) |kv| {
                kv.value.deinit(this.ecs.allocator, kv.value.ptr);
            }
            kit = this.assets.keyIterator();
        }

        this.assets.deinit();
    }

    pub fn get(this: *This, comptime T: type, path: [:0]const u8) ?*T {
        switch (T) {
            assets.Texture, assets.TextureAtlas, assets.Json(T) => {},
            else => @compileError("must be a valid asset type, but was " ++ @typeName(T)),
        }

        if (this.assets.get(path)) |asset| {
            return @ptrFromInt(asset.ptr);
        }
        return null;
    }

    pub fn loadJsonFromFile(this: *This, comptime T: type, path: [:0]const u8) !*assets.Json(T) {
        if (this.assets.get(path)) |contained| {
            return @ptrFromInt(contained.ptr);
        }
        const obj = try assets.Json(T).initFromFile(this.ecs.allocator, path);

        try this.assets.put(path, AssetLink{
            .ptr = @intFromPtr(obj),
            .check = assets.Json(T).checkFn,
            .deinit = assets.Json(T).deinitFn,
        });
        return obj;
    }

    pub fn loadTexture(this: *This, path: [:0]const u8) !*assets.Texture {
        if (this.assets.get(path)) |contained| {
            return @ptrFromInt(contained.ptr);
        }

        const tex = try assets.Texture.init(this.ecs.allocator, path);
        try this.assets.put(path, AssetLink{
            .ptr = @intFromPtr(tex),
            .check = assets.Texture.checkFn,
            .deinit = assets.Texture.deinitFn,
        });
        return tex;
    }

    pub fn loadTextureAtlas(
        this: *This,
        path: [:0]const u8,
        horizontalCells: u32,
        verticalCells: u32,
    ) !*assets.TextureAtlas {
        if (this.assets.get(path)) |contained| {
            return @ptrFromInt(contained.ptr);
        }

        const atlas = try assets.TextureAtlas.init(
            this.ecs.allocator,
            path,
            horizontalCells,
            verticalCells,
        );
        try this.assets.put(path, AssetLink{
            .ptr = @intFromPtr(atlas),
            .check = assets.TextureAtlas.checkFn,
            .deinit = assets.TextureAtlas.deinitFn,
        });
        return atlas;
    }

    // pub fn loadAnimatedTextureAtlas(
    //     this: *This,
    //     path: [:0]const u8,
    //     horizontalCells: u32,
    //     verticalCells: u32,
    //     count: u32,
    //     time: f32,
    //     loop: bool,
    // ) !*assets.AnimatedTextureAtlas {
    //     if (this.assets.get(path)) |contained| {
    //         return @ptrFromInt(contained.ptr);
    //     }

    //     const atlas = try assets.AnimatedTextureAtlas.init(
    //         this.ecs.allocator,
    //         path,
    //         horizontalCells,
    //         verticalCells,
    //         count,
    //         time,
    //         loop,
    //     );
    //     try this.assets.put(path, AssetLink{
    //         .ptr = @intFromPtr(atlas),
    //         .check = assets.TextureAtlas.checkFn,
    //         .deinit = assets.TextureAtlas.deinitFn,
    //     });
    //     return atlas;
    // }

    /// remove asset link from cache and deinit it
    /// O(1)
    pub fn unload(this: *This, path: []const u8) void {
        if (this.assets.get(path)) |asset| {
            asset.deinit(this.ecs.allocator, asset.ptr);
            _ = this.assets.remove(path);
        }
    }

    /// remove asset link from cache and deinit it
    /// O(n)
    pub fn unloadLink(this: *This, asset: AssetLink) void {
        var it = this.assets.iterator();
        while (it.next()) |e| {
            if (asset.ptr == e.value_ptr.ptr) {
                asset.deinit(this.ecs.allocator, asset.ptr);
                _ = this.assets.remove(e.key_ptr.*);
                return;
            }
        }
    }

    pub fn update(this: *This, dt: f32) !void {
        if (builtin.mode != .Debug) return;

        if (this.reloadInterval.tick(dt)) {
            var it = this.assets.iterator();
            while (it.next()) |asset| {
                const wasReloaded: bool = asset.value_ptr.check(this.ecs.allocator, asset.value_ptr.ptr) catch |err| {
                    try log.errAlloc(this.ecs.allocator, "Error when checking AssetLink [{s}]: {?}", .{ asset.key_ptr, err });
                    continue;
                };
                if (wasReloaded) {
                    std.log.debug("reloaded {s}", .{asset.key_ptr});
                }
            }
        }
    }
};
