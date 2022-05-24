const std = @import("std");
const builtin = @import("builtin");
const _ecs = @import("ecs/ecs.zig");
pub const ECS = _ecs.ECS;
pub const Entity = _ecs.Entity;
pub const EntityID = _ecs.EntityID;
pub const Component = _ecs.Component;
pub const EntityComponentIterator = _ecs.EntityComponentIterator;

pub const game = @import("game.zig");

pub const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;

pub const log = @import("./log.zig");
pub const utils = @import("./utils.zig");
pub const assets = @import("./assets.zig");
pub const inputHandlers = @import("./input_handlers.zig");

pub const raylib = @import("raylib/raylib.zig");

pub const baseSystems = struct {
    usingnamespace @import("camera_system.zig");
    usingnamespace @import("asset_system.zig");
    usingnamespace @import("grid_placement_system.zig");
};

// pub fn init(
//     initialConfig: game.GameConfig,
//     gameEntryPoint: fn (ecs: *ECS) anyerror!void,
//     cleanup: ?fn (ecs: *ECS) anyerror!void,
// ) !void {
//     try game.init(allocator, initialConfig, gameEntryPoint, cleanup);
// }
