const std = @import("std");
const r = @import("../../../raylib/raylib.zig");
const utils = @import("../draw_text.zig");

pub fn defaultTrimOverflow(text: []u8, options: DrawTextInRectOptions) void {
    //TODO
    _ = text;
    _ = options;
}

pub fn DefaultToString(comptime TElement: type) *const fn (std.mem.Allocator, usize, TElement) std.fmt.AllocPrintError![:0]u8 {
    return (struct {
        fn print(allocator: std.mem.Allocator, index: usize, e: TElement) std.fmt.AllocPrintError![:0]u8 {
            _ = index;
            return try std.fmt.allocPrintZ(allocator, "{any}", .{e});
        }
    }).print;
}

pub fn UIListOptions(comptime TElement: type) type {
    return struct {
        fontSize: i32,
        color: r.Color = r.GOLD,
        borderColor: r.Color = r.BLACK,
        backgroundColor: r.Color = r.GRAY,

        /// determines how the text is aligned
        /// default: `TextOrigin.topLeft`
        origin: r.Vector2 = utils.TextOrigin.center,

        overflow: OverflowHandling = .cropEnd,

        ///control transformation from TElement to []const u8
        toString: *const fn (std.mem.Allocator, usize, TElement) anyerror![:0]u8 = DefaultToString(TElement),
    };
}

/// creates strings with given allocator for all `data` elements
/// caller owns returned memory
pub fn uiList(
    comptime TElement: type,
    allocator: std.mem.Allocator,
    data: []const TElement,
    rect: r.Rectangle,
    options: UIListOptions(TElement),
) ![]const [:0]const u8 {
    var textList = std.ArrayList([:0]const u8).init(allocator);
    errdefer {
        for (textList.items) |t| {
            allocator.free(t);
        }
        textList.deinit();
    }
    const spacePerCell = r.Vector2{ .x = rect.width, .y = rect.height / @intToFloat(f32, data.len) };

    r.DrawRectangleRec(rect, options.borderColor);

    for (data) |element, i| {
        const cellRect = r.Rectangle{
            .x = rect.x,
            .y = rect.y + (@intToFloat(f32, i) * spacePerCell.y),
            .width = rect.width,
            .height = spacePerCell.y,
        };
        var str = try options.toString(allocator, i, element);
        defaultTrimOverflow(str, .{
            .rect = cellRect,
            .fontSize = options.fontSize,
            .color = options.color,
            .origin = options.origin,
            // .overflow = options.overflow,
        });
        try textList.append(str);
        utils.drawJustText(str, .{
            .position = cellRect.center(),
            .fontSize = options.fontSize,
            .color = options.color,
            .origin = options.origin,
        });
        r.DrawLineEx(cellRect.bottomLeft(), cellRect.bottomRight(), 1, options.color);
    }

    return textList.toOwnedSlice();
}

pub fn uiStackList(
    comptime TElement: type,
    comptime stackBufferSize: usize,
    data: []const TElement,
    rect: r.Rectangle,
    options: UIListOptions(TElement),
) !void {
    var buffer: [stackBufferSize]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    _ = try uiList(TElement, fba.allocator(), data, rect, options);
}

pub const DrawTextInRectOptions = struct {
    rect: r.Rectangle,
    fontSize: i32,
    color: r.Color = r.BLACK,

    /// determines how the text is aligned
    /// default: `TextOrigin.topLeft`
    origin: r.Vector2 = utils.TextOrigin.topLeft,
};

pub const OverflowHandling = enum { cropEnd, elipseAtStart, elipseAtEnd, elipseInTheMiddle };
