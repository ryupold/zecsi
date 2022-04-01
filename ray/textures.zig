const r = @cImport({
    @cInclude("raylib_marshall.h");
});

const t = @import("types.zig");

//=== Texture loading functions ===================================================================
// NOTE: These functions require GPU access

/// Load texture from file into GPU memory (VRAM)
pub fn LoadTexture(path: [*c]const u8) t.Texture2D {
    var tex: t.Texture2D = undefined;
    r.mLoadTexture(@ptrCast([*c]r.Texture2D, &tex), path);
    return tex;
}

/// Unload texture from GPU memory (VRAM)
pub fn UnloadTexture(texture: t.Texture2D) void {
    var tex = texture;
    r.mUnloadTexture(@ptrCast([*c]r.Texture2D, &tex));
}

//=== Texture drawing functions ===================================================================

/// Draw a part of a texture defined by a rectangle with 'pro' parameters
pub fn DrawTexturePro(texture: t.Texture2D, source: t.Rectangle, dest: t.Rectangle, origin: t.Vector2, rotation: f32, tint: t.Color) void {
    var tex = texture;
    var src = source;
    var d = dest;
    var o = origin;
    var tnt = tint;
    r.mDrawTexturePro(
        @ptrCast([*c]r.Texture2D, &tex),
        @ptrCast([*c]r.Rectangle, &src),
        @ptrCast([*c]r.Rectangle, &d),
        @ptrCast([*c]r.Vector2, &o),
        rotation,
        @ptrCast([*c]r.Color, &tnt),
    );
}
