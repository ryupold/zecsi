//! inspired by:
//! https://devlog.hexops.com/2022/lets-build-ecs-part-1/
//! https://devlog.hexops.com/2022/lets-build-ecs-part-2-databases/

const std = @import("std");
const meta = std.meta;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const EntityID = @import("entity.zig").EntityID;
const storage = @import("archetype_storage.zig");
const ArchetypeHash = storage.ArchetypeHash;
const archetypeHash = storage.archetypeHash;
const combineArchetypeHash = storage.combineArchetypeHash;
const ArchetypeStorage = storage.ArchetypeStorage;
const ArchetypeEntry = storage.ArchetypeEntry;
const ArchetypeSlices = storage.ArchetypeSlices;

/// V2 ECS with archetype storages for different component combinations
pub const ECS = struct {
    allocator: std.mem.Allocator,
    window: struct { size: struct { x: f32, y: f32 } = .{ .x = 100, .y = 100 } } = .{},
    systems: std.ArrayList(System),
    nextEnitityID: EntityID = 1,
    enitities: std.AutoArrayHashMap(EntityID, ArchetypeHash),
    archetypes: std.AutoArrayHashMap(ArchetypeHash, ArchetypeStorage),
    addedArchetypes: std.AutoArrayHashMap(ArchetypeHash, ArchetypeStorage),

    pub fn init(
        allocator: std.mem.Allocator,
    ) !@This() {
        var ecs = @This(){
            .allocator = allocator,
            .systems = std.ArrayList(System).init(allocator),
            .enitities = std.AutoArrayHashMap(EntityID, ArchetypeHash).init(allocator),
            .archetypes = std.AutoArrayHashMap(ArchetypeHash, ArchetypeStorage).init(allocator),
            .addedArchetypes = std.AutoArrayHashMap(ArchetypeHash, ArchetypeStorage).init(allocator),
        };

        //initialize with void archetype where all new entities will be placed
        try ecs.archetypes.put(archetypeHash(.{}), try ArchetypeStorage.init(allocator));

        return ecs;
    }

    pub fn deinit(this: *@This()) void {
        for (this.systems.items) |*sys| {
            sys.deinit();
        }
        this.systems.deinit();

        for (this.archetypes.values()) |*archetypeStorage| {
            archetypeStorage.deinit();
        }
        this.archetypes.deinit();

        for (this.addedArchetypes.values()) |*addedArchetypeStorage| {
            addedArchetypeStorage.deinit();
        }
        this.addedArchetypes.deinit();

        this.enitities.deinit();
    }

    //=== Entity ==================================================================================
    pub fn create(this: *@This()) !EntityID {
        const id = this.nextEnitityID;
        const hash = archetypeHash(.{});

        var voidStorage = this.archetypes.getPtr(hash).?;
        _ = try voidStorage.newEntity(id);

        try this.enitities.put(id, hash);

        this.nextEnitityID += 1;
        return id;
    }

    /// sync all added and removed data from temp storage to real
    /// this is called usually after each frame (after all before, update, after, ui steps).
    fn syncArchetypes(this: *@This()) !void {
        for (this.archetypes.values()) |*archetype| {
            try archetype.sync();
        }

        var it = this.addedArchetypes.iterator();
        while (it.next()) |kv| {
            try kv.value_ptr.sync();
            try this.archetypes.putNoClobber(kv.key_ptr.*, kv.value_ptr.*);
        }
        this.addedArchetypes.clearAndFree();
    }

    //=== Component ===============================================================================

    pub fn put(this: *@This(), entity: EntityID, component: anytype) !void {
        if (this.enitities.get(entity)) |oldHash| {
            var previousStorage = this.archetypes.getPtr(oldHash) orelse this.addedArchetypes.getPtr(oldHash);
            if (previousStorage) |oldStorage| {
                oldStorage.put(entity, component) catch |err|
                    switch (err) {
                    // entity did not have this component before
                    error.ComponentNotPartOfArchetype => {
                        const newHash = combineArchetypeHash(oldHash, @TypeOf(component));
                        //after adding to new archetype, delete from old
                        defer oldStorage.delete(entity) catch unreachable;

                        //storage already exists
                        if (this.archetypes.getPtr(newHash)) |newStorage| {
                            // move entity to this storage
                            _ = try newStorage.copyFromOldArchetype(entity, oldStorage.*);
                        }
                        //storage is new, but already created in this frame
                        else if (this.addedArchetypes.getPtr(newHash)) |newlyAddedStorage| {
                            _ = try newlyAddedStorage.copyFromOldArchetype(entity, oldStorage.*);
                        }
                        //storage for this archetype does not exist yet
                        else {
                            var newArchetype = try ArchetypeStorage.initExtension(this.allocator, oldStorage.*, @TypeOf(component));
                            _ = try newArchetype.copyFromOldArchetype(entity, oldStorage.*);
                            try newArchetype.put(entity, component);
                            try this.addedArchetypes.put(newHash, newArchetype);
                        }
                        try this.enitities.put(entity, newHash);
                    },
                    else => return err,
                };
            }
        } else {
            return error.EntityNotFound;
        }
    }

    pub fn get(this: *@This(), entity: EntityID, comptime TComponent: type) ?TComponent {
        if (this.enitities.get(entity)) |hash| {
            if (this.archetypes.get(hash) orelse this.addedArchetypes.get(hash)) |archStorage| {
                return archStorage.get(entity, TComponent) catch |err| {
                    std.debug.panic("ECS.get({d}, {s}) -> {?}", .{ entity, @typeName(TComponent), err });
                };
            } else if (builtin.mode == .Debug) {
                std.debug.panic("Entity #{d} does not exist in any archetype storage (hash invalid)", .{entity});
            }
        } else if (builtin.mode == .Debug) {
            std.debug.panic("Entity #{d} does not exist", .{entity});
        }
        return null;
    }

    //=== Systems =================================================================================

    pub fn getSystem(self: *@This(), comptime TSystem: type) ?*TSystem {
        for (self.systems.items) |sys| {
            if (std.mem.eql(u8, @typeName(TSystem), sys.name))
                return @intToPtr(*TSystem, sys.ptr);
        }
        return null;
    }

    /// Replace system instance with a copy of 'system's data
    pub fn putSystem(self: *@This(), system: anytype) !void {
        const TSystem = @TypeOf(system);
        const tSystemInfo = @typeInfo(TSystem);
        comptime if (tSystemInfo != .Pointer and @typeInfo(tSystemInfo.Pointer.child) != .Struct) {
            compError("'system' parameter must be a pointer to a system", .{});
        };
        if (self.getSystem(TSystem)) |alreadyRegistered| {
            alreadyRegistered.* = system.*;
        } else {
            var s = try self.allocSystem(TSystem);
            try self.systems.append(s.ref);
            s.system.* = system.*;
        }
    }

    /// Create a new system instance and add it to the system pool
    /// Return previous instance if already registered
    pub fn registerSystem(self: *@This(), comptime TSystem: type) !*TSystem {
        if (self.getSystem(TSystem) != null) {
            return error.SystemAlreadyRegistered;
        }

        var s = try self.allocSystem(TSystem);
        try self.systems.append(s.ref);
        comptime if (std.meta.trait.hasFn("load")(TSystem)) {
            try s.system.load();
        };
        return s.system;
    }

    fn AllocSystemResult(comptime TSystem: type) type {
        return struct {
            ref: System,
            system: *TSystem,
        };
    }

    /// Allocate a new system instance and return it with its VTable (not added to system list yet)
    fn allocSystem(self: *@This(), comptime TSystem: type) !AllocSystemResult(TSystem) {
        var system: *TSystem = try self.allocator.create(TSystem);
        errdefer self.allocator.destroy(system);
        system.* = try TSystem.init(self);

        const gen = struct {
            const hasBefore = std.meta.trait.hasFn("before")(TSystem);
            const hasUpdate = std.meta.trait.hasFn("update")(TSystem);
            const hasAfter = std.meta.trait.hasFn("after")(TSystem);
            const hasUI = std.meta.trait.hasFn("ui")(TSystem);

            pub fn deinitImpl(ptr: usize) void {
                const this = @intToPtr(*TSystem, ptr);
                this.deinit();
                this.ecs.allocator.destroy(this);
            }

            pub fn beforeImpl(ptr: usize, dt: f32) !void {
                const this = @intToPtr(*TSystem, ptr);
                if (hasBefore) try this.before(dt);
            }
            pub fn updateImpl(ptr: usize, dt: f32) !void {
                const this = @intToPtr(*TSystem, ptr);
                if (hasUpdate) try this.update(dt);
            }
            pub fn afterImpl(ptr: usize, dt: f32) !void {
                const this = @intToPtr(*TSystem, ptr);
                if (hasAfter) try this.after(dt);
            }
            pub fn uiImpl(ptr: usize, dt: f32) !void {
                const this = @intToPtr(*TSystem, ptr);
                if (hasUI) try this.ui(dt);
            }
        };

        const sys = System{
            .ptr = @ptrToInt(system),
            .name = @typeName(TSystem),
            .alignment = @alignOf(TSystem),
            .deinitFn = gen.deinitImpl,
            .beforeFn = if (std.meta.trait.hasFn("before")(TSystem)) gen.beforeImpl else null,
            .updateFn = if (std.meta.trait.hasFn("update")(TSystem)) gen.updateImpl else null,
            .afterFn = if (std.meta.trait.hasFn("after")(TSystem)) gen.afterImpl else null,
            .uiFn = if (std.meta.trait.hasFn("ui")(TSystem)) gen.uiImpl else null,
        };

        return AllocSystemResult(TSystem){
            .ref = sys,
            .system = system,
        };
    }

    //=== Before, Update, After, UI ===============================================================

    /// execution order: before0,before1,before2,update0,update1,update2,after2,after1,after0,ui0,ui1,ui2
    pub fn update(self: *@This(), dt: f32) !void {
        for (self.systems.items) |*system| {
            try system.before(dt);
        }
        for (self.systems.items) |*system| {
            try system.update(dt);
        }

        var i: usize = self.systems.items.len;
        while (i > 0) : (i -= 1) {
            try self.systems.items[i - 1].after(dt);
        }

        for (self.systems.items) |*system| {
            try system.ui(dt);
        }

        try self.syncArchetypes();
    }
};

