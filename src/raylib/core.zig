//! apologies for the weird bindings.
//! i have to pass structs in&out as pointers otherwise the wasm32 build will crash at runtime
//! windows & macos works just fine passing structs directly

const std = @import("std");

const r = @cImport({
    @cInclude("raylib_marshall.h");
});

const t = @import("types.zig");
const cPtr = t.asCPtr;

//=== Window-related functions ====================================================================
// Setup init configuration flags
pub fn SetConfigFlags(flags: t.ConfigFlags) void {
    r.SetConfigFlags(@enumToInt(flags));
}

/// Initialize window and OpenGL context
pub fn InitWindow(width: c_int, height: c_int, title: [*c]const u8) void {
    r.mInitWindow(width, height, title);
}

pub fn GetScreenWidth() u32 {
    return @intCast(u32, r.mGetScreenWidth());
}

pub fn GetScreenHeight() u32 {
    return @intCast(u32, r.mGetScreenHeight());
}

pub fn SetWindowSize(width: c_int, height: c_int) void {
    r.mSetWindowSize(width, height);
}

/// Set window minimum dimensions 
pub fn SetWindowMinSize(width: u32, height: u32) void {
    r.SetWindowMinSize(@intCast(c_int, width), @intCast(c_int, height));
}

/// Check if KEY_ESCAPE pressed or Close icon pressed
pub fn WindowShouldClose() bool {
    return r.mWindowShouldClose();
}

/// Close window and unload OpenGL context
pub fn CloseWindow() void {
    r.mCloseWindow();
}

//=== Timing-related functions ====================================================================
pub fn SetTargetFPS(fps: c_int) void {
    r.mSetTargetFPS(fps);
}
pub fn GetFPS() c_int {
    return r.mGetFPS();
}

pub fn GetFrameTime() f32 {
    return r.mGetFrameTime();
}

pub fn GetTime() f64 {
    return r.mGetTime();
}

//=== Drawing-related functions ===================================================================

/// Setup canvas (framebuffer) to start drawing
pub fn BeginDrawing() void {
    r.mBeginDrawing();
}

/// End canvas drawing and swap buffers (double buffering)
pub fn EndDrawing() void {
    r.mEndDrawing();
}

/// Set background color (framebuffer clear color)
pub fn ClearBackground(color: t.Color) void {
    var c = color;
    r.mClearBackground(@ptrCast([*c]r.Color, &c));
}

//=== Camera ======================================================================================

/// Begin 2D mode with custom camera (2D)
pub fn BeginMode2D(camera: t.Camera2D) void {
    var _camera = camera;
    r.mBeginMode2D(@ptrCast([*c]r.Camera2D, &_camera));
}

/// Ends 2D mode with custom camera
pub fn EndMode2D() void {
    r.mEndMode2D();
}

pub fn GetCameraMatrix2D(camera: t.Camera2D) t.Matrix {
    var m: t.Matrix = undefined;
    var c = camera;
    r.mGetCameraMatrix2D(cPtr(r.Matrix, &m), cPtr(r.Camera2D, &c));
    return m;
}

// Get the screen space position for a 2d camera world space position
pub fn GetWorldToScreen2D(position: t.Vector2, camera: t.Camera2D) t.Vector2 {
    var out: t.Vector2 = undefined;
    var p = position;
    var c = camera;
    r.mGetWorldToScreen2D(cPtr(r.Vector2, &out), cPtr(r.Vector2, &p), cPtr(r.Camera2D, &c));
    return out;
}
// Get the world space position for a 2d camera screen space position
pub fn GetScreenToWorld2D(position: t.Vector2, camera: t.Camera2D) t.Vector2 {
    var out: t.Vector2 = undefined;
    var p = position;
    var c = camera;
    r.mGetScreenToWorld2D(cPtr(r.Vector2, &out), cPtr(r.Vector2, &p), cPtr(r.Camera2D, &c));
    return out;
}

//=== Files System ================================================================================
pub fn LoadFileData(fileName: []const u8) []const u8 {
    var buf: [8096]u8 = undefined;
    var bytesRead: u32 = undefined;

    const result = r.mLoadFileData(std.fmt.bufPrintZ(&buf, "{s}", .{fileName}) catch unreachable, @ptrCast([*c]c_uint, &bytesRead));

    return result[0..bytesRead];
}

