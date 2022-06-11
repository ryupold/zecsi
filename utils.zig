const std = @import("std");
const raylib = @import("raylib/raylib.zig");

pub const Timer = struct {
    timePassed: f32 = 0,
    repeat: bool,
    time: f32,

    /// move time forward by `dt`
    /// returns true if `timePassed` reaches `time`
    /// if this is a `repeat`ing Timer, true is returned and `timePassed` starts from 0 (+overflow) again
    pub fn tick(self: *@This(), dt: f32) bool {
        if (self.time <= 0) return true;

        if (self.repeat) {
            self.timePassed += dt;
        } else {
            self.timePassed = std.math.clamp(self.timePassed + dt, 0, self.time);
        }

        if (self.timePassed >= self.time) {
            if (self.repeat) self.timePassed = @mod(self.timePassed, self.time);
            return true;
        }
        return false;
    }

    /// returns a value between 0 - 1
    /// interpret this as percent until the timer triggers
    pub fn progress(self: @This()) f32 {
        return std.math.clamp(self.timePassed / self.time, 0, 1);
    }

    /// reset `timePassed` to 0
    pub fn reset(self: *@This()) void {
        self.timePassed = 0;
    }
};

pub fn randomF32(rng: std.rand.Random, min: f32, max: f32) f32 {
    return rng.float(f32) * (max - min) + min;
}

pub fn randomVector2(rng: std.rand.Random, min: raylib.Vector2, max: raylib.Vector2) raylib.Vector2 {
    return .{ .x = randomF32(rng, min.x, max.x), .y = randomF32(rng, min.y, max.y) };
}

pub fn ignore(v: anytype) void {
    _ = v catch |err| std.debug.panic("this should never crash: {?}", .{err});
}

pub fn vouch(v: anytype) @typeInfo(@TypeOf(v)).ErrorUnion.payload {
    return v catch |err| std.debug.panic("this should never crash: {?}", .{err});
}

pub const DrawArrowConfig = struct {
    startOffset: f32 = 0,
    endOffset: f32 = 0,
    headSize: f32 = 20,
    color: raylib.Color = raylib.GREEN.set(.{ .a = 127 }),
};

pub fn drawArrow(from: raylib.Vector2, to: raylib.Vector2, config: DrawArrowConfig) void {
    const direction = to.sub(from).normalize();
    const start = from.add(direction.scale(config.startOffset));
    const end = to.sub(direction.scale(config.endOffset));

    raylib.DrawLineV(start, end, config.color);

    const arrowHeadLength = direction.scale(config.headSize);

    const aSide = arrowHeadLength.rotate(-raylib.PI * 3 / 4).add(end);
    const bSide = arrowHeadLength.rotate(raylib.PI * 3 / 4).add(end);

    raylib.DrawLineV(aSide, end, config.color);
    raylib.DrawLineV(bSide, end, config.color);
}

///TODO: draw angle head (it's just a line for now)
pub fn drawArrow3D(start: raylib.Vector3, end: raylib.Vector3, config: DrawArrowConfig) void {
    raylib.DrawLine3D(start, end, config.color);

    // const arrowLength = start.sub(end).normalize().scale(config.headSize);

    // const aSide = arrowLength.rotate(raylib.PI / 4).add(end);
    // const bSide = arrowLength.rotate(-raylib.PI / 4).add(end);

    // raylib.DrawLine3D(aSide, end, config.color);
    // raylib.DrawLine3D(bSide, end, config.color);
}

//=== TESTS =======================================================================================

const expect = std.testing.expect;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "Timer" {
    var timer: Timer = .{ .time = 1.0, .repeat = true };
    try expect(!timer.tick(0.1));
    try expect(timer.tick(1));
    try expectApproxEqAbs(timer.timePassed, 0.1, std.math.epsilon(f32));
    try expect(timer.tick(0.91));
    try expect(!timer.tick(0.1));
    try expect(!timer.tick(0.1));
    try expect(timer.tick(10.1));

    var timerWithoutRepeat: Timer = .{ .time = 1.0, .repeat = false };
    try expect(!timerWithoutRepeat.tick(0.5));
    try expect(timerWithoutRepeat.tick(0.51));
    try expect(!timerWithoutRepeat.tick(0.5));
    try expect(!timerWithoutRepeat.tick(1.5));
}

test "size of c_int" {
    try expect(@sizeOf(c_int) == @sizeOf(i32));
}
