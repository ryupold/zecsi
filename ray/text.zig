const r = @cImport({
    @cInclude("raylib_marshall.h");
});
const t = @import("types.zig");

//=== Text drawing functions ======================================================================

/// Draw text (using default font)
pub fn DrawText(title: [*c]const u8, x: i32, y: i32, fontSize: i32, color: t.Color) void {
    var c = color;
    r.mDrawText(title, @intCast(c_int, x), @intCast(c_int, y), @intCast(c_int, fontSize), @ptrCast([*c]r.Color, &c));
}

pub fn DrawFPS(x: i32, y: i32) void {
    r.mDrawFPS(@intCast(c_int, x), @intCast(c_int, y));
}