pub fn UnloadFileData(data: []const u8) void {
    var ptr = @intToPtr([*c]u8, @ptrToInt(data.ptr));
    r.mUnloadFileData(ptr);
}

//=== Input ==================================================================
//Touch
pub fn GetTouchPointCount() c_int {
    return r.mGetTouchPointCount();
}

pub fn GetTouchPosition(index: c_int) t.Vector2 {
    var v2: t.Vector2 = undefined;
    r.mGetTouchPosition(index, @ptrCast([*c]r.Vector2, &v2));
    return v2;
}

//Mouse

pub fn IsCursorOnScreen() bool {
    return r.mIsCursorOnScreen();
}

/// current position in screen coordinates
pub fn GetMousePosition() t.Vector2 {
    var v2: t.Vector2 = undefined;
    r.mGetMousePosition(@ptrCast([*c]r.Vector2, &v2));
    return v2;
}

/// Get mouse delta between frames
pub fn GetMouseDelta() t.Vector2 {
    var v2: t.Vector2 = undefined;
    r.mGetMouseDelta(@ptrCast([*c]r.Vector2, &v2));
    return v2;
}

pub fn IsMouseButtonDown(button: anytype) bool {
    return r.mIsMouseButtonDown(@intCast(c_int, button));
}

pub fn IsMouseButtonPressed(button: anytype) bool {
    return r.mIsMouseButtonPressed(@intCast(c_int, button));
}

pub fn IsMouseButtonReleased(button: anytype) bool {
    return r.mIsMouseButtonReleased(@intCast(c_int, button));
}

pub fn IsMouseButtonUp(button: anytype) bool {
    return r.mIsMouseButtonUp(@intCast(c_int, button));
}

/// Set mouse offset
pub fn SetMouseOffset(offsetX: i32, offsetY: i32) void {
    r.mSetMouseOffset(
        @intCast(c_int, offsetX),
        @intCast(c_int, offsetY),
    );
}

/// Set mouse scaling
pub fn SetMouseScale(scaleX: f32, scaleY: f32) void {
    r.mSetMouseScale(scaleX, scaleY);
}

/// Get mouse wheel movement Y
pub fn GetMouseWheelMove() f32 {
    return r.mGetMouseWheelMove();
}

/// Set mouse cursor
pub fn SetMouseCursor(cursor: u32) void {
    r.mSetMouseCursor(@intCast(c_int, cursor));
}

//--- Keyboard ------------------------------------------------------------------------------------

// Persistent storage management

/// Save integer value to storage file (to defined position), returns true on success
pub fn SaveStorageValue(position: c_uint, value: c_int) bool {
    return r.SaveStorageValue(position, value);
}

/// Load integer value from storage file (from defined position)
pub fn LoadStorageValue(position: c_uint) c_int {
    return r.LoadStorageValue(position);
}

// Misc.

/// Open URL with default system browser (if available)
pub fn OpenURL(url: []const u8) void {
    r.OpenURL(@ptrCast([*c]const u8, url));
}

// Input-related functions: keyboard

/// Check if a key has been pressed once
pub fn IsKeyPressed(key: t.KeyboardKey) bool {
    return r.IsKeyPressed(@enumToInt(key));
}

/// Check if a key is being pressed
pub fn IsKeyDown(key: t.KeyboardKey) bool {
    return r.IsKeyDown(@enumToInt(key));
}

/// Check if a key has been released once
pub fn IsKeyReleased(key: t.KeyboardKey) bool {
    return r.IsKeyReleased(@enumToInt(key));
}

/// Check if a key is NOT being pressed
pub fn IsKeyUp(key: t.KeyboardKey) bool {
    return r.IsKeyUp(@enumToInt(key));
}

/// Set a custom key to exit program (default is ESC)
pub fn SetExitKey(key: t.KeyboardKey) void {
    r.SetExitKey(@enumToInt(key));
}

/// Get key pressed (keycode), call it multiple times for keys queued, returns 0 when the queue is empty
pub fn GetKeyPressed() t.KeyboardKey {
    return @intToEnum(t.KeyboardKey, r.GetKeyPressed());
}

/// Get char pressed (unicode), call it multiple times for chars queued, returns 0 when the queue is empty
pub fn GetCharPressed() c_int {
    return r.GetCharPressed();
}
