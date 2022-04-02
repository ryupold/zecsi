const std = @import("std");

pub const Timer = struct {
    timePassed: f32 = 0,
    repeat: bool,
    time: f32,

    pub fn tick(self: *@This(), dt: f32) bool {
        if(self.time <= 0) return true;

        const before = self.timePassed >= self.time;
        self.timePassed = std.math.clamp(self.timePassed + dt, 0, self.time);
        
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

pub fn ignore(v: anytype) void {
    _ = v catch |err| std.debug.panic("this should never crash: {?}", .{err});
}

pub fn vouch(v: anytype) @typeInfo(@TypeOf(v)).ErrorUnion.payload {
    return v catch |err| std.debug.panic("this should never crash: {?}", .{err});
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
