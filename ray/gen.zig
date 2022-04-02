const std = @import("std");
const r = @cImport({
    @cInclude("raylib_marshall.h");
});
const t = @import("types.zig");
const cPtr = t.asCPtr;

pub fn InitWindow(width: i32, height: i32, title: []const u8) void {
    return r.mInitWindow(
        @intCast(c_int, width),
        @intCast(c_int, height),
        @ptrCast([*c]const u8, title.ptr),
    );
}

pub fn WindowShouldClose() bool {
    return r.mWindowShouldClose();
}

pub fn CloseWindow() void {
    return r.mCloseWindow();
}

pub fn SetWindowMinSize(width: i32, height: i32) void {
    return r.mSetWindowMinSize(
        @intCast(c_int, width),
        @intCast(c_int, height),
    );
}

pub fn SetWindowSize(width: i32, height: i32) void {
    return r.mSetWindowSize(
        @intCast(c_int, width),
        @intCast(c_int, height),
    );
}

pub fn GetScreenWidth() i32 {
    return r.mGetScreenWidth();
}

pub fn GetScreenHeight() i32 {
    return r.mGetScreenHeight();
}

pub fn IsCursorOnScreen() bool {
    return r.mIsCursorOnScreen();
}

pub fn ClearBackground(color: t.Color) void {
    var _color = color;

    return r.mClearBackground(
        @ptrCast([*c]r.Color, &_color),
    );
}

pub fn BeginDrawing() void {
    return r.mBeginDrawing();
}

pub fn EndDrawing() void {
    return r.mEndDrawing();
}

pub fn BeginMode2D(camera: t.Camera2D) void {
    var _camera = camera;

    return r.mBeginMode2D(
        @ptrCast([*c]r.Camera2D, &_camera),
    );
}

pub fn EndMode2D() void {
    return r.mEndMode2D();
}

pub fn GetCameraMatrix2D(camera: t.Camera2D) t.Matrix {
    var _camera = camera;
    var _out: t.Matrix = undefined;

    r.mGetCameraMatrix2D(
        @ptrCast([*c]r.Matrix, &_out),
        @ptrCast([*c]r.Camera2D, &_camera),
    );
    return _out;
}

pub fn GetWorldToScreen2D(position: t.Vector2, camera: t.Camera2D) t.Vector2 {
    var _position = position;
    var _camera = camera;
    var _out: t.Vector2 = undefined;

    r.mGetWorldToScreen2D(
        @ptrCast([*c]r.Vector2, &_out),
        @ptrCast([*c]r.Vector2, &_position),
        @ptrCast([*c]r.Camera2D, &_camera),
    );
    return _out;
}

pub fn GetScreenToWorld2D(position: t.Vector2, camera: t.Camera2D) t.Vector2 {
    var _position = position;
    var _camera = camera;
    var _out: t.Vector2 = undefined;

    r.mGetScreenToWorld2D(
        @ptrCast([*c]r.Vector2, &_out),
        @ptrCast([*c]r.Vector2, &_position),
        @ptrCast([*c]r.Camera2D, &_camera),
    );
    return _out;
}

pub fn SetTargetFPS(fps: i32) void {
    return r.mSetTargetFPS(
        @intCast(c_int, fps),
    );
}

pub fn GetFPS() i32 {
    return r.mGetFPS();
}

pub fn GetFrameTime() f32 {
    return r.mGetFrameTime();
}

pub fn GetTime() f64 {
    return r.mGetTime();
}

pub fn OpenURL(url: []const u8) void {
    return r.mOpenURL(
        @ptrCast([*c]const u8, url.ptr),
    );
}

pub fn IsKeyPressed(key: i32) bool {
    return r.mIsKeyPressed(
        @intCast(c_int, key),
    );
}

pub fn IsKeyDown(key: i32) bool {
    return r.mIsKeyDown(
        @intCast(c_int, key),
    );
}

pub fn IsKeyReleased(key: i32) bool {
    return r.mIsKeyReleased(
        @intCast(c_int, key),
    );
}

pub fn IsKeyUp(key: i32) bool {
    return r.mIsKeyUp(
        @intCast(c_int, key),
    );
}

pub fn SetExitKey(key: i32) void {
    return r.mSetExitKey(
        @intCast(c_int, key),
    );
}

pub fn GetKeyPressed() i32 {
    return r.mGetKeyPressed();
}

pub fn GetCharPressed() i32 {
    return r.mGetCharPressed();
}

pub fn IsMouseButtonPressed(button: i32) bool {
    return r.mIsMouseButtonPressed(
        @intCast(c_int, button),
    );
}

