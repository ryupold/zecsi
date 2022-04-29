const std = @import("std");
const log = @import("log.zig");
const _ecs = @import("ecs/ecs.zig");
const ECS = _ecs.ECS;

pub const Scene = struct {
    name: []const u8,
    ecs: *ECS,

    pub fn init(
        name: []const u8,
        allocator: std.mem.Allocator,
        arenaParent: std.mem.Allocator,
    ) !@This() {
        return @This(){
            .name = name,
            .ecs = try ECS.init(allocator, arenaParent),
        };
    }

    //TODO: write initFromPrevious function that also recreates entities & system of previous scene

    pub fn deinit(self: *@This()) void {
        self.ecs.deinit();
    }
};
