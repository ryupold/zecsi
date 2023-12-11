const std = @import("std");
const builtin = @import("builtin");
const r = @import("raylib");
const log = @import("log.zig");

pub const CheckFn = *const fn (allocator: std.mem.Allocator, ptr: usize) anyerror!bool;
pub const DeinitFn = *const fn (allocator: std.mem.Allocator, ptr: usize) void;

pub const Texture = struct {
    path: [:0]const u8,
    tex: r.Texture2D,
    loadTime: i128 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        path: [:0]const u8,
    ) !*@This() {
        const ptr = try allocator.create(Texture);
        const tex = r.LoadTexture(path);
        ptr.* = .{
            .path = path,
            .tex = tex,
            .loadTime = std.time.nanoTimestamp(),
        };
        return ptr;
    }

    pub fn reload(this: *@This()) !void {
        r.UnloadTexture(this.tex);
        this.tex = r.LoadTexture(this.path);
        this.loadTime = std.time.nanoTimestamp();
    }

    pub fn draw(
        self: @This(),
        pos: r.Vector2,
        size: r.Vector2,
        rotation: f32,
        tint: r.Color,
    ) void {
        const dest: r.Rectangle = .{
            .x = pos.x - size.x / 2.0,
            .y = pos.y - size.y / 2.0,
            .width = size.x,
            .height = size.y,
        };

        const sourceRec: r.Rectangle = .{
            .x = 0,
            .y = 0,
            .width = self.tex.width,
            .height = self.tex.height,
        };
        r.DrawTexturePro(self.tex, sourceRec, dest, r.Vector2.zero(), rotation, tint);
    }

    pub fn check(this: *@This(), allocator: std.mem.Allocator) !bool {
        _ = allocator;
        const modiTime = try readModTime(this.path);
        if (modiTime > this.loadTime) {
            try this.reload();
            return true;
        }
        return false;
    }

    pub fn checkFn(allocator: std.mem.Allocator, ptr: usize) !bool {
        var this: *@This() = @ptrFromInt(ptr);
        return this.check(allocator);
    }

    pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
        r.UnloadTexture(this.tex);
        allocator.destroy(this);
    }

    pub fn deinitFn(allocator: std.mem.Allocator, ptr: usize) void {
        const this: *@This() = @ptrFromInt(ptr);
        this.deinit(allocator);
    }
};

pub const TextureAtlas = struct {
    path: [:0]const u8,
    tex: r.Texture2D,
    count: struct {
        x: u32 = 1,
        y: u32 = 1,
    } = .{ .x = 1, .y = 1 },
    cell: struct {
        width: f32,
        height: f32,
    },
    loadTime: i128 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        path: [:0]const u8,
        horizontalCells: u32,
        verticalCells: u32,
    ) !*@This() {
        const ptr = try allocator.create(TextureAtlas);
        const tex = r.LoadTexture(path);
        ptr.* = .{
            .path = path,
            .tex = tex,
            .count = .{ .x = horizontalCells, .y = verticalCells },
            .cell = .{
                .width = @as(f32, @floatFromInt(@divFloor(@as(u32, @intCast(tex.width)), horizontalCells))),
                .height = @as(f32, @floatFromInt(@divFloor(@as(u32, @intCast(tex.height)), verticalCells))),
            },
            .loadTime = std.time.nanoTimestamp(),
        };
        return ptr;
    }

    pub fn reload(this: *@This()) !void {
        r.UnloadTexture(this.tex);
        this.tex = r.LoadTexture(this.path);
        this.loadTime = std.time.nanoTimestamp();
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

    pub fn check(this: *@This(), allocator: std.mem.Allocator) !bool {
        _ = allocator;
        const modiTime = try readModTime(this.path);
        if (modiTime > this.loadTime) {
            try this.reload();
            return true;
        }
        return false;
    }

    pub fn checkFn(allocator: std.mem.Allocator, ptr: usize) !bool {
        var this: *@This() = @ptrFromInt(ptr);
        return this.check(allocator);
    }

    pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
        r.UnloadTexture(this.tex);
        allocator.destroy(this);
    }

    pub fn deinitFn(allocator: std.mem.Allocator, ptr: usize) void {
        const this: *@This() = @ptrFromInt(ptr);
        this.deinit(allocator);
    }
};

