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

pub const CameraMouseDrag = struct {
    button: r.MouseButton = .MOUSE_BUTTON_LEFT,
    _oldCameraPos: ?r.Vector2 = null,
    _dragStart: ?r.Vector2 = null,
};

pub const CameraScrollZoom = struct {
    factor: f32 = 1,
};

pub const CameraWASD = struct {
    speed: f32 = 1,
    up: r.KeyboardKey = .KEY_UP,
    right: r.KeyboardKey = .KEY_RIGHT,
    down: r.KeyboardKey = .KEY_DOWN,
    left: r.KeyboardKey = .KEY_LEFT,
};

pub const TwoFingerZoomAndDrag = struct {
    factor: f32 = 1,
    _oldCameraZoom: ?f32 = null,
    _oldCameraPos: ?r.Vector2 = null,
    _startFingerPositions: ?struct { a: r.Vector2, b: r.Vector2 } = null,
};

var _camera: ?Component = null;
var _ecsInstance: ?*ECS = null;

pub const CameraSystem = struct {
    pub const Self = @This();
    ecs: *ECS,
    camera: _ecs.EntityID,
    ///just saving this ref for quicker reference
    camRef: Component,

    pub fn init(ecs: *ECS) !Self {
        const cam = try ecs.createWithCapacity(5);
        var system = Self{
            .ecs = ecs,
            .camera = cam.id,
            .camRef = try ecs.add(cam, r.Camera2D{
                .target = r.Vector2.zero(),
                .offset = .{
                    .x = ecs.window.size.x / 2,
                    .y = ecs.window.size.y / 2,
                },
            }),
        };

        std.debug.print("Camera entity: {?}", .{cam});

        _camera = system.camRef;
        _ecsInstance = ecs;

        return system;
    }

    pub fn deinit(_: *@This()) void {}

    pub fn before(self: *Self, _: f32) !void {
        var cam = self.ecs.getPtr(r.Camera2D, self.camRef).?;
        cam.offset.x = self.ecs.window.size.x / 2;
        cam.offset.y = self.ecs.window.size.y / 2;

        self.applyMouseDrag(cam);
        self.applyZoomByScrollWheel(cam);
        self.applyTouchDragAndZoom(cam);
        self.applyWASDMovement(cam);

        r.BeginMode2D(cam.*);
    }

    pub fn update(_: *Self, _: f32) !void {}

    fn applyMouseDrag(self: *Self, cam: *r.Camera2D) void {
        if (self.ecs.getOnePtr(self.camera, CameraMouseDrag)) |onDrag| {
            if (r.IsMouseButtonPressed(onDrag.button)) {
                const mousePos = r.GetMousePosition(); //self.screenToWorld(r.GetMousePosition());
                onDrag._dragStart = mousePos;
                onDrag._oldCameraPos = cam.target;
            }
            if (onDrag._oldCameraPos != null and r.IsMouseButtonDown(onDrag.button)) {
                const mousePos = r.GetMousePosition(); //self.screenToWorld(r.GetMousePosition());
                const delta = mousePos.sub(onDrag._dragStart.?);
                cam.target = onDrag._oldCameraPos.?.sub(delta.scale(1 / cam.zoom));
            }
            if (r.IsMouseButtonReleased(onDrag.button)) {
                onDrag._dragStart = null;
                onDrag._oldCameraPos = null;
            }
        }
    }

    fn applyZoomByScrollWheel(self: *Self, cam: *r.Camera2D) void {
        const wheelMove = switch (builtin.os.tag) {
            .wasi, .emscripten, .freestanding => r.GetMouseWheelMove() * -1,
            else => r.GetMouseWheelMove(),
        };
        if (wheelMove != 0) {
            if (self.ecs.getOnePtr(self.camera, CameraScrollZoom)) |onScroll| {
                cam.zoom = std.math.clamp((cam.zoom + wheelMove * onScroll.factor * cam.zoom), 0.1, 1000);
            }
        }
    }

    fn applyTouchDragAndZoom(self: *Self, cam: *r.Camera2D) void {
        if (self.ecs.getOnePtr(self.camera, TwoFingerZoomAndDrag)) |onTwoFingers| {
            if (r.GetTouchPointCount() == 2) {
                const a = r.GetTouchPosition(0);
                const b = r.GetTouchPosition(1);
                const center = a.lerp(b, 0.5);
                const distance = a.distanceTo(b);
                if (onTwoFingers._startFingerPositions == null) {
                    onTwoFingers._oldCameraZoom = cam.zoom;
                    onTwoFingers._oldCameraPos = cam.target;
                    onTwoFingers._startFingerPositions = .{ .a = a, .b = b };
                } else {
                    const startA = onTwoFingers._startFingerPositions.?.a;
                    const startB = onTwoFingers._startFingerPositions.?.b;
                    const startCenter = startA.lerp(startB, 0.5);
                    const startDistance = startA.distanceTo(startB);
                    const centerDelta = center.sub(startCenter);
                    const zoomFactor = distance / startDistance - 1;

                    cam.target = onTwoFingers._oldCameraPos.?.sub(centerDelta.scale(1 / cam.zoom));
                    cam.zoom = std.math.clamp((onTwoFingers._oldCameraZoom.? + onTwoFingers.factor * zoomFactor), 0.1, 1000);
                }
            } else {
                onTwoFingers._oldCameraZoom = null;
                onTwoFingers._oldCameraPos = null;
                onTwoFingers._startFingerPositions = null;
            }
        }
    }

    fn applyWASDMovement(self: *Self, cam: *r.Camera2D) void {
        if (self.ecs.getOnePtr(self.camera, CameraWASD)) |wasd| {
            if (r.IsKeyDown(wasd.up)) {
                cam.target = cam.target.add(.{ .x = 0, .y = -wasd.speed });
            }
            if (r.IsKeyDown(wasd.down)) {
                cam.target = cam.target.add(.{ .x = 0, .y = wasd.speed });
            }
            if (r.IsKeyDown(wasd.left)) {
                cam.target = cam.target.add(.{ .x = -wasd.speed, .y = 0 });
            }
            if (r.IsKeyDown(wasd.right)) {
                cam.target = cam.target.add(.{ .x = wasd.speed, .y = 0 });
            }
        }
    }

    /// transform a (x,y) screen coordinates to a world position
    pub fn screenToWorld(self: Self, screenPos: r.Vector2) r.Vector2 {
        const cam = self.ecs.getPtr(r.Camera2D, self.camRef).?.*;
        return r.GetScreenToWorld2D(screenPos, cam);
    }

    /// transform a (x,y) world position to screen coordinates
    pub fn worldToScreen(self: Self, worldPos: r.Vector2) r.Vector2 {
        const cam = self.ecs.getPtr(r.Camera2D, self.camRef).?.*;
        return r.GetWorldToScreen2D(worldPos, cam);
    }

    pub fn screenLengthToWorld(self: Self, lenght: f32) f32 {
        return lenght / self.getCamZoom();
    }

    pub fn worldLengthToScreen(self: Self, lenght: f32) f32 {
        return self.getCamZoom() * lenght;
    }

    pub fn after(self: *Self, _: f32) !void {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |_| {
            r.EndMode2D();
        }
    }

    //=== CAM functions ===========================================================================
    pub fn getCam(self: Self) r.Camera2D {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            return cam;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCam(self: Self, cam: r.Camera2D) void {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |c| {
            c.* = cam;
        }
    }

    pub fn setCamMode(self: Self, mode: r.CameraMode) void {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            r.SetCameraMode(cam.*, mode);
        }
    }

    pub fn getCamOffset(self: Self) r.Vector2 {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            return cam.offset;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCamOffset(self: Self, offset: r.Vector2) void {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            cam.offset = offset;
        }
    }

    pub fn getCamTarget(self: Self) r.Vector2 {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            return cam.target;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCamTarget(self: Self, target: r.Vector2) void {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            cam.target = target;
        }
    }

    pub fn getCamZoom(self: Self) f32 {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            return cam.zoom;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCamZoom(self: Self, zoom: f32) void {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            cam.zoom = zoom;
        }
    }

    pub fn getCamRotation(self: Self) f32 {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            return cam.rotation;
        }
        unreachable; //if we have a CameraSystem it should have created a camera intance
    }
    pub fn setCamRotation(self: Self, rotation: f32) void {
        if (self.ecs.getPtr(r.Camera2D, self.camRef)) |cam| {
            cam.rotation = rotation;
        }
    }

    //=== CONTROL components ======================================================================

    pub fn initCameraWASD(self: *Self, wasd: CameraWASD) void {
        log.debug("init camera wasd {?}", .{wasd});
        if (self.ecs.getOnePtr(self.camera, CameraWASD)) |camWasd| {
            camWasd.* = wasd;
        } else {
            ignore(self.ecs.add(self.camera, wasd));
        }
    }

    pub fn initMouseDrag(self: *Self, drag: CameraMouseDrag) void {
        log.debug("init mouse drag {?}", .{drag});
        if (self.ecs.getOnePtr(self.camera, CameraMouseDrag)) |camDrag| {
            camDrag.* = drag;
        } else {
            ignore(self.ecs.add(self.camera, drag));
        }
    }

    pub fn initMouseZoomScroll(self: *Self, zoomer: CameraScrollZoom) void {
        log.debug("init mouse zoom scroll {?}", .{zoomer});
        if (self.ecs.getOnePtr(self.camera, CameraScrollZoom)) |camZoom| {
            camZoom.* = zoomer;
        } else {
            ignore(self.ecs.add(self.camera, zoomer));
        }
    }

    pub fn initTouchZoomAndDrag(self: *Self, zoomDragger: TwoFingerZoomAndDrag) void {
        log.debug("init touch zoom and drag {?}", .{zoomDragger});
        if (self.ecs.getOnePtr(self.camera, TwoFingerZoomAndDrag)) |camZoomDragger| {
            camZoomDragger.* = zoomDragger;
        } else {
            ignore(self.ecs.add(self.camera, zoomDragger));
        }
    }
};