pub fn IsMouseButtonDown(button: i32) bool {
    return r.mIsMouseButtonDown(
        @intCast(c_int, button),
    );
}

pub fn IsMouseButtonReleased(button: i32) bool {
    return r.mIsMouseButtonReleased(
        @intCast(c_int, button),
    );
}

pub fn IsMouseButtonUp(button: i32) bool {
    return r.mIsMouseButtonUp(
        @intCast(c_int, button),
    );
}

pub fn GetMousePosition() t.Vector2 {
    var _out: t.Vector2 = undefined;

    r.mGetMousePosition(
        @ptrCast([*c]r.Vector2, &_out),
    );
    return _out;
}

pub fn GetMouseDelta() t.Vector2 {
    var _out: t.Vector2 = undefined;

    r.mGetMouseDelta(
        @ptrCast([*c]r.Vector2, &_out),
    );
    return _out;
}

pub fn SetMouseOffset(offsetX: i32, offsetY: i32) void {
    return r.mSetMouseOffset(
        @intCast(c_int, offsetX),
        @intCast(c_int, offsetY),
    );
}

pub fn SetMouseScale(scaleX: f32, scaleY: f32) void {
    return r.mSetMouseScale(
        scaleX,
        scaleY,
    );
}

pub fn GetMouseWheelMove() f32 {
    return r.mGetMouseWheelMove();
}

pub fn SetMouseCursor(cursor: i32) void {
    return r.mSetMouseCursor(
        @intCast(c_int, cursor),
    );
}

pub fn GetTouchPosition(index: i32) t.Vector2 {
    var _out: t.Vector2 = undefined;

    r.mGetTouchPosition(
        @ptrCast([*c]r.Vector2, &_out),
        @intCast(c_int, index),
    );
    return _out;
}

pub fn GetTouchPointCount() i32 {
    return r.mGetTouchPointCount();
}

pub fn DrawLineEx(startPos: t.Vector2, endPos: t.Vector2, thick: f32, color: t.Color) void {
    var _startPos = startPos;
    var _endPos = endPos;
    var _color = color;

    return r.mDrawLineEx(
        @ptrCast([*c]r.Vector2, &_startPos),
        @ptrCast([*c]r.Vector2, &_endPos),
        thick,
        @ptrCast([*c]r.Color, &_color),
    );
}

pub fn DrawRectanglePro(rec: t.Rectangle, origin: t.Vector2, rotation: f32, color: t.Color) void {
    var _rec = rec;
    var _origin = origin;
    var _color = color;

    return r.mDrawRectanglePro(
        @ptrCast([*c]r.Rectangle, &_rec),
        @ptrCast([*c]r.Vector2, &_origin),
        rotation,
        @ptrCast([*c]r.Color, &_color),
    );
}

pub fn LoadTexture(fileName: []const u8) t.Texture2D {
    var _out: t.Texture2D = undefined;

    r.mLoadTexture(
        @ptrCast([*c]r.Texture2D, &_out),
        @ptrCast([*c]const u8, fileName.ptr),
    );
    return _out;
}

pub fn UnloadTexture(texture: t.Texture2D) void {
    var _texture = texture;

    return r.mUnloadTexture(
        @ptrCast([*c]r.Texture2D, &_texture),
    );
}

pub fn DrawTexturePro(texture: t.Texture2D, source: t.Rectangle, dest: t.Rectangle, origin: t.Vector2, rotation: f32, tint: t.Color) void {
    var _texture = texture;
    var _source = source;
    var _dest = dest;
    var _origin = origin;
    var _tint = tint;

    return r.mDrawTexturePro(
        @ptrCast([*c]r.Texture2D, &_texture),
        @ptrCast([*c]r.Rectangle, &_source),
        @ptrCast([*c]r.Rectangle, &_dest),
        @ptrCast([*c]r.Vector2, &_origin),
        rotation,
        @ptrCast([*c]r.Color, &_tint),
    );
}

pub fn DrawFPS(posX: i32, posY: i32) void {
    return r.mDrawFPS(
        @intCast(c_int, posX),
        @intCast(c_int, posY),
    );
}

pub fn DrawText(text: []const u8, posX: i32, posY: i32, fontSize: i32, color: t.Color) void {
    var _color = color;

    return r.mDrawText(
        @ptrCast([*c]const u8, text.ptr),
        @intCast(c_int, posX),
        @intCast(c_int, posY),
        @intCast(c_int, fontSize),
        @ptrCast([*c]r.Color, &_color),
    );
}
