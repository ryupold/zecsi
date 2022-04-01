const std = @import("std");
const r = @import("ray/raylib.zig");
const log = @import("log.zig");
const _ecs = @import("ecs/ecs.zig");
const ECS = _ecs.ECS;
const ray = @cImport({
    @cInclude("raylib_marshall.h");
});

pub const UiSystem = struct {
    ecs: *ECS,

    pub fn init(ecs: *ECS) !@This() {
        return @This(){
            .ecs = ecs,
        };
    }

    pub fn deinit(_: *@This()) void {}

    pub fn update(_: *@This(), _: f32) !void {
        // if (r.GuiButton(
        //     ray.Rectangle{ .x = 100, .y = 100, .width = 100, .height = 50 },
        //     "this is a test",
        // )) {
        //     log.debug("pressed the button", .{});
        // }
    }
};
