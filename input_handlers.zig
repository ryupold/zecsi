const std = @import("std");
const raylib = @import("raylib");

/// detects mouse press and drag to draw a line
/// alternatively detects a single touch point
pub const PointerDragger = struct {
    button: raylib.MouseButton,
    down: ?raylib.Vector2 = null,
    up: ?raylib.Vector2 = null,
    current: ?raylib.Vector2 = null,
    _lastTouchCount: i32 = 0,

    pub fn update(self: *@This()) void {
        const touchCount = raylib.GetTouchPointCount();
        defer self._lastTouchCount = touchCount;

        if (self.up != null or touchCount > 1) {
            self.down = null;
            self.current = null;
            self.up = null;
        }

        if (raylib.IsMouseButtonPressed(self.button)) {
            self.down = raylib.GetMousePosition();
            self.current = self.down;
            self.up = null;
        }

        if (self._lastTouchCount == 0 and touchCount == 1) {
            self.down = raylib.GetTouchPosition(0);
            self.current = self.down;
            self.up = null;
        }

        if (raylib.IsMouseButtonDown(self.button)) {
            self.current = raylib.GetMousePosition();
        }
        if (touchCount == 1) {
            self.current = raylib.GetTouchPosition(0);
        }

        if (raylib.IsMouseButtonReleased(self.button)) {
            self.up = self.current;
        }
        if (self._lastTouchCount == 1 and touchCount == 0) {
            self.up = self.current;
        }
    }

    pub fn dragLine(self: @This()) ?Line {
        if (self.down) |down| {
            if (self.current) |current| {
                return Line{ .from = down, .to = current };
            } else {
                return Line{ .from = down, .to = down };
            }
        }
        return null;
    }

    pub fn isReleased(self: @This()) bool {
        return self.up != null;
    }

    pub const Line = struct {
        from: raylib.Vector2,
        to: raylib.Vector2,

        pub fn distance(this: @This()) f32 {
            return this.to.distanceTo(this.from);
        }

        pub fn distanceSquared(this: @This()) f32 {
            return this.to.distanceToSquared(this.from);
        }

        pub fn delta(this: @This()) raylib.Vector2 {
            return this.to.sub(this.from);
        }
    };
};
