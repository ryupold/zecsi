const r = @import("ray/raylib.zig");
const ecs = @import("ecs.zig");

pub const Transform = struct {
    position: r.Vector3 = r.Vector3.zero(),
    rotation: r.Quaternion = r.Quaternion.fromAngleAxis(r.Vector3.forward(), 0),
    scale: r.Vector3 = r.Vector3.one(),
    parent: ?ecs.TypedComponent(Transform) = null,

    fn transform(self: @This()) r.Matrix {
        const x = self.rotation.x;
        const y = self.rotation.y;
        const z = self.rotation.z;
        const w = self.rotation.w;
        const x2 = x + x;
        const y2 = y + y;
        const z2 = z + z;
        const xx = x * x2;
        const xy = x * y2;
        const xz = x * z2;
        const yy = y * y2;
        const yz = y * z2;
        const zz = z * z2;
        const wx = w * x2;
        const wy = w * y2;
        const wz = w * z2;
        var m = r.Matrix{
            .m0 = (1.0 - (yy + zz)) * self.scale.x,
            .m1 = (xy + wz) * self.scale.x,
            .m2 = (xz - wy) * self.scale.x,
            .m3 = (0.0) * self.scale.x,
            .m4 = (xy - wz) * self.scale.y,
            .m5 = (1.0 - (xx + zz)) * self.scale.y,
            .m6 = (yz + wx) * self.scale.y,
            .m7 = (0.0) * self.scale.y,
            .m8 = (xz + wy) * self.scale.z,
            .m9 = (yz - wx) * self.scale.z,
            .m10 = (1.0 - (xx + yy)) * self.scale.z,
            .m11 = (0.0) * self.scale.z,
            .m12 = self.position.x,
            .m13 = self.position.y,
            .m14 = self.position.z,
            .m15 = 1.0,
        };
    }

    fn worldTransform(self: @This()) r.Matrix {
        if (self.parent == null) return self.transform();

        r.MatrixMultiply(self.parent.?.worldTransform(), self.transform());
    }

    fn worldPosition(self: @This()) r.Vector3 {
        const m = self.worldTransform();
        return r.Vector3{ .x = m.m14, .y = m.m13, .z = m.m12 };
    }

    fn worlRotation(self: @This()) r.Quaternion {
        const m = self.worldTransform();
        return r.QuaternionFromMatrix(m);
    }

    fn worldScale(self: @This()) r.Vector3 {
        const m = self.worldTransform();
        var v = r.Vector3.zero();
        v.x = m.m0;
        v.y = m.m1;
        v.z = m.m2;
        const sx = v.length();
        v.x = m.m4;
        v.y = m.m5;
        v.z = m.m6;
        const sy = v.length();
        v.x = m.m8;
        v.y = m.m9;
        v.z = m.m10;
        const sz = v.length();
        v.x = sx;
        v.y = sy;
        v.z = sz;
        return v;
    }
};
