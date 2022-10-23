const std = @import("std");
const r = @import("../../../raylib/raylib.zig");
const utils = @import("../draw_text.zig");

pub const UiButtonOptions = struct {
    textColor: r.Color = r.GOLD,
    hoverTextColor: r.Color = r.BLACK,
    pressedTextColor: r.Color = r.ORANGE,
    fontSize: f32 = 15,
    backgroundColor: r.Color = r.GRAY,
    pressedBackgroundColor: r.Color = r.DARKGRAY,
    hoverBackgroundColor: r.Color = r.LIGHTGRAY,
    borderColor: r.Color = r.BLACK,
    borderWidth: i32 = 2,
};

/// draw button with text on UI layer
/// use`UiButtonOptions` to customize appearance
pub fn uiButton(text: []const u8, rect: r.Rectangle, options: UiButtonOptions) bool {
    const State = enum { Normal, Hovered, Pressed };
    var state: State = .Normal;
    const mousePos = r.GetMousePosition();
    if (r.CheckCollisionPointRec(mousePos, rect)) {
        state = .Hovered;
        if (r.IsMouseButtonDown(.MOUSE_BUTTON_LEFT)) {
            state = .Pressed;
        }
    }

    const rectI = rect.toI32();
    r.DrawRectangle(rectI.x, rectI.y, rectI.width, rectI.height, options.borderColor);
    r.DrawRectangle(
        rectI.x + options.borderWidth,
        rectI.y + options.borderWidth,
        rectI.width - options.borderWidth * 2,
        rectI.height - options.borderWidth * 2,
        switch (state) {
            .Normal => options.backgroundColor,
            .Hovered => options.hoverBackgroundColor,
            .Pressed => options.pressedBackgroundColor,
        },
    );

    const txtColor = switch (state) {
        .Normal => options.textColor,
        .Hovered => options.hoverTextColor,
        .Pressed => options.pressedTextColor,
    };

    var buf: [100 * 1024]u8 = undefined;
    utils.drawTextBuf(&buf, "{s}", .{text}, .{
        .position = rect.center(),
        .fontSize = @floatToInt(i32, options.fontSize),
        .color = txtColor,
        .origin = utils.TextOrigin.center,
    }) catch |err| {
        utils.drawTextBuf(&buf, "{?}", .{err}, .{
            .position = rect.center(),
            .fontSize = @floatToInt(i32, options.fontSize),
            .color = txtColor,
            .origin = utils.TextOrigin.center,
        }) catch unreachable;
    };

    return state == .Pressed and r.IsMouseButtonPressed(.MOUSE_BUTTON_LEFT);
}

pub fn uiButtonFmt(
    comptime fmt: []const u8,
    args: anytype,
    rect: r.Rectangle,
    options: UiButtonOptions,
    mousePos: r.Vector2,
) bool {
    const State = enum { Normal, Hovered, Pressed };
    var state: State = .Normal;
    // const mousePos = r.GetMousePosition();
    if (r.CheckCollisionPointRec(mousePos, rect)) {
        state = .Hovered;
        if (r.IsMouseButtonDown(.MOUSE_BUTTON_LEFT)) {
            state = .Pressed;
        }
    }

    const rectI = rect.toI32();
    r.DrawRectangle(rectI.x, rectI.y, rectI.width, rectI.height, options.borderColor);
    r.DrawRectangle(
        rectI.x + options.borderWidth,
        rectI.y + options.borderWidth,
        rectI.width - options.borderWidth * 2,
        rectI.height - options.borderWidth * 2,
        switch (state) {
            .Normal => options.backgroundColor,
            .Hovered => options.hoverBackgroundColor,
            .Pressed => options.pressedBackgroundColor,
        },
    );

    const txtColor = switch (state) {
        .Normal => options.textColor,
        .Hovered => options.hoverTextColor,
        .Pressed => options.pressedTextColor,
    };

    var buf: [10 * 1024]u8 = undefined;
    utils.drawTextBuf(&buf, fmt, args, .{
        .position = rect.center(),
        .fontSize = @floatToInt(i32, options.fontSize),
        .color = txtColor,
        .origin = utils.TextOrigin.center,
    }) catch |err| {
        utils.drawTextBuf(&buf, "{?}", .{err}, .{
            .position = rect.center(),
            .fontSize = @floatToInt(i32, options.fontSize),
            .color = txtColor,
            .origin = utils.TextOrigin.center,
        }) catch unreachable;
    };

    return state == .Pressed and r.IsMouseButtonPressed(.MOUSE_BUTTON_LEFT);
}
