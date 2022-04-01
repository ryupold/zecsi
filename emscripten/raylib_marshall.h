#include "raylib.h"
#include "raymath.h"
#include "extras/raygui.h"

void mInitWindow(int width, int height, const char *title);
int mGetScreenWidth(void);
int mGetScreenHeight(void);
void mSetWindowSize(int width, int height);

void mCloseWindow(void);
bool mWindowShouldClose(void);
void mSetTargetFPS(int fps);

void mBeginDrawing(void);
void mEndDrawing(void);

// Camera
void mBeginMode2D(Camera2D *camera);
void mEndMode2D(void);
void mGetCameraMatrix2D(Matrix *outMatrix, Camera2D *camera);
void mGetWorldToScreen2D(Vector2 *out, Vector2 *position, Camera2D *camera);
void mGetScreenToWorld2D(Vector2 *out, Vector2 *position, Camera2D *camera);

void mClearBackground(Color *color);

void mDrawText(const char *text, int posX, int posY, int fontSize, Color *color);
void mDrawFPS(int posX, int posY);

int mGetFPS(void);
float mGetFrameTime(void);
double mGetTime(void);

// Image
//  void mLoadImage(Image *outImage, const char *fileName);
//  void mUnloadImage(Image *image);

// Textures
void mLoadTexture(Texture2D *outTex, const char *fileName);
void mDrawTexturePro(Texture2D *texture, Rectangle *source, Rectangle *dest, Vector2 *origin, float rotation, Color *tint);
void mUnloadTexture(Texture2D *texture);

// File System
unsigned char *mLoadFileData(const char *fileName, unsigned int *bytesRead);
void mUnloadFileData(unsigned char *data);

// Input
int mGetTouchPointCount(void);
void mGetTouchPosition(int index, Vector2 *outPosition);
bool mIsCursorOnScreen(void);
void mGetMousePosition(Vector2 *outPosition);
bool mIsMouseButtonDown(int button);
bool mIsMouseButtonPressed(int button);
bool mIsMouseButtonReleased(int button);
bool mIsMouseButtonUp(int button);
void mGetMouseDelta(Vector2 *outDelta);
void mSetMouseOffset(int offsetX, int offsetY);
void mSetMouseScale(float scaleX, float scaleY);
float mGetMouseWheelMove(void);
void mSetMouseCursor(int cursor);

// Math
void mMatrixIdentity(Matrix *out);
void mMatrixMultiply(Matrix *out, Matrix *left, Matrix *right);
void mQuaternionFromMatrix(Quaternion *out, Matrix *mat);
void mQuaternionFromAxisAngle(Quaternion *out, Vector3 *axis, float angle);
void mQuaternionToAxisAngle(Quaternion *q, Vector3 *outAxis, float *outAngle);

// Shapes
void mDrawLineEx(Vector2 *startPos, Vector2 *endPos, float thick, Color *color);
void mDrawRectanglePro(Rectangle *rec, Vector2 *origin, float rotation, Color *color);