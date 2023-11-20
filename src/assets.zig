const std = @import("std");
const builtin = @import("builtin");
const r = @import("raylib");
const log = @import("log.zig");

pub const TextureAtlas = struct {
    tex: r.Texture2D,
    count: struct {
        x: u32 = 1,
        y: u32 = 1,
    } = .{ .x = 1, .y = 1 },
    cell: struct {
        width: f32,
        height: f32,
    },

    pub fn load(
        path: [:0]const u8,
        horizontalCells: u32,
        verticalCells: u32,
    ) @This() {
        return @This().init(r.LoadTexture(path), horizontalCells, verticalCells);
    }

    pub fn init(
        tex: r.Texture2D,
        horizontalCells: u32,
        verticalCells: u32,
    ) @This() {
        return .{
            .tex = tex,
            .count = .{ .x = horizontalCells, .y = verticalCells },
            .cell = .{
                .width = @as(f32, @floatFromInt(@divFloor(@as(u32, @intCast(tex.width)), horizontalCells))),
                .height = @as(f32, @floatFromInt(@divFloor(@as(u32, @intCast(tex.height)), verticalCells))),
            },
        };
    }

    pub fn drawEasy(
        self: @This(),
        index: u32,
        pos: r.Vector2,
        size: r.Vector2,
    ) void {
        const dest: r.Rectangle = .{
            .x = pos.x - size.x / 2.0,
            .y = pos.y - size.y / 2.0,
            .width = size.x,
            .height = size.y,
        };
        const fixedIndex = @mod(index, self.count.x * self.count.y);
        const cellX = @mod(fixedIndex, self.count.x);
        const cellY = @divFloor(fixedIndex, self.count.x);
        self.draw(cellX, cellY, dest, r.Vector2.zero(), 0, r.WHITE);
    }

    pub fn draw(
        self: @This(),
        cellX: u32,
        cellY: u32,
        dest: r.Rectangle,
        origin: r.Vector2,
        rotation: f32,
        tint: r.Color,
    ) void {
        const fX = @as(f32, @floatFromInt(cellX));
        const fY = @as(f32, @floatFromInt(cellY));

        const sourceRec: r.Rectangle = .{
            .x = fX * self.cell.width,
            .y = fY * self.cell.height,
            .width = self.cell.width,
            .height = self.cell.height,
        };
        r.DrawTexturePro(self.tex, sourceRec, dest, origin, rotation, tint);
    }

    pub fn unload(self: @This()) void {
        r.UnloadTexture(self.tex);
    }
};

pub const AnimatedTextureAtlas = struct {
    time: f32,
    index: u32 = 0,
    count: u32,
    loop: bool,
    atlas: *AssetLink,
    timePassed: f32 = 0,

    pub fn init(
        asset: *AssetLink,
        count: u32,
        time: f32,
        loop: bool,
    ) @This() {
        return .{
            .atlas = asset,
            .time = time,
            .loop = loop,
            .count = count,
        };
    }

    pub fn tick(self: *@This(), dt: f32) void {
        if (self.loop) {
            self.timePassed += dt;
            if (self.timePassed >= self.time)
                self.timePassed = std.math.clamp(self.timePassed - self.time, 0, self.time);
        } else {
            self.timePassed = std.math.clamp(self.timePassed + dt, 0, self.time);
        }

        if (self.atlas.asset != .TextureAtlas) {
            std.log.warn("{s} is not a TextureAtlas", .{self.atlas.path});
            return;
        }

        const percent = self.timePassed / self.time;
        self.index = @as(
            u32,
            @intFromFloat(percent * @as(f32, @floatFromInt(self.count - 1))),
        );
    }

    pub fn draw(
        self: @This(),
        dest: r.Rectangle,
        origin: r.Vector2,
        rotation: f32,
        tint: r.Color,
    ) void {
        const cellX = self.index % self.atlas.asset.TextureAtlas.count.x;
        const cellY = self.index / self.atlas.asset.TextureAtlas.count.x;
        self.atlas.asset.TextureAtlas.draw(cellX, cellY, dest, origin, rotation, tint);
    }
};

///dont use Json directly. Instead get a 'JsonObject(T)' for easier usage
pub const Json = struct {
    data: []const u8,

    /// loads a json string from file
    /// use 'deinit' to unload the data (reload does that automatically)
    pub fn load(path: [:0]const u8) !@This() {
        const data = try r.LoadFileData(path);
        if (data.len == 0) return error.UnexpectedEndOfJson;

        return @This(){ .data = data };
    }

    pub fn deinit(self: *@This()) void {
        r.UnloadFileData(self.data);
        self.data = undefined;
    }

    pub fn reload(self: *@This(), path: [:0]const u8) !void {
        self.deinit();
        self.* = try @This().load(path);
    }

    pub fn parse(self: @This(), comptime T: type, allocator: std.mem.Allocator) !Parsed(T) {
        return try std.json.parseFromSlice(T, allocator, self.data, .{
            .ignore_unknown_fields = true,
            .duplicate_field_behavior = .use_last,
        });
    }
};

