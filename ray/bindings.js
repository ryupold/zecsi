const generateBindingsFor = [
  //window
  "InitWindow",
  "SetWindowSize",
  "SetWindowMinSize",
  "WindowShouldClose",
  "CloseWindow",
  "GetScreenWidth",
  "GetScreenHeight",
  "SetWindowMonitor",
  "SetWindowPosition",

  //data
  "OpenURL",

  //timing
  "SetTargetFPS",
  "GetFPS",
  "GetFrameTime",
  "GetTime",

  //camera
  "BeginMode2D",
  "GetScreenToWorld2D",
  "GetWorldToScreen2D",
  "EndMode2D",
  "GetCameraMatrix2D",

  //drawing
  "ClearBackground",
  "BeginDrawing",
  "EndDrawing",

  //shapes
  "DrawLineEx",
  "DrawRectanglePro",

  //textures
  "LoadTexture",
  "UnloadTexture",
  "DrawTextureEx",
  "DrawTexturePro",
  "DrawTextureRec",

  //text
  "DrawText",
  "DrawFPS",

  //touch
  "GetTouchPointCount",
  "GetTouchPosition",

  //mouse
  "IsCursorOnScreen",
  "GetMousePosition",
  "GetMouseDelta",
  "IsMouseButtonDown",
  "IsMouseButtonPressed",
  "IsMouseButtonReleased",
  "IsMouseButtonUp",
  "SetMouseOffset",
  "SetMouseScale",
  "GetMouseWheelMove",
  "SetMouseCursor",

  //keyboard
  "IsKeyPressed",
  "IsKeyDown",
  "IsKeyReleased",
  "IsKeyUp",
  "SetExitKey",
  "GetKeyPressed",
  "GetCharPressed",

  //math
  "MatrixIdentity",
  "MatrixMultiply",
  "QuaternionFromMatrix",
  "QuaternionFromAxisAngle",
  "QuaternionToAxisAngle",
];

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

const fs = require("fs");
const inputFiles = [`../raylib/src/raylib.h`, `../raylib/src/extras/raygui.h`];
const outputFile = {
  zig: "./gen.zig",
  h: "../emscripten/raylib_marshall_gen.h",
  c: "../emscripten/raylib_marshall_gen.c",
};
const inputCode = inputFiles
  .map((inputFile) => fs.readFileSync(inputFile).toString("utf-8"))
  .join("\n");

const nameAndReturnRx =
  /^(?:RAYGUIAPI|RLAPI)\s+(\w+)\s+(\w+)\s*\(([A-Za-z-0-9*, ]*)\)\s*;/gm;
const nameAndReturnLineRx =
  /^(?:RAYGUIAPI|RLAPI)\s+(\w+)\s+(\w+)\s*\(([A-Za-z-0-9*, ]*)\)\s*;/m;
const parameterRxAll =
  /(?:((?:(?:const )?(?:unsigned )?)?\w+)\s+(\*?)\s*(\w+)(,|$))/g;
const parameterRx =
  /(?:((?:(?:const )?(?:unsigned )?)?\w+)\s+(\*?)\s*(\w+)(,|$))/;
const noParametersRx = /void/;

/**
 * t: type in c function
 * p: is pointer (bool)
 * z: zig argument type
 * s: is struct (needs to be passed as pointer)
 * n: how to map the parameter before call, e.g.: (a) => `@ptrCast([*c]const u8, ${a.n})`
 */
const argMap = [
  { t: "void", p: false, z: "void", n: (a) => undefined },
  {
    t: "const char",
    p: true,
    z: "[]const u8",
    n: (a) => `@ptrCast([*c]const u8, ${a.n}.ptr)`,
  },
  { t: "bool", p: false, z: "bool", n: (a) => `${a.n}` },
  { t: "float", p: false, z: "f32", n: (a) => `${a.n}` },
  { t: "double", p: false, z: "f64", n: (a) => `${a.n}` },
  { t: "int", p: false, z: "i32", n: (a) => `@intCast(c_int, ${a.n})` },
  {
    t: "Font",
    p: false,
    z: "t.Font",
    s: true,
    n: (a) => `@ptrCast([*c]r.${a.t}, &_${a.n})`,
  },
  {
    t: "Rectangle",
    p: false,
    z: "t.Rectangle",
    s: true,
    n: (a) => `@ptrCast([*c]r.${a.t}, &_${a.n})`,
  },
  {
    t: "Camera2D",
    p: false,
    z: "t.Camera2D",
    s: true,
    n: (a) => `@ptrCast([*c]r.${a.t}, &_${a.n})`,
  },
  {
    t: "Vector2",
    p: false,
    z: "t.Vector2",
    s: true,
    n: (a) => `@ptrCast([*c]r.${a.t}, &_${a.n})`,
  },
  {
    t: "Color",
    p: false,
    z: "t.Color",
    s: true,
    n: (a) => `@ptrCast([*c]r.${a.t}, &_${a.n})`,
  },
  {
    t: "Matrix",
    p: false,
    z: "t.Matrix",
    s: true,
    n: (a) => `@ptrCast([*c]r.${a.t}, &_${a.n})`,
  },
  {
    t: "Texture2D",
    p: false,
    z: "t.Texture2D",
    s: true,
    n: (a) => `@ptrCast([*c]r.${a.t}, &_${a.n})`,
  },
];