pub const AnimatedTextureAtlas = struct {
    time: f32,
    index: u32 = 0,
    count: u32,
    loop: bool,
    atlas: *TextureAtlas,
    timePassed: f32 = 0,

    pub fn init(
        atlas: *TextureAtlas,
        count: u32,
        time: f32,
        loop: bool,
    ) @This() {
        return @This(){
            .atlas = atlas,
            .count = count,
            .time = time,
            .loop = loop,
            .index = 0,
        };
    }

    pub fn tick(this: *@This(), dt: f32) void {
        if (this.loop) {
            this.timePassed += dt;
            if (this.timePassed >= this.time)
                this.timePassed = std.math.clamp(this.timePassed - this.time, 0, this.time);
        } else {
            this.timePassed = std.math.clamp(this.timePassed + dt, 0, this.time);
        }

        const percent = this.timePassed / this.time;
        this.index = @as(
            u32,
            @intFromFloat(percent * @as(f32, @floatFromInt(this.count - 1))),
        );
    }

    pub fn draw(
        this: @This(),
        dest: r.Rectangle,
        origin: r.Vector2,
        rotation: f32,
        tint: r.Color,
    ) void {
        const cellX = this.index % this.atlas.count.x;
        const cellY = this.index / this.atlas.count.x;
        this.atlas.draw(cellX, cellY, dest, origin, rotation, tint);
    }
};

pub fn Json(comptime T: type) type {
    return union(enum) {
        const Self = @This();
        Const: T,
        String: struct {
            object: std.json.Parsed(T) = undefined,
        },
        File: struct {
            object: std.json.Parsed(T) = undefined,
            path: [:0]const u8,
            loadTime: i128 = 0,

            pub fn reload(this: *@This(), allocator: std.mem.Allocator) !void {
                this.object.deinit();

                const data = try r.LoadFileData(this.path);
                if (data.len == 0) return error.UnexpectedEndOfJson;
                defer r.UnloadFileData(data);

                const parsed = try std.json.parseFromSlice(T, allocator, data, .{
                    .duplicate_field_behavior = .use_last,
                    .ignore_unknown_fields = true,
                });
                this.object = parsed;
                this.loadTime = std.time.nanoTimestamp();
            }

            pub fn check(this: *@This(), allocator: std.mem.Allocator) !bool {
                const modiTime = try readModTime(this.path);
                if (modiTime > this.loadTime) {
                    try this.reload(allocator);
                    return true;
                }
                return false;
            }
        },

        pub fn initConst(allocator: std.mem.Allocator, v: T) !*@This() {
            const this = try allocator.create(Self);

            this.* = Self{ .Const = v };
            return this;
        }

        pub fn initFromString(allocator: std.mem.Allocator, str: []const u8) !*@This() {
            const parsed = try std.json.parseFromSlice(T, allocator, str, .{
                .duplicate_field_behavior = .use_last,
                .ignore_unknown_fields = true,
            });
            const this = try allocator.create(Self);

            this.* = Self{ .String = .{ .object = parsed } };
            return this;
        }

        pub fn initFromFile(allocator: std.mem.Allocator, path: [:0]const u8) !*@This() {
            const data = try r.LoadFileData(path);
            if (data.len == 0) return error.UnexpectedEndOfJson;
            defer r.UnloadFileData(data);

            const parsed = try std.json.parseFromSlice(T, allocator, data, .{
                .duplicate_field_behavior = .use_last,
                .ignore_unknown_fields = true,
            });

            const this = try allocator.create(Self);
            this.* = Self{ .File = .{
                .object = parsed,
                .path = path,
                .loadTime = std.time.nanoTimestamp(),
            } };
            return this;
        }

        pub fn value(this: @This()) T {
            return switch (this) {
                @This().Const => this.Const,
                @This().String => this.String.object.value,
                @This().File => this.File.object.value,
            };
        }

        pub fn check(this: *@This(), allocator: std.mem.Allocator) !bool {
            return switch (this.*) {
                @This().Const => false,
                @This().String => false,
                @This().File => |*f| f.check(allocator),
            };
        }

        pub fn checkFn(allocator: std.mem.Allocator, ptr: usize) !bool {
            const this: *@This() = @ptrFromInt(ptr);
            return try this.check(allocator);
        }

        pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
            switch (this.*) {
                @This().Const => {},
                @This().String => |*s| s.object.deinit(),
                @This().File => |*f| f.object.deinit(),
            }
            allocator.destroy(this);
        }

        pub fn deinitFn(allocator: std.mem.Allocator, ptr: usize) void {
            const this: *@This() = @ptrFromInt(ptr);
            this.deinit(allocator);
        }
    };
}

fn readModTime(path: []const u8) !i128 {
    //this makes no sense in webassembly
    if (builtin.os.tag == .wasi or builtin.os.tag == .emscripten) {
        return 0;
    }

    const cwd = std.fs.cwd();
    const file: std.fs.File = try cwd.openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    return stat.mtime;
}
