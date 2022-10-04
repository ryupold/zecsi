const std = @import("std");
const zecsi = @import("../../zecsi.zig");
const raylib = zecsi.raylib;
const log = zecsi.log;
const ECS = zecsi.ECS;
const utils = @import("draw_text.zig");

pub const ToastSystem = struct {
    ecs: *ECS,

    pub fn init(ecs: *ECS) !@This() {
        return @This(){
            .ecs = ecs,
        };
    }

    pub fn deinit(this: *@This()) void {
        var toasts = this.ecs.query(.{
            .{ "toast", Toast },
        });
        while (toasts.next()) |e| {
            e.toast.deinit(this.ecs.allocator);
            this.ecs.destroy(e.entity) catch |errr| {
                log.err("ToastSystem.deinit: {any}", .{errr});
            };
        }
    }

    pub fn update(this: *@This(), dt: f32) !void {
        var toasts = this.ecs.query(.{
            .{ "toast", Toast },
        });
        while (toasts.next()) |e| {
            if (e.toast.timer.tick(dt)) {
                e.toast.deinit(this.ecs.allocator);
                try this.ecs.destroy(e.entity);
            } else if (e.toast.options.typ == .world) {
                e.toast.draw();
            }
        }
        try this.ecs.syncEntities();
    }

    pub fn ui(this: *@This(), _: f32) !void {
        var toasts = this.ecs.query(.{
            .{ "toast", Toast },
        });
        while (toasts.next()) |e| {
            if (e.toast.options.typ == .screen) {
                e.toast.draw();
            }
        }
    }

    pub fn showToast(
        this: *@This(),
        comptime fmt: []const u8,
        args: anytype,
        position: raylib.Vector2,
        options: ToastOptions,
    ) !void {
        const e = try this.ecs.create();
        try this.ecs.put(e, try Toast.init(this.ecs.allocator, fmt, args, position, options));
    }
};

pub const ToastOptions = struct {
    pub const short: f32 = 2;
    pub const medium: f32 = 4;
    pub const long: f32 = 6;

    typ: enum { screen, world } = .world,
    time: f32 = short,
    fontSize: i32 = 15,
    color: raylib.Color = raylib.WHITE,
    background: raylib.Color = raylib.BLACK.set(.{ .a = 150 }),
    origin: raylib.Vector2 = utils.TextOrigin.center,
    pointer: ?raylib.Vector2 = null,
};

pub const Toast = struct {
    text: [:0]const u8,
    timer: zecsi.utils.Timer,
    position: raylib.Vector2,
    options: ToastOptions,

    pub fn init(
        allocator: std.mem.Allocator,
        comptime fmt: []const u8,
        args: anytype,
        position: raylib.Vector2,
        options: ToastOptions,
    ) !@This() {
        const text = try std.fmt.allocPrintZ(allocator, fmt, args);
        return @This(){
            .text = text,
            .position = position,
            .timer = zecsi.utils.Timer{ .repeat = false, .time = options.time },
            .options = options,
        };
    }

    pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(this.text);
    }

    pub fn draw(this: @This()) void {
        //TODO: fix cause of Nan
        if (std.math.isNan(this.position.x) or std.math.isNan(this.position.y)) return;
        const lines = @intCast(i32, @truncate(u32, std.mem.count(u8, this.text, "\n") + 1));

        const textWidth = raylib.MeasureText(this.text, this.options.fontSize);
        const textHeight = lines * this.options.fontSize;
        std.debug.assert(!std.math.isNan(this.position.x) and !std.math.isNan(this.position.y));
        const topLeft = raylib.Vector2i{
            .x = @floatToInt(i32, this.position.x - (@intToFloat(f32, textWidth) * this.options.origin.x)),
            .y = @floatToInt(i32, this.position.y - (@intToFloat(f32, this.options.fontSize * lines) * this.options.origin.y)),
        };
        const fs = this.options.fontSize;
        raylib.DrawRectangle(
            topLeft.x - fs,
            topLeft.y - fs,
            textWidth + fs * 2,
            textHeight + fs * 2,
            this.options.background.lerp(
                .{ .a = 0 },
                this.timer.progress(),
            ),
        );
        if (this.options.pointer) |pointer| {
            raylib.DrawCircle(
                @floatToInt(i32, this.position.x + pointer.x),
                @floatToInt(i32, this.position.y + pointer.y),
                2,
                raylib.RED,
            );
        }
        raylib.DrawText(
            this.text,
            topLeft.x,
            topLeft.y,
            fs,
            this.options.color.lerp(this.options.color.neg(), this.timer.progress()),
        );
    }
};
