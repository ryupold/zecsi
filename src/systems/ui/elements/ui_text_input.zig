const std = @import("std");
const raylib = @import("raylib");
const utils = @import("../draw_text.zig");

pub fn ArrayTextInput(comptime maxLength: usize) type {
    return struct {
        box: raylib.Rectangle,
        data: [maxLength + 1]u8 = [_]u8{0} ** (maxLength + 1),
        last: usize = 0,
        letters: usize = 0,
        cursorPos: usize = 0,
        fontColor: raylib.Color = raylib.BLACK,
        backgroundColor: raylib.Color = raylib.LIGHTGRAY,
        focusedBorderColor: raylib.Color = raylib.RED,
        unfocusedBorderColor: raylib.Color = raylib.DARKGRAY,
        isFocused: bool = false,
        timeToBlink: f32 = 1,
        timePassed: f32 = 0,

        pub fn update(
            this: *@This(),
            dt: f32,
            mousePos: raylib.Vector2,
        ) void {

            // UPDATE
            if (raylib.IsMouseButtonPressed(.MOUSE_BUTTON_LEFT)) {
                if (raylib.CheckCollisionPointRec(mousePos, this.box)) {
                    this.isFocused = true;
                    this.timePassed = this.timeToBlink;
                } else {
                    this.isFocused = false;
                }
            }
            if (this.isFocused) {
                // Get char pressed (utf8 character) on the queue
                var key = @as(u21, @intCast(raylib.GetCharPressed()));

                // Check if more characters have been pressed on the same frame
                while (key > 0) {
                    var byteCount: usize = @as(usize, @intCast(std.unicode.utf8CodepointSequenceLength(key) catch 0));
                    if (byteCount == 0) continue;
                    if ((key >= 32) and (this.last < this.data.len - byteCount - 1)) {
                        if (std.unicode.Utf8View.init(this.text())) |view| {
                            var it = view.iterator();
                            const cursorIndex: usize = it.peek(this.cursorPos).len;
                            std.mem.copyForwards(u8, this.data[cursorIndex..this.last], this.data[cursorIndex + byteCount .. this.last + byteCount]);
                        } else |err| {
                            std.debug.print("ui_text_input.zig: {?}\n", .{err});
                            continue;
                        }

                        while (byteCount > 0) : (byteCount -= 1) {
                            this.data[this.last] = @as(u8, @truncate(key >> @as(u5, @intCast((byteCount - 1) * 8))));
                            this.last += 1;
                        }
                        this.letters += 1;
                        this.cursorPos += 1;
                    }

                    key = @as(u21, @intCast(raylib.GetCharPressed())); // Check next character in the queue
                }

                if (raylib.IsKeyPressed(.KEY_BACKSPACE) and this.cursorPos > 0 and this.letters > 0) {
                    if (std.unicode.Utf8View.init(this.text())) |view| {
                        var it = view.iterator();
                        var last: []const u8 = undefined;
                        while (it.nextCodepointSlice()) |s| {
                            last = s;
                        }

                        this.last -= last.len;
                        this.data[this.last] = 0;
                        this.letters -= 1;
                        this.cursorPos -= 1;
                    } else |err| {
                        std.debug.print("ui_text_input.zig: {?}\n", .{err});
                    }
                }

                if (raylib.IsKeyPressed(.KEY_LEFT) and this.cursorPos > 0) {
                    this.cursorPos -= 1;
                    this.timePassed = this.timeToBlink;
                }
                if (raylib.IsKeyPressed(.KEY_RIGHT) and this.cursorPos < this.letters) {
                    this.cursorPos += 1;
                    this.timePassed = this.timeToBlink;
                }
            }

            if (raylib.CheckCollisionPointRec(mousePos, this.box)) {
                raylib.SetMouseCursor(.MOUSE_CURSOR_IBEAM);
            } else {
                raylib.SetMouseCursor(.MOUSE_CURSOR_DEFAULT);
            }

            // DRAW
            raylib.DrawRectangleRec(this.box, this.backgroundColor);
            if (this.isFocused) {
                raylib.DrawRectangleLines(@as(i32, @intFromFloat(this.box.x)), @as(i32, @intFromFloat(this.box.y)), @as(i32, @intFromFloat(this.box.width)), @as(i32, @intFromFloat(this.box.height)), this.focusedBorderColor);
            } else {
                raylib.DrawRectangleLines(@as(i32, @intFromFloat(this.box.x)), @as(i32, @intFromFloat(this.box.y)), @as(i32, @intFromFloat(this.box.width)), @as(i32, @intFromFloat(this.box.height)), this.unfocusedBorderColor);
            }

            const fontSize = @as(i32, @intFromFloat(this.box.height)) - 2;
            raylib.DrawText(@as([*:0]u8, @ptrCast(&this.data)), @as(i32, @intFromFloat(this.box.x)) + 5, @as(i32, @intFromFloat(this.box.y)), fontSize, this.fontColor);

            // draw cursor
            if (this.isFocused) {
                if (this.timePassed >= 0) {
                    if (std.unicode.Utf8View.init(this.text())) |view| {
                        var it: std.unicode.Utf8Iterator = view.iterator();
                        const peek = it.peek(this.cursorPos);
                        const before = this.data[peek.len];
                        this.data[peek.len] = 0;
                        raylib.DrawText("|", @as(i32, @intFromFloat(this.box.x)) + 4 + raylib.MeasureText(@as([*:0]u8, @ptrCast(&this.data)), fontSize), @as(i32, @intFromFloat(this.box.y)), fontSize, this.fontColor);
                        this.data[peek.len] = before;
                    } else |err| {
                        std.debug.print("ui_text_input.zig: {?}\n", .{err});
                    }
                }

                if (this.timePassed > 0) {
                    this.timePassed -= dt;
                    if (this.timePassed <= 0) {
                        this.timePassed = -this.timeToBlink;
                    }
                } else if (this.timePassed <= 0) {
                    this.timePassed += dt;
                    if (this.timePassed > 0) {
                        this.timePassed = this.timeToBlink;
                    }
                }
            }
        }

        pub fn text(this: *@This()) []const u8 {
            return this.data[0..this.last];
        }

        pub fn setText(this: *@This(), comptime fmt: []const u8, args: anytype) void {
            _ = std.fmt.bufPrintZ(&this.data, fmt, args) catch {};
        }
    };
}