pub const System = struct {
    ///pointer to system instance
    ptr: usize,
    /// type name of the system
    name: []const u8,
    alignment: usize,
    deinitFn: fn (usize) void,
    beforeFn: ?fn (usize, f32) anyerror!void,
    updateFn: ?fn (usize, f32) anyerror!void,
    afterFn: ?fn (usize, f32) anyerror!void,
    uiFn: ?fn (usize, f32) anyerror!void,

    pub fn deinit(self: *@This()) void {
        @call(.{}, self.deinitFn, .{self.ptr});
    }

    pub fn before(self: *@This(), dt: f32) !void {
        if (self.beforeFn) |beforeFn| try @call(.{}, beforeFn, .{ self.ptr, dt });
    }

    pub fn update(self: *@This(), dt: f32) !void {
        if (self.updateFn) |updateFn| try @call(.{}, updateFn, .{ self.ptr, dt });
    }

    pub fn after(self: *@This(), dt: f32) !void {
        if (self.afterFn) |afterFn| try @call(.{}, afterFn, .{ self.ptr, dt });
    }

    pub fn ui(self: *@This(), dt: f32) !void {
        if (self.uiFn) |uiFn| try @call(.{}, uiFn, .{ self.ptr, dt });
    }
};

fn compError(comptime fmt: []const u8, args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

//=================================================================================================
//=== TESTS =======================================================================================
//=================================================================================================

const t = std.testing;
const expect = t.expect;
const expectEqual = t.expectEqual;
const expectEqualStrings = t.expectEqualStrings;

test "create ecs" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();
}

