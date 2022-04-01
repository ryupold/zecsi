#include "raylib.h"
#include "raymath.h"

void mInitWindow(int width, int height, const char *title)
{
    InitWindow(width, height, title);
}

int mGetScreenWidth(void)
{
    return GetScreenWidth();
}

int mGetScreenHeight(void)
{
    return GetScreenHeight();
}

void mSetWindowSize(int width, int height)
{
    SetWindowSize(width, height);
}

void mCloseWindow(void)
{
    CloseWindow();
}

bool mWindowShouldClose(void)
{
    return WindowShouldClose();
}

void mSetTargetFPS(int fps)
{
    SetTargetFPS(fps);
}

void mBeginDrawing()
{
    BeginDrawing();
}

void mEndDrawing()
{
    EndDrawing();
}

void mBeginMode2D(Camera2D *camera)
{
    BeginMode2D(*camera);
}
void mEndMode2D(void)
{
    EndMode2D();
}
void mGetCameraMatrix2D(Matrix *outMatrix, Camera2D *camera)
{
    *outMatrix = GetCameraMatrix2D(*camera);
}

void mGetWorldToScreen2D(Vector2 *out, Vector2 *position, Camera2D *camera)
{
    *out = GetWorldToScreen2D(*position, *camera);
}

void mGetScreenToWorld2D(Vector2 *out, Vector2 *position, Camera2D *camera)
{
    *out = GetScreenToWorld2D(*position, *camera);
}

void mClearBackground(Color *color)
{
    ClearBackground(*color);
}

void mDrawText(const char *text, int posX, int posY, int fontSize, Color *color)
{
    DrawText(text, posX, posY, fontSize, *color);
}

void mDrawFPS(int posX, int posY)
{
    DrawFPS(posX, posY);
}

int mGetFPS(void)
{
    return GetFPS();
}

float mGetFrameTime(void)
{
    return GetFrameTime();
}

double mGetTime(void)
{
    return GetTime();
}

//=== Textures ====================================================================================

void mLoadTexture(Texture2D *outTex, const char *fileName)
{
    Texture2D tex = LoadTexture(fileName);
    *outTex = tex;
}

void mDrawTexturePro(Texture2D *texture, Rectangle *source, Rectangle *dest, Vector2 *origin, float rotation, Color *tint)
{
    DrawTexturePro(*texture, *source, *dest, *origin, rotation, *tint);
}
void mUnloadTexture(Texture2D *texture)
{
    UnloadTexture(*texture);
}

//=== File System =================================================================================

unsigned char *mLoadFileData(const char *fileName, unsigned int *bytesRead)
{
    return LoadFileData(fileName, bytesRead);
}
void mUnloadFileData(unsigned char *data)
{
    UnloadFileData(data);
}

//=== Input =================================================================================
int mGetTouchPointCount(void)
{
    return GetTouchPointCount();
}

void mGetTouchPosition(int index, Vector2 *outPosition)
{
    *outPosition = GetTouchPosition(index);
}

void mGetMousePosition(Vector2 *outPosition)
{
    *outPosition = GetMousePosition();
}

void mGetMouseDelta(Vector2 *outDelta)
{
    *outDelta = GetMouseDelta();
}

bool mIsCursorOnScreen(void)
{
    return IsCursorOnScreen();
}

bool mIsMouseButtonDown(int button)
{
    return IsMouseButtonDown(button);
}
bool mIsMouseButtonPressed(int button)
{
    return IsMouseButtonPressed(button);
}
bool mIsMouseButtonReleased(int button)
{
    return IsMouseButtonReleased(button);
}
bool mIsMouseButtonUp(int button)
{
    return IsMouseButtonUp(button);
}

void mSetMouseOffset(int offsetX, int offsetY)
{
    SetMouseOffset(offsetX, offsetY);
}
void mSetMouseScale(float scaleX, float scaleY)
{
    SetMouseScale(scaleX, scaleY);
}
float mGetMouseWheelMove(void)
{
    return GetMouseWheelMove();
}
void mSetMouseCursor(int cursor)
{
    SetMouseCursor(cursor);
}

//=== Math =================================================================================

void mMatrixIdentity(Matrix *outMatrix)
{
    *outMatrix = MatrixIdentity();
}

void mMatrixMultiply(Matrix *outMatrix, Matrix *left, Matrix *right)
{
    *outMatrix = MatrixMultiply(*left, *right);
}

void mQuaternionFromMatrix(Quaternion *outQ, Matrix *mat)
{
    *outQ = QuaternionFromMatrix(*mat);
}

void mQuaternionFromAxisAngle(Quaternion *outQ, Vector3 *axis, float angle)
{
    *outQ = QuaternionFromAxisAngle(*axis, angle);
}
void mQuaternionToAxisAngle(Quaternion *q, Vector3 *outAxis, float *outAngle)
{
    QuaternionToAxisAngle(*q, outAxis, outAngle);
}

//=== Shapes ===============================================================================
void mDrawLineEx(Vector2 *startPos, Vector2 *endPos, float thick, Color *color)
{
    DrawLineEx(*startPos, *endPos, thick, *color);
}

void mDrawRectanglePro(Rectangle *rec, Vector2 *origin, float rotation, Color *color)
{
    DrawRectanglePro(*rec, *origin, rotation, *color);
}