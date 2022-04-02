#include "raylib.h"
#include "raymath.h"
#include "extras/raygui.h"
    
void mInitWindow(int width, int height, const char *title);

bool mWindowShouldClose();

void mCloseWindow();

void mSetWindowMinSize(int width, int height);

void mSetWindowSize(int width, int height);

int mGetScreenWidth();

int mGetScreenHeight();

bool mIsCursorOnScreen();

void mClearBackground(Color *color);

void mBeginDrawing();

void mEndDrawing();

void mBeginMode2D(Camera2D *camera);

void mEndMode2D();

void mGetCameraMatrix2D(Matrix *out, Camera2D *camera);

void mGetWorldToScreen2D(Vector2 *out, Vector2 *position, Camera2D *camera);

void mGetScreenToWorld2D(Vector2 *out, Vector2 *position, Camera2D *camera);

void mSetTargetFPS(int fps);

int mGetFPS();

float mGetFrameTime();

double mGetTime();

void mOpenURL(const char *url);

bool mIsKeyPressed(int key);

bool mIsKeyDown(int key);

bool mIsKeyReleased(int key);

bool mIsKeyUp(int key);

void mSetExitKey(int key);

int mGetKeyPressed();

int mGetCharPressed();

bool mIsMouseButtonPressed(int button);

bool mIsMouseButtonDown(int button);

bool mIsMouseButtonReleased(int button);

bool mIsMouseButtonUp(int button);

void mGetMousePosition(Vector2 *out);

void mGetMouseDelta(Vector2 *out);

void mSetMouseOffset(int offsetX, int offsetY);

void mSetMouseScale(float scaleX, float scaleY);

float mGetMouseWheelMove();

void mSetMouseCursor(int cursor);

void mGetTouchPosition(Vector2 *out, int index);

int mGetTouchPointCount();

void mDrawLineEx(Vector2 *startPos, Vector2 *endPos, float thick, Color *color);

void mDrawRectanglePro(Rectangle *rec, Vector2 *origin, float rotation, Color *color);

void mLoadTexture(Texture2D *out, const char *fileName);

void mUnloadTexture(Texture2D *texture);

void mDrawTexturePro(Texture2D *texture, Rectangle *source, Rectangle *dest, Vector2 *origin, float rotation, Color *tint);

void mDrawFPS(int posX, int posY);

void mDrawText(const char *text, int posX, int posY, int fontSize, Color *color);
