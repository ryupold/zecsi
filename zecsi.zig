const _ecs = @import("ecs/ecs.v2.zig");
const archetype = @import("ecs/archetype_storage.zig");
pub const ECS = _ecs.ECS;
pub const EntityID = _ecs.EntityID;
pub const ArchetypeIterator = _ecs.ArchetypeIterator;
pub const ArchetypeSlices = archetype.ArchetypeSlices;
pub const ArchetypeEntry = archetype.ArchetypeEntry;

pub const game = @import("game.zig");

pub const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;

pub const log = @import("./log.zig");
pub const utils = @import("./utils.zig");
pub const assets = @import("./assets.zig");
pub const inputHandlers = @import("./input_handlers.zig");

pub const raylib = @import("raylib/raylib.zig");
pub const raygui = @import("raygui/raygui.zig");

pub const baseSystems = struct {
    pub usingnamespace @import("systems/camera_system.zig");
    pub usingnamespace @import("systems/camera_system_3d.zig");
    pub usingnamespace @import("systems/asset_system.zig");
    pub usingnamespace @import("systems/grid_placement_system.zig");
    pub usingnamespace @import("systems/ui/ui_system.zig");
    pub usingnamespace @import("systems/scene_system.zig");
};

pub const ui = @import("systems/ui/ui.zig");