pub fn screenToWorld(screenPos: r.Vector2) r.Vector2 {
    const cam = _ecsInstance.?.getPtr(r.Camera2D, _camera.?);
    if (builtin.mode == .Debug) {
        if (cam == null) {
            @panic("no Camera2D available");
        }
    }
    return r.GetScreenToWorld2D(screenPos, cam.?.*);
}

pub fn worldToScreen(worldPos: r.Vector2) r.Vector2 {
    const cam = _ecsInstance.?.getPtr(r.Camera2D, _camera.?);
    if (builtin.mode == .Debug) {
        if (cam == null) {
            @panic("no Camera2D available");
        }
    }
    return r.GetWorldToScreen2D(worldPos, cam.?.*);
}

pub fn screenLengthToWorld(lenght: f32) f32 {
    const cam = _ecsInstance.?.getPtr(r.Camera2D, _camera.?);
    if (builtin.mode == .Debug) {
        if (cam == null) {
            @panic("no Camera2D available");
        }
    }
    return lenght / cam.?.zoom;
}

pub fn worldLengthToScreen(lenght: f32) f32 {
    const cam = _ecsInstance.?.getPtr(r.Camera2D, _camera.?);
    if (builtin.mode == .Debug) {
        if (cam == null) {
            @panic("no Camera2D available");
        }
    }
    return cam.?.zoom * lenght;
}
