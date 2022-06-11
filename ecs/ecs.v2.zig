//! https://devlog.hexops.com/2022/lets-build-ecs-part-1/
//! https://devlog.hexops.com/2022/lets-build-ecs-part-2-databases/

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const EntityID = u46;

pub const ArchetypeStorage = struct {
    allocator: std.mem.Allocator,

    /// The hash of every component name in this archetype, i.e. the name of this archetype.
    hash: u64,

    /// A string hashmap of component_name -> type-erased *ComponentStorage(Component)
    components: std.StringArrayHashMapUnmanaged(ErasedComponentStorage),

    entity_ids: std.ArrayListUnmanaged(EntityID) = .{},

    pub fn new(this: *@This(), entity: EntityID) !u32 {
        // Return a new row index
        const new_row_index = this.entity_ids.items.len;
        try this.entity_ids.append(this.allocator, entity);
        return @intCast(u32, new_row_index);
    }

    pub fn deinit(this: *@This()) void {
        for (this.components.values()) |erased| {
            erased.deinit(erased.ptr, this.allocator);
        }
        this.entity_ids.deinit(this.allocator);
        this.components.deinit(this.allocator);
    }

    pub fn calculateHash(this: *@This()) void {
        this.hash = 0;
        var iter = this.components.iterator();
        while (iter.next()) |entry| {
            const component_name = entry.key_ptr.*;
            this.hash ^= std.hash_map.hashString(component_name);
        }
    }

    pub fn undoNew(this: *@This()) void {
        _ = this.entity_ids.pop();
    }

    pub fn set(this: *@This(), row_index: u32, name: []const u8, component: anytype) !void {
        var component_storage_erased = this.components.get(name).?;
        var component_storage = ErasedComponentStorage.cast(component_storage_erased.ptr, @TypeOf(component));
        try component_storage.set(this.allocator, row_index, component);
    }

    pub fn remove(this: *@This(), row_index: u32) !void {
        _ = this.entity_ids.swapRemove(row_index);
        for (this.components.values()) |component_storage| {
            component_storage.remove(component_storage.ptr, row_index);
        }
    }
};

pub fn ComponentStorage(comptime TComponent: type) type {
    return struct {
        /// A reference to the total number of entities with the same type as is being stored here.
        total_rows: *usize,

        /// The actual densely stored component data.
        data: std.ArrayListUnmanaged(TComponent) = .{},

        pub fn deinit(this: *@This(), allocator: Allocator) void {
            this.data.deinit(allocator);
        }

        pub fn remove(this: *@This(), row_index: u32) void {
            if (this.data.items.len > row_index) {
                _ = this.data.swapRemove(row_index);
            }
        }

        pub inline fn copy(dst: *@This(), allocator: Allocator, src_row: u32, dst_row: u32, src: *@This()) !void {
            try dst.set(allocator, dst_row, src.get(src_row));
        }

        pub inline fn get(this: @This(), row_index: u32) Component {
            return storage.data.items[row_index];
        }
    };
}

/// A type-erased representation of ComponentStorage(T) (where T is unknown).
pub const ErasedComponentStorage = struct {
    ptr: *anyopaque,
    deinit: fn (erased: *anyopaque, allocator: Allocator) void,
    cloneType: fn (erased: @This(), total_entities: *usize, allocator: Allocator, retval: *@This()) error{OutOfMemory}!void,
    copy: fn (dst_erased: *anyopaque, allocator: Allocator, src_row: u32, dst_row: u32, src_erased: *anyopaque) error{OutOfMemory}!void,
    remove: fn (erased: *anyopaque, row: u32) void,

    // Casts this `ErasedComponentStorage` into `*ComponentStorage(TComponent)` with the given type
    // (unsafe).
    pub fn cast(this: *@This(), comptime TComponent: type) *ComponentStorage(TComponent) {
        var aligned = @alignCast(@alignOf(*ComponentStorage(TComponent)), this.ptr);
        return @ptrCast(*ComponentStorage(TComponent), aligned);
    }
};

