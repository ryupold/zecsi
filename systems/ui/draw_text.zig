const std = @import("std");
const zecsi = @import("../../zecsi.zig");
const raylib = zecsi.raylib;
const log = zecsi.log;

pub const TextOrigin = struct {
    pub const topLeft: raylib.Vector2 = .{ .x = 0, .y = 0 };
    pub const topCenter: raylib.Vector2 = .{ .x = 0.5, .y = 0 };
    pub const topRight: raylib.Vector2 = .{ .x = 1, .y = 0 };
    pub const centerLeft: raylib.Vector2 = .{ .x = 0, .y = 0.5 };
    pub const center: raylib.Vector2 = .{ .x = 0.5, .y = 0.5 };
    pub const centerRight: raylib.Vector2 = .{ .x = 1, .y = 0.5 };
    pub const bottomRight: raylib.Vector2 = .{ .x = 1, .y = 1 };
    pub const bottomCenter: raylib.Vector2 = .{ .x = 0.5, .y = 1 };
    pub const bottomLeft: raylib.Vector2 = .{ .x = 0, .y = 1 };
};

pub const DrawTextOptions = struct {
    position: raylib.Vector2,
    fontSize: i32,
    color: raylib.Color = raylib.BLACK,

    /// determines how the text is aligned
    /// default: `TextOrigin.topLeft`
    origin: raylib.Vector2 = TextOrigin.topLeft,
};

pub fn drawText(
    comptime fmt: []const u8,
    args: anytype,
    options: DrawTextOptions,
) void {
    var buf: [32 * 1024]u8 = undefined;
    drawTextBuf(&buf, fmt, args, options) catch |err| {
        log.err("error during drawText: {any}", .{err});
    };
}

pub fn drawTextBuf(
    buffer: []u8,
    comptime fmt: []const u8,
    args: anytype,
    options: DrawTextOptions,
) !void {
    var fba = std.heap.FixedBufferAllocator.init(buffer);
    drawTextAlloc(fba.allocator(), fmt, args, options) catch {
        return error.DrawTextBufNeedsBiggerBufferForThat;
    };
}

pub fn drawTextAlloc(
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
    options: DrawTextOptions,
) !void {
    const text = try std.fmt.allocPrintZ(allocator, fmt, args);

    const lines = @intCast(i32, @truncate(u32, std.mem.count(u8, text, "\n") + 1));

    const textWidth = raylib.MeasureText(text, options.fontSize);
    raylib.DrawText(
        text,
        @floatToInt(i32, options.position.x - (@intToFloat(f32, textWidth) * options.origin.x)),
        @floatToInt(i32, options.position.y - (@intToFloat(f32, options.fontSize * lines) * options.origin.y)),
        options.fontSize,
        options.color,
    );
}