test "create entity" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    const entity1 = try ecs.create();
    const entity2 = try ecs.create();

    try expectEqual(@as(EntityID, 1), entity1);
    try expectEqual(@as(EntityID, 2), entity2);

    try ecs.update(0); // causes sync of archetype storages

    const voidArch = ecs.archetypes.get(archetypeHash(.{})).?;

    try expect(voidArch.hasEntity(entity1));
    try expect(voidArch.hasEntity(entity2));
}

test "put new component type, not previously present in the entities' storage" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    const entity = try ecs.create();

    try ecs.put(entity, Position{ .x = 1, .y = 2 });
    // there should be an additional archetype in addedArchetypes
    try expectEqual(@as(usize, 1), ecs.addedArchetypes.count());
    try expectEqual(archetypeHash(.{Position}), ecs.addedArchetypes.keys()[0]);

    try ecs.put(entity, Name{ .name = "foobar" });
    try expectEqual(@as(usize, 2), ecs.addedArchetypes.count());
}

test "syncArchetypes" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    const entity1 = try ecs.create();
    const entity2 = try ecs.create();

    try ecs.put(entity1, Position{ .x = 1, .y = 2 });
    try ecs.put(entity1, Name{ .name = "foobar" });
    try ecs.put(entity2, Position{ .x = 1, .y = 2 });
    try expectEqual(@as(usize, 1), ecs.archetypes.count());
    try expectEqual(@as(usize, 2), ecs.addedArchetypes.count());

    try ecs.syncArchetypes();

    try expectEqual(@as(usize, 0), ecs.addedArchetypes.count());
    // all archetypes created along the way
    try expectEqual(@as(usize, 3), ecs.archetypes.count());
    try expectEqual(archetypeHash(.{}), ecs.archetypes.keys()[0]);
    try expectEqual(archetypeHash(.{Position}), ecs.archetypes.keys()[1]);
    try expectEqual(archetypeHash(.{ Position, Name }), ecs.archetypes.keys()[2]);

    try expectEqual(ecs.enitities.get(entity1).?, archetypeHash(.{ Position, Name }));
    try expectEqual(ecs.enitities.get(entity2).?, archetypeHash(.{Position}));
}

