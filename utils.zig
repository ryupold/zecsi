const std = @import("std");
const raylib = @import("raylib/raylib.zig");

pub const Timer = struct {
    timePassed: f32 = 0,
    repeat: bool,
    time: f32,

    pub fn tick(self: *@This(), dt: f32) bool {
        if (self.time <= 0) return true;

        const before = self.timePassed >= self.time;
        if (self.repeat) {
            self.timePassed += dt;
        } else {
            self.timePassed = std.math.clamp(self.timePassed + dt, 0, self.time);
        }

        const after = self.timePassed >= self.time;
        if (!before and after) {
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
    headSize: f32 = 20,
    color: raylib.Color = raylib.GREEN.set(.{ .a = 127 }),
};

pub fn drawArrow(start: raylib.Vector2, end: raylib.Vector2, config: DrawArrowConfig) void {
    const from = raylib.Vector2{
        .x = std.math.clamp(
            start.x,
            @intToFloat(f32, std.math.minInt(i32)),
            @intToFloat(f32, std.math.maxInt(i32)),
        ),
        .y = std.math.clamp(
            start.y,
            @intToFloat(f32, std.math.minInt(i32)),
            @intToFloat(f32, std.math.maxInt(i32)),
        ),
    };
    const to = raylib.Vector2{
        .x = std.math.clamp(
            end.x,
            @intToFloat(f32, std.math.minInt(i32)),
            @intToFloat(f32, std.math.maxInt(i32)),
        ),
        .y = std.math.clamp(
            end.y,
            @intToFloat(f32, std.math.minInt(i32)),
            @intToFloat(f32, std.math.maxInt(i32)),
        ),
    };

    raylib.DrawLine(
        @floatToInt(i32, from.x),
        @floatToInt(i32, from.y),
        @floatToInt(i32, to.x),
        @floatToInt(i32, to.y),
        config.color,
    );

    const arrowLength = from.sub(to).normalize().scale(config.headSize);

    const aSide = arrowLength.rotate(raylib.PI / 4).add(to);
    const bSide = arrowLength.rotate(-raylib.PI / 4).add(to);

    raylib.DrawLine(
        @floatToInt(i32, aSide.x),
        @floatToInt(i32, aSide.y),
        @floatToInt(i32, to.x),
        @floatToInt(i32, to.y),
        config.color,
    );
    raylib.DrawLine(
        @floatToInt(i32, bSide.x),
        @floatToInt(i32, bSide.y),
        @floatToInt(i32, to.x),
        @floatToInt(i32, to.y),
        config.color,
    );
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
