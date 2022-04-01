const std = @import("std");

const r = @cImport({
    @cInclude("raylib_marshall.h");
});
const t = @import("types.zig");

// /// Draw a line defining thickness
// void DrawLineEx(Vector2 startPos, Vector2 endPos, float thick, Color color);

pub fn DrawLineEx(startPos: t.Vector2, endPos: t.Vector2, thick: f32, color: t.Color) void {
    var s = startPos;
    var e = endPos;
    var c = color;
    r.mDrawLineEx(
        @ptrCast([*c]r.Vector2, &s),
        @ptrCast([*c]r.Vector2, &e),
        thick,
        @ptrCast([*c]r.Color, &c),
    );
}

// Draw a color-filled rectangle with pro parameters
pub fn DrawRectanglePro(rec: t.Rectangle, origin: t.Vector2, rotation: f32, color: t.Color) void {
    var _r = rec;
    var _o = origin;
    var _c = color;
    r.mDrawRectanglePro(
        @ptrCast([*c]r.Rectangle, &_r),
        @ptrCast([*c]r.Vector2, &_o),
        rotation,
        @ptrCast([*c]r.Color, &_c),
    );
}