test "get component data from entity" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    const entity = try ecs.create();

    try ecs.put(entity, Position{ .x = 1, .y = 2 });
    try ecs.put(entity, Name{ .name = "foobar" });

    // get before sync
    try expectEqual(Position{ .x = 1, .y = 2 }, ecs.get(entity, Position).?);
    try expectEqual(Name{ .name = "foobar" }, ecs.get(entity, Name).?);

    try ecs.syncArchetypes();

    // and after sync
    try expectEqual(Position{ .x = 1, .y = 2 }, ecs.get(entity, Position).?);
    try expectEqual(Name{ .name = "foobar" }, ecs.get(entity, Name).?);
}

const ExampleSystem = struct {
    ecs: *ECS,

    testState: f32 = 0,

    pub fn init(ecs: *ECS) !@This() {
        return @This(){ .ecs = ecs };
    }

    pub fn deinit(_: *@This()) void {}

    pub fn before(self: *@This(), dt: f32) !void {
        self.testState -= dt;
    }

    pub fn update(self: *@This(), dt: f32) !void {
        self.testState = dt;
    }

    pub fn after(self: *@This(), dt: f32) !void {
        self.testState += dt;
    }

    pub fn ui(self: *@This(), dt: f32) !void {
        self.testState *= dt;
    }
};

pub const MinimalSystem = struct {
    ecs: *ECS,

    pub fn init(ecs: *ECS) !@This() {
        return @This(){ .ecs = ecs };
    }

    pub fn deinit(_: *@This()) void {}
};

test "register system" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    var system: *ExampleSystem = try ecs.registerSystem(ExampleSystem);
    try expectEqual(system.testState, 0);
    try system.before(0.1);
    try expectEqual(system.testState, -0.1);
    try system.update(0.3);
    try expectEqual(system.testState, 0.3);
    try system.after(0.1);
    try expectEqual(system.testState, 0.4);

    _ = try ecs.registerSystem(MinimalSystem);
}

test "get system" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    _ = try ecs.registerSystem(ExampleSystem);
    const system2: *MinimalSystem = try ecs.registerSystem(MinimalSystem);

    const minimal = ecs.getSystem(MinimalSystem);
    try expect(minimal == system2);
}

test "ECS.update calls before on all systems, then update on all systems and at last after on all systems" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    const UpdateSystem = struct {
        ecs: *ECS,

        beforeCalls: usize = 0,
        updateCalls: usize = 0,
        afterCalls: usize = 0,
        testState: f32 = 0,

        pub fn init(e: *ECS) !@This() {
            return @This(){ .ecs = e };
        }

        pub fn deinit(_: *@This()) void {}

        pub fn before(self: *@This(), _: f32) !void {
            self.beforeCalls += 1;
            self.testState += 1;
        }
        pub fn update(self: *@This(), _: f32) !void {
            self.updateCalls += 1;
            self.testState *= -1;
        }
        pub fn after(self: *@This(), _: f32) !void {
            self.afterCalls += 1;
            self.testState -= 1;
        }
    };

    var sut = try ecs.registerSystem(UpdateSystem);
    try expectEqual(sut.beforeCalls, 0);
    try expectEqual(sut.updateCalls, 0);
    try expectEqual(sut.afterCalls, 0);
    try ecs.update(0.2);
    try expectEqual(sut.testState, -2);

    try expectEqual(sut.beforeCalls, 1);
    try expectEqual(sut.updateCalls, 1);
    try expectEqual(sut.afterCalls, 1);
    try ecs.update(0.1);
    try expectEqual(sut.beforeCalls, 2);
    try expectEqual(sut.updateCalls, 2);
    try expectEqual(sut.afterCalls, 2);
}

//=== components used in unit tests ==================
const Position = struct { x: f32, y: f32 };
const Target = struct { x: f32, y: f32 };
const Name = struct { name: []const u8 };
const Dunno = struct { label: []const u8, wtf: i32 };
//====================================================
