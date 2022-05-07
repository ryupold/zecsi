const std = @import("std");
const log = @import("log.zig");
const _ecs = @import("ecs/ecs.zig");
const ECS = _ecs.ECS;


pub const Scene = struct {
    name: []const u8,
    ecs: *ECS,

    pub fn init(
        name: []const u8,
        ecs: ECS,
    ) !@This() {
        return @This(){
            .name = name,
            .ecs = ecs,
        };
    }

    

    pub fn deinit(self: *@This()) void {
        self.ecs.deinit();
    }
};
