const std = @import("std");
const r = @import("../raylib/raylib.zig");
const log = @import("../log.zig");
const _ecs = @import("../ecs/ecs.zig");
const ECS = _ecs.ECS;

pub const UiSystem = struct {
    ecs: *ECS,

    pub fn init(ecs: *ECS) !@This() {
        return @This(){
            .ecs = ecs,
        };
    }

    pub fn deinit(_: *@This()) void {}

    pub fn ui(_: *@This(), _: f32) !void {}
};