/**
 * returns mapping entry:
 *  - t = type
 *  - p = is pointer
 *  - n = name
 *  to corresponding Zig function arguments if they are defined in argMap
 * @param arg - {t: string, p: boolean, n: string}
 * @returns {name: string, ...entry, cn: string}
 */
function getMapping(arg) {
  for (const entry of argMap) {
    if (arg.t === entry.t && arg.p === entry.p) {
      return { name: arg.n, ...entry, cn: entry.n(arg) };
    }
  }
  throw new Error(`unknown arg type ${arg.t} ${arg.p ? "*" : ""}${arg.n}`);
}

function mapFunction(m) {
  const returnType = m[1];
  const functionName = m[2];
  const parameters = m[3];

  if (!generateBindingsFor.includes(functionName)) {
    return undefined;
  }
  console.log(`generating binding for: ${functionName}`);

  const mParams = parameters.match(parameterRxAll);
  const hasNoParameters = !mParams || noParametersRx.test(mParams[0]);
  const args = hasNoParameters
    ? null
    : mParams.map((arg) => {
        const pm = arg.match(parameterRx);
        return { t: pm[1], p: pm[2] === "*", n: pm[3] };
      });
  const mappedArgs = hasNoParameters ? [] : args.map(getMapping);
  const mappedReturn = getMapping({ t: returnType, p: false, n: "out" });
  const zigSignature = `pub fn ${functionName} (${mappedArgs
    .map((a) => `${a.name}: ${a.z}`)
    .join(", ")}) ${mappedReturn.z}`;
  //--- Zig body -----------------
  let zigBody = "{";
  //converting all structs
  for (const arg of mappedArgs) {
    if (arg.s) {
      zigBody += `var _${arg.name} = ${arg.name};\n`;
    }
  }
  if (mappedReturn.s) {
    zigBody += `var _out: ${mappedReturn.z} = undefined;\n`;
  }

  //calling the c function
  if (mappedReturn.s) {
    zigBody += `\n    r.m${functionName}(\n`;
    zigBody += `        ${mappedReturn.cn},\n`;
  } else if (mappedReturn.t === "void") {
    zigBody += `\n    r.m${functionName}(\n`;
  } else {
    zigBody += `\n    return r.m${functionName}(\n`;
  }
  for (const arg of mappedArgs) {
    zigBody += `        ${arg.cn},\n`;
  }
  zigBody += "    );";

  if (mappedReturn.s) {
    zigBody += "    return _out;";
  }

  zigBody += "}";
  //-----------------------------

  //--- C Header ----------------
  let cSignature = `${mappedReturn.s ? "void" : returnType} m${functionName}(`;

  if (mappedReturn.s)
    cSignature += [mappedReturn, ...mappedArgs]
      .map((a) => `${a.t} ${a.p || a.s ? "*" : ""}${a.name}`)
      .join(", ");
  else if (hasNoParameters) {
    cSignature += 'void';
  } else
    cSignature += mappedArgs
      .map((a) => `${a.t} ${a.p || a.s ? "*" : ""}${a.name}`)
      .join(", ");

  cSignature += ")";

  let cBody = `{\n`;

  if (mappedReturn.s) cBody += `    *${mappedReturn.name} = ${functionName}(`;
  else if (mappedReturn.t === "void") cBody += `    ${functionName}(`;
  else cBody += `    return ${functionName}(`;

  cBody += `${mappedArgs.map((a) => `${a.s ? "*" : ""}${a.name}`).join(", ")}`;
  cBody += `);\n`;
  cBody += `}`;

  //-----------------------------

  return {
    zig: `${zigSignature} ${zigBody}`,
    h: `${cSignature};`,
    c: `${cSignature} \n ${cBody}`,
  };
}

let generatedZig = [];
let generatedH = [];
let generatedC = [];
for (let functionCall of inputCode.match(nameAndReturnRx)) {
  const out = mapFunction(functionCall.match(nameAndReturnLineRx));
  if (out) {
    generatedZig.push(out.zig);
    generatedH.push(out.h);
    generatedC.push(out.c);
  }
}

if (generateBindingsFor.length !== generatedZig.length) {
  console.log('not all functions of "generateBindingsFor" were generated');
}

//=== Write Zig =================================
fs.writeFileSync(
  outputFile.zig,
  `const std = @import("std");
    const r = @cImport({
        @cInclude("raylib_marshall.h");
    });
    const t = @import("types.zig");
    const cPtr = t.asCPtr;
    
    ${generatedZig.join("\n\n")}
`
);
console.log(`written to ${outputFile.zig}:`);

//=== C Header ==================================
fs.writeFileSync(
  outputFile.h,
  `#include "raylib.h"
#include "raymath.h"
#include "extras/raygui.h"
    
${generatedH.join("\n\n")}
`
);
console.log(`written to ${outputFile.h}:`);

//=== C Implementation ==========================
fs.writeFileSync(
  outputFile.c,
  `#include "raylib.h"
#include "raymath.h"
#include "extras/raygui.h"
    
${generatedC.join("\n\n")}
`
);
console.log(`written to ${outputFile.c}`);
