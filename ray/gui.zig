const r = @cImport({
    @cInclude("raylib_marshall.h");
    @cInclude("extras/raygui.h");
});
const t = @import("types.zig");

//=== GENERATED ====


pub fn GuiButton(bounds: r.Rectangle, text: []const u8) bool {
    return r.GuiButton(bounds, @ptrCast([*c]const u8, text));
}