pub const ECS = struct {
    pub const voidArchetype = std.math.maxInt(u64);

    counter: EntityID = 0,

    allocator: std.mem.Allocator,
    window: struct { size: struct { x: f32, y: f32 } = .{ .x = 100, .y = 100 } } = .{},
    systems: std.ArrayList(System),
    archetypes: std.AutoArrayHashMap(u64, ArchetypeStorage),

    /// A mapping of entity IDs (array indices) to where an entity's component values are actually
    /// stored.
    entities: std.AutoHashMapUnmanaged(EntityID, Pointer) = .{},

    /// Points to where an entity is stored, specifically in which archetype table and in which row
    /// of that table.
    pub const Pointer = struct {
        archetype_index: u16,
        row_index: u32,
    };

    ///
    pub fn init(
        allocator: std.mem.Allocator,
    ) !@This() {
        return @This(){
            .allocator = allocator,
            .systems = std.ArrayList(System).init(allocator),
            .archetypes = std.AutoArrayHashMap(u64, ArchetypeStorage).init(allocator),
        };
    }

    pub fn deinit(this: *@This()) void {
        for (this.systems.items) |*sys| {
            sys.deinit();
        }
        this.systems.deinit();

        var ait = this.archetypes.iterator();
        while (ait.next()) |archtype| {
            archtype.value_ptr.deinit();
        }
        this.entities.deinit(this.allocator);
    }

    /// Returns a new entity.
    pub fn create(this: *@This()) !EntityID {
        const new_id = this.counter;
        this.counter += 1;

        var void_archetype = this.archetypes.getPtr(voidArchetype).?;
        const new_row = try void_archetype.new(new_id);
        const void_pointer = Pointer{
            .archetype_index = 0, // void archetype is guaranteed to be first index
            .row_index = new_row,
        };

        this.entities.put(this.allocator, new_id, void_pointer) catch |err| {
            void_archetype.undoNew();
            return err;
        };

        return new_id;
    }

    pub inline fn archetypeByID(this: *@This(), entity: EntityID) *ArchetypeStorage {
        const ptr = this.entities.get(entity).?;
        return &this.archetypes.values()[ptr.archetype_index];
    }

    pub fn setComponent(this: *@This(), entity: EntityID, name: []const u8, component: anytype) !void {
        var archetype = this.archetypeByID(entity);

        const old_hash = archetype.hash;

        var have_already = archetype.components.contains(name);
        const new_hash = if (have_already) old_hash else old_hash ^ std.hash_map.hashString(name);

        var archetype_entry = try this.archetypes.getOrPut(this.allocator, new_hash);
        if (!archetype_entry.found_existing) {
            archetype_entry.value_ptr.* = ArchetypeStorage{
                .allocator = this.allocator,
                .components = .{},
                .hash = 0,
            };
            var new_archetype = archetype_entry.value_ptr;

            var column_iter = archetype.components.iterator();
            while (column_iter.next()) |entry| {
                var erased: ErasedComponentStorage = undefined;
                entry.value_ptr.cloneType(entry.value_ptr.*, &new_archetype.entity_ids.items.len, this.allocator, &erased) catch |err| {
                    assert(entities.archetypes.swapRemove(new_hash));
                    return err;
                };
                new_archetype.components.put(this.allocator, entry.key_ptr.*, erased) catch |err| {
                    assert(entities.archetypes.swapRemove(new_hash));
                    return err;
                };
            }

            // Create storage/column for the new component.
            const erased = this.initErasedStorage(&new_archetype.entity_ids.items.len, @TypeOf(component)) catch |err| {
                assert(entities.archetypes.swapRemove(new_hash));
                return err;
            };
            new_archetype.components.put(this.allocator, name, erased) catch |err| {
                assert(entities.archetypes.swapRemove(new_hash));
                return err;
            };

            new_archetype.calculateHash();
        }

        var current_archetype_storage = archetype_entry.value_ptr;

        //--- just write component data ---
        if (new_hash == old_hash) {
            const ptr = this.entities.get(entity).?;
            try current_archetype_storage.set(ptr.row_index, name, component);
            return;
        }

        //---

        const new_row = try current_archetype_storage.new(entity);
        const old_ptr = this.entities.get(entity).?;

        var column_iter = archetype.components.iterator();
        while (column_iter.next()) |entry| {
            var old_component_storage = entry.value_ptr;
            var new_component_storage = current_archetype_storage.components.get(entry.key_ptr.*).?;
            new_component_storage.copy(new_component_storage.ptr, this.allocator, new_row, old_ptr.row_index, old_component_storage.ptr) catch |err| {
                current_archetype_storage.undoNew();
                return err;
            };
        }

        current_archetype_storage.entity_ids.items[new_row] = entity;

        current_archetype_storage.set(new_row, name, component) catch |err| {
            current_archetype_storage.undoNew();
            return err;
        };

        var swapped_entity_id = archetype.entity_ids.items[archetype.entity_ids.items.len - 1];
        archetype.remove(old_ptr.row_index) catch |err| {
            current_archetype_storage.undoNew();
            return err;
        };

        try this.entities.put(this.allocator, swapped_entity_id, old_ptr);

        try entities.entities.put(entities.allocator, entity, Pointer{
            .archetype_index = @intCast(u16, archetype_entry.index),
            .row_index = new_row,
        });
        return;
    }

    pub fn getComponent(this: *@This(), entity: EntityID, name: []const u8, comptime Component: type) ?Component {
        var archetype = this.archetypeByID(entity);

        var component_storage_erased = archetype.components.get(name) orelse return null;

        const ptr = this.entities.get(entity).?;
        var component_storage = component_storage_erased.cast(Component);
        return component_storage.get(ptr.row_index);
    }

    fn initErasedStorage(
        self: *@This(),
        /// why is this a pointer?
        total_rows: *usize,
        comptime Component: type,
    ) !ErasedComponentStorage {
        var new_ptr = try self.allocator.create(ComponentStorage(Component));
        new_ptr.* = ComponentStorage(Component){ .total_rows = total_rows };

        return ErasedComponentStorage{
            .ptr = new_ptr,

            .deinit = (struct {
                pub fn deinit(erased: *anyopaque, allocator: Allocator) void {
                    var ptr = ErasedComponentStorage.cast(erased, Component);
                    ptr.deinit(allocator);
                    allocator.destroy(ptr);
                }
            }).deinit,

            .cloneType = (struct {
                pub fn cloneType(erased: ErasedComponentStorage, _total_rows: *usize, allocator: Allocator, retval: *ErasedComponentStorage) !void {
                    var new_clone = try allocator.create(ComponentStorage(Component));
                    new_clone.* = ComponentStorage(Component){ .total_rows = _total_rows };
                    var tmp = erased;
                    tmp.ptr = new_clone;
                    retval.* = tmp;
                }
            }).cloneType,

            .copy = (struct {
                pub fn copy(dst_erased: *anyopaque, allocator: Allocator, src_row: u32, dst_row: u32, src_erased: *anyopaque) !void {
                    var dst = ErasedComponentStorage.cast(dst_erased, Component);
                    var src = ErasedComponentStorage.cast(src_erased, Component);
                    return dst.copy(allocator, src_row, dst_row, src);
                }
            }).copy,

            .remove = (struct {
                pub fn remove(erased: *anyopaque, row: u32) void {
                    var ptr = ErasedComponentStorage.cast(erased, Component);
                    ptr.remove(row);
                }
            }).remove,
        };
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

/// get usize id for a given type (magic)
/// typeId implementation by Felix "xq" Queißner
/// from: https://zig.news/xq/cool-zig-patterns-type-identifier-3mfd
pub fn typeId(comptime T: type) usize {
    _ = T;
    const H = struct {
        var byte: u8 = 0;
    };
    return @ptrToInt(&H.byte);
}


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

const Position = struct { x: f32, y: f32 };
const Target = struct { x: f32, y: f32 };
const Name = struct { name: []const u8 };

test "create ecs" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();
}

test "create entity" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    var player = try ecs.create();
    const Location = struct {
        x: f32 = 0,
        y: f32 = 0,
        z: f32 = 0,
    };

    try ecs.setComponent(player, "Name", "jane"); // add Name component
    try ecs.setComponent(player, "Location", Location{}); // add Location component
    try ecs.setComponent(player, "Name", "joe"); // update Name component
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
