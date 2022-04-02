#include "raylib.h"
#include "raymath.h"
#include "extras/raygui.h"
    
void mInitWindow(int width, int height, const char *title) 
 {
    return InitWindow(width, height, title);
}

bool mWindowShouldClose() 
 {
    return WindowShouldClose();
}

void mCloseWindow() 
 {
    return CloseWindow();
}

void mSetWindowMinSize(int width, int height) 
 {
    return SetWindowMinSize(width, height);
}

void mSetWindowSize(int width, int height) 
 {
    return SetWindowSize(width, height);
}

int mGetScreenWidth() 
 {
    return GetScreenWidth();
}

int mGetScreenHeight() 
 {
    return GetScreenHeight();
}

bool mIsCursorOnScreen() 
 {
    return IsCursorOnScreen();
}

void mClearBackground(Color *color) 
 {
    return ClearBackground(*color);
}

void mBeginDrawing() 
 {
    return BeginDrawing();
}

void mEndDrawing() 
 {
    return EndDrawing();
}

void mBeginMode2D(Camera2D *camera) 
 {
    return BeginMode2D(*camera);
}

void mEndMode2D() 
 {
    return EndMode2D();
}

void mGetCameraMatrix2D(Matrix *out, Camera2D *camera) 
 {
    *out = GetCameraMatrix2D(*camera);
}

void mGetWorldToScreen2D(Vector2 *out, Vector2 *position, Camera2D *camera) 
 {
    *out = GetWorldToScreen2D(*position, *camera);
}

void mGetScreenToWorld2D(Vector2 *out, Vector2 *position, Camera2D *camera) 
 {
    *out = GetScreenToWorld2D(*position, *camera);
}

void mSetTargetFPS(int fps) 
 {
    return SetTargetFPS(fps);
}

int mGetFPS() 
 {
    return GetFPS();
}

float mGetFrameTime() 
 {
    return GetFrameTime();
}

double mGetTime() 
 {
    return GetTime();
}

void mOpenURL(const char *url) 
 {
    return OpenURL(url);
}

bool mIsKeyPressed(int key) 
 {
    return IsKeyPressed(key);
}

bool mIsKeyDown(int key) 
 {
    return IsKeyDown(key);
}

bool mIsKeyReleased(int key) 
 {
    return IsKeyReleased(key);
}

bool mIsKeyUp(int key) 
 {
    return IsKeyUp(key);
}

void mSetExitKey(int key) 
 {
    return SetExitKey(key);
}

int mGetKeyPressed() 
 {
    return GetKeyPressed();
}

int mGetCharPressed() 
 {
    return GetCharPressed();
}

bool mIsMouseButtonPressed(int button) 
 {
    return IsMouseButtonPressed(button);
}

bool mIsMouseButtonDown(int button) 
 {
    return IsMouseButtonDown(button);
}

bool mIsMouseButtonReleased(int button) 
 {
    return IsMouseButtonReleased(button);
}

bool mIsMouseButtonUp(int button) 
 {
    return IsMouseButtonUp(button);
}

void mGetMousePosition(Vector2 *out) 
 {
    *out = GetMousePosition();
}

void mGetMouseDelta(Vector2 *out) 
 {
    *out = GetMouseDelta();
}

void mSetMouseOffset(int offsetX, int offsetY) 
 {
    return SetMouseOffset(offsetX, offsetY);
}

void mSetMouseScale(float scaleX, float scaleY) 
 {
    return SetMouseScale(scaleX, scaleY);
}

float mGetMouseWheelMove() 
 {
    return GetMouseWheelMove();
}

void mSetMouseCursor(int cursor) 
 {
    return SetMouseCursor(cursor);
}

void mGetTouchPosition(Vector2 *out, int index) 
 {
    *out = GetTouchPosition(index);
}

int mGetTouchPointCount() 
 {
    return GetTouchPointCount();
}

void mDrawLineEx(Vector2 *startPos, Vector2 *endPos, float thick, Color *color) 
 {
    return DrawLineEx(*startPos, *endPos, thick, *color);
}

void mDrawRectanglePro(Rectangle *rec, Vector2 *origin, float rotation, Color *color) 
 {
    return DrawRectanglePro(*rec, *origin, rotation, *color);
}

void mLoadTexture(Texture2D *out, const char *fileName) 
 {
    *out = LoadTexture(fileName);
}

void mUnloadTexture(Texture2D *texture) 
 {
    return UnloadTexture(*texture);
}

void mDrawTexturePro(Texture2D *texture, Rectangle *source, Rectangle *dest, Vector2 *origin, float rotation, Color *tint) 
 {
    return DrawTexturePro(*texture, *source, *dest, *origin, rotation, *tint);
}

void mDrawFPS(int posX, int posY) 
 {
    return DrawFPS(posX, posY);
}

void mDrawText(const char *text, int posX, int posY, int fontSize, Color *color) 
 {
    return DrawText(text, posX, posY, fontSize, *color);
}
