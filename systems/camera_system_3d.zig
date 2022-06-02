const std = @import("std");
const builtin = @import("builtin");
const log = @import("../log.zig");
const _ecs = @import("../ecs/ecs.zig");
const r = @import("../raylib/raylib.zig");
const ECS = _ecs.ECS;
const Entity = _ecs.Entity;
const Component = _ecs.Component;
const vouch = @import("../utils.zig").vouch;
const ignore = @import("../utils.zig").ignore;

var _camera: Component = undefined;
var _ecsInstance: *ECS = undefined;

pub const CameraSystem3D = struct {
    pub const Self = @This();
    ecs: *ECS,
    camera: _ecs.EntityID,
    ///just saving this ref for quicker reference
    camRef: Component,

    pub fn init(ecs: *ECS) !Self {
        var cam = try ecs.createWithCapacity(5);
        var system = Self{
            .ecs = ecs,
            .camera = cam.id,
            .camRef = try ecs.add(cam, r.Camera3D{
                .position = r.Vector3.zero(),
                .target = r.Vector3.zero(),
                .up = .{ .y = 1 },
                .fovy = 45,
                .projection = .CAMERA_PERSPECTIVE,
            }),
        };

        std.debug.print("Camera entity: {?}", .{cam});

        _camera = system.camRef;
        _ecsInstance = ecs;

        return system;
    }

    pub fn deinit(_: *@This()) void {}

    pub fn before(self: *Self, _: f32) !void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            r.BeginMode3D(cam.*);
        }
    }

    pub fn update(self: *Self, _: f32) !void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            r.UpdateCamera(cam);
        }
    }

    /// cast a ray forward from screen pos and detect hit point on XZ plane
    pub fn screenToWorldXZ(self: Self, screenPos: r.Vector2, config: struct {
        extend: f32 = 1000,
        offset: r.Vector3 = .{},
    }) r.Vector3 {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            var ray = r.GetMouseRay(screenPos, cam);
            const v = r.Vector2{ .x = config.extend, .z = config.extend };
            const collision = r.GetRayCollisionQuad(
                ray,
                (r.Vector3{ .x = -v.x, .z = -v.z }).add(config.offset),
                (r.Vector3{ .x = v.x, .z = -v.z }).add(config.offset),
                (r.Vector3{ .x = -v.x, .z = v.z }).add(config.offset),
                (r.Vector3{ .x = -v.x, .z = -v.z }).add(config.offset),
            );
            return collision.point;
        }
        return r.Vector3.zero();
    }

    /// transform a (x,y) world position to screen coordinates
    pub fn worldToScreen(self: Self, worldPos: r.Vector3) r.Vector2 {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            return r.GetWorldToScreen(worldPos, cam);
        }
        return r.Vector2.zero();
    }

    pub fn after(self: *Self, _: f32) !void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |_| {
            r.EndMode3D();
        }
    }

    //=== CAM functions ===========================================================================
    pub fn getCam(self: Self) r.Camera3D {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            return cam;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCam(self: Self, cam: r.Camera3D) void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |c| {
            c.* = cam;
        }
    }

    pub fn setCamMode(self: Self, mode: r.CameraMode) void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            r.SetCameraMode(cam.*, mode);
        }
    }

    pub fn getCamPos(self: Self) r.Vector3 {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            return cam.position;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCamPos(self: Self, pos: r.Vector3) void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            cam.position = pos;
        }
    }

    pub fn getCamTarget(self: Self) r.Vector3 {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            return cam.target;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCamTarget(self: Self, target: r.Vector3) void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            cam.target = target;
        }
    }

    pub fn getCamUp(self: Self) r.Vector3 {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            return cam.up;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCamUp(self: Self, up: r.Vector3) void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            cam.up = up;
        }
    }

    pub fn getCamFovY(self: Self) f32 {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            return cam.fovy;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCamFovY(self: Self, fovy: f32) void {
        if (self.ecs.getPtr(r.Camera3D, self.camRef)) |cam| {
            cam.fovy = fovy;
        }
    }
};