const Parsed = std.json.Parsed;
pub fn JsonObject(comptime T: type) type {
    return struct {
        object: Parsed(T) = undefined,
        json: *AssetLink,
        static: bool = false,
        modTime: i128 = 0,

        pub fn init(json: *AssetLink) !@This() {
            return @This(){
                .json = json,
                .object = try json.asset.Json.parse(T, json.allocator),
            };
        }

        pub fn initOrDefault(json: *AssetLink, default: T) !@This() {
            const obj = json.asset.Json.parse(T, json.allocator) catch |err| {
                log.err("cannot load {s}: {?}\nusing default value instead", .{ json.path, err });
                const tmp = try std.json.stringifyAlloc(json.allocator, default, .{});
                defer json.allocator.free(tmp);

                return @This(){
                    .json = json,
                    .object = try std.json.parseFromSlice(T, json.allocator, tmp, .{
                        .ignore_unknown_fields = true,
                        .duplicate_field_behavior = .use_last,
                    }),
                    .static = true,
                };
            };
            return @This(){
                .json = json,
                .object = obj,
            };
        }

        pub fn initStatic(allocator: std.mem.Allocator, default: T) !@This() {
            const tmp = try std.json.stringifyAlloc(allocator, default, .{});
            defer allocator.free(tmp);

            return @This(){
                .object = try std.json.parseFromSlice(T, allocator, tmp, .{
                    .ignore_unknown_fields = true,
                    .duplicate_field_behavior = .use_last,
                }),
                .static = true,
                .json = AssetLink.static(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.object.deinit();
        }

        pub fn get(self: *@This()) T {
            if (builtin.mode != .Debug or self.static) {
                return self.object.value; //no asset reloading in release mode
            }

            if (self.modTime != self.json.loadedModTime) {
                self.object.deinit();
                self.object = self.json.asset.Json.parse(T, self.json.allocator) catch |err| {
                    log.err("cannot load {s}: {?}", .{ self.json.path, err });
                    return std.mem.zeroes(T);
                };
                self.modTime = self.json.loadedModTime;
            }
            return self.object.value;
        }
    };
}

pub const Asset = union(enum) {
    Texture2D: r.Texture2D,
    TextureAtlas: TextureAtlas,
    Json: Json,
    Static: void,
};

pub const AssetLink = struct {
    allocator: std.mem.Allocator,
    path: [:0]const u8,
    asset: Asset,
    loadedModTime: i128 = 0,
    currentModTime: i128 = 0,

    pub fn init(allocator: std.mem.Allocator, path: [:0]const u8, asset: Asset) !@This() {
        var this: @This() = .{
            .allocator = allocator,
            .path = path,
            .asset = asset,
            .loadedModTime = std.time.nanoTimestamp(),
        };

        _ = try this.check();
        this.loadedModTime = this.currentModTime;
        return this;
    }

    var _static: ?*@This() = null;
    /// TODO: remove?
    pub fn static(allocator: std.mem.Allocator) *@This() {
        if (_static) |s| {
            return s;
        }
        _static = allocator.create(@This()) catch unreachable;
        _static.?.* = @This(){
            .allocator = allocator,
            .path = "",
            .asset = .{ .Static = {} },
            .loadedModTime = std.time.nanoTimestamp(),
        };
        return _static.?;
    }

    pub fn deinit(self: *@This()) void {
        defer if (self == _static) {
            self.allocator.destroy(_static.?);
            _static = null;
        };
        defer self.asset = undefined;
        switch (self.asset) {
            .Texture2D => {
                r.UnloadTexture(self.asset.Texture2D);
            },
            .TextureAtlas => {
                self.asset.TextureAtlas.unload();
            },
            .Json => {
                self.asset.Json.deinit();
            },
            .Static => {},
        }
    }

    /// returns true if the asset file was updated
    pub fn hasChanged(self: @This()) bool {
        if (self.asset == .Static) {
            return false;
        }
        return self.loadedModTime != self.currentModTime;
    }

    /// reloads the file and updates 'loadedModTime'
    pub fn reload(self: *@This()) !bool {
        if (!self.hasChanged()) return false;

        switch (self.asset) {
            .Texture2D => {
                self.asset = .{ .Texture2D = r.LoadTexture(self.path) };
            },
            .TextureAtlas => {
                const count = self.asset.TextureAtlas.count;
                self.asset = .{ .TextureAtlas = TextureAtlas.load(self.path, count.x, count.y) };
            },
            .Json => {
                try self.asset.Json.reload(self.path);
            },
            .Static => {},
        }
        self.loadedModTime = self.currentModTime;
        return true;
    }

    /// check mod time of the file with 'std.fs.File.stat()'
    /// update self.currentModTime
    pub fn check(self: *@This()) !bool {
        if (self.asset == .Static) {
            return false;
        }
        //this makes no sense in webassembly
        if (builtin.os.tag != .wasi and builtin.os.tag != .emscripten) {
            const cwd = std.fs.cwd();
            const file: std.fs.File = try cwd.openFile(self.path, .{});
            defer file.close();
            const stat = try file.stat();
            self.currentModTime = stat.mtime;
        }
        return self.hasChanged();
    }
};

//=================================================================================================
//=== TESTS =======================================================================================
//=================================================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "AssetLink" {
    //TODO: write & delete pseudo asset for test
    var ass = AssetLink.init(std.testing.allocator, .Texture2D, "assets/images/food/onion_unpeeled.png");
    defer ass.deinit();

    try expectEqual(ass.path, "assets/images/food/onion_unpeeled.png");
    try expectEqual(ass.assetType, .Texture2D);
}
