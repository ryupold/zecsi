const r = @cImport({
    @cInclude("raylib_marshall.h");
});

const t = @import("types.zig");

pub fn MatrixIdentity() t.Matrix {
    var out: t.Matrix = undefined;
    r.mMatrixIdentity(@ptrCast([*c]r.Matrix, &out));
    return out;
}

pub fn MatrixMultiply(left: t.Matrix, right: t.Matrix) t.Matrix {
    var out: t.Matrix = undefined;
    r.mMatrixMultiply(@ptrCast([*c]r.Matrix, &out), @ptrCast([*c]r.Matrix, &left), @ptrCast([*c]r.Matrix, &right));
    return out;
}

pub fn QuaternionFromMatrix(mat: t.Matrix) t.Quaternion {
    var out: t.Quaternion = undefined;
    r.mQuaternionFromMatrix(@ptrCast([*c]r.Quaternion, &out), @ptrCast([*c]r.Matrix, &mat));
    return out;
}

pub fn QuaternionFromAxisAngle(axis: t.Vector3, angle: f32) t.Quaternion {
    var out: t.Quaternion = undefined;
    r.mQuaternionFromAxisAngle(@ptrCast([*c]r.Quaternion, &out), @ptrCast([*c]r.Vector3, &axis), angle);
    return out;
}

pub fn QuaternionToAxisAngle(q: t.Quaternion) struct {
    axis: t.Vector3,
    angle: f32,
} {
    var outAxis: t.Vector3 = undefined;
    var outAngle: f32 = undefined;
    r.mQuaternionFromAxisAngle(
        @ptrCast([*c]r.Quaternion, &q),
        @ptrCast([*c]r.Vector3, &outAxis),
        @ptrCast([*c]f32, &outAngle),
    );
    return .{
        .axis = outAxis,
        .angle = outAngle,
    };
}
