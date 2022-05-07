//! best practices: https://ziglearn.org/chapter-2/

const std = @import("std");
const builtin = @import("builtin");

pub const EntityID = usize;
const EntityContainer = std.AutoHashMap(EntityID, Entity);
const ComponentContainer = std.StringHashMap(usize);

pub const ECS = struct {
    const Self = @This();

    window: struct { size: struct { x: f32, y: f32 } = .{ .x = 100, .y = 100 } } = .{},
    entities: EntityContainer = undefined,
    componentData: ComponentContainer,
    systems: std.ArrayList(System),
    freeComponentIDs: std.StringHashMap(std.ArrayList(usize)),
    nextEntityID: EntityID = 0,
    allocator: std.mem.Allocator,
    componentAllocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,

    /// 
    pub fn init(
        allocator: std.mem.Allocator,
        arenaParent: std.mem.Allocator,
    ) !Self {
        var arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(arenaParent);
        const compAllocator = arena.allocator();

        return Self{
            .allocator = allocator,
            .arena = arena,
            .componentAllocator = compAllocator,
            .entities = EntityContainer.init(allocator),
            .systems = std.ArrayList(System).init(allocator),
            .componentData = ComponentContainer.init(compAllocator),
            .freeComponentIDs = std.StringHashMap(std.ArrayList(usize)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.systems.items) |*sys| {
            sys.deinit();
        }
        self.systems.deinit();

        var eit = self.entities.valueIterator();
        while (eit.next()) |entity| {
            entity.deinit();
        }
        self.entities.deinit();

        var freeIdIt = self.freeComponentIDs.valueIterator();
        while (freeIdIt.next()) |ids| {
            ids.deinit();
        }
        self.freeComponentIDs.deinit();

        self.arena.deinit();
        self.allocator.destroy(self.arena);
    }

    pub fn createEmpty(self: *Self) !*Entity {
        return self.createWithCapacity(1);
    }

    /// same as createEmpty but reserves some component capacity for better memory alignment
    /// useful when enitites have always the same set of components
    pub fn createWithCapacity(self: *Self, capacity: usize) !*Entity {
        defer self.nextEntityID += 1;
        const id = self.nextEntityID;

        try self.entities.putNoClobber(id, Entity{
            .id = id,
            .components = try std.ArrayList(Component).initCapacity(self.allocator, capacity),
        });

        return self.entities.getPtr(id).?;
    }

    /// when this method results in an bus error at runtime you have to first put the components in const variables
    /// and then pass them as tuple into this
    /// 
    /// instead of this:
    /// 
    ///ecs.create(.{StudentTable{
    ///     .pos = tablePos,
    ///     .width = tables.tableArea.x,
    ///     .height = tables.tableArea.y,
    ///}});
    /// 
    /// do this:
    /// 
    /// const table = StudentTable{
    ///     .pos = tablePos,
    ///     .width = tables.tableArea.x,
    ///     .height = tables.tableArea.y,
    ///}
    /// ecs.create(.{table});
    pub fn create(self: *Self, components: anytype) !*Entity {
        comptime if (!std.meta.trait.isTuple(@TypeOf(components))) compError("components must be a tuple with value types but was {?}", .{components});

        const info: std.builtin.TypeInfo = @typeInfo(@TypeOf(components));

        var entity = try self.createEmpty();
        inline for (info.Struct.fields) |field| {
            _ = try self.add(entity.id, @field(components, field.name));
        }
        return entity;
    }

    pub fn getID(_: *Self, e: anytype) EntityID {
        if (@TypeOf(e) == *Entity or @TypeOf(e) == Entity) {
            return e.id;
        }
        return e;
    }

    pub inline fn getEntity(self: *Self, id: EntityID) ?*Entity {
        const entityID = self.getID(id);

        return self.entities.getPtr(entityID);
    }

    pub fn add(self: *Self, entity: anytype, component: anytype) !Component {
        const T = @TypeOf(component);
        const entityID = self.getID(entity);
        var e = if (self.getEntity(entityID)) |eid| eid else return error.EntityNotFound;

        var c = Component{
            .t = @typeName(@TypeOf(component)),
            .id = undefined,
        };

        var arr: *std.ArrayList(T) = undefined;
        if (self.componentData.getPtr(c.t)) |address| {
            arr = @intToPtr(*std.ArrayList(T), address.*);
        } else {
            arr = try self.componentAllocator.create(std.ArrayList(T));
            arr.* = std.ArrayList(T).init(self.componentAllocator);
            try self.componentData.put(c.t, @ptrToInt(arr));
        }

        var freeId: ?*std.ArrayList(usize) = self.freeComponentIDs.getPtr(c.t);
        if (freeId == null) {
            try self.freeComponentIDs.put(c.t, std.ArrayList(usize).init(self.allocator));
            freeId = self.freeComponentIDs.getPtr(c.t).?;
        }

        c.id = id: {
            if (freeId.?.popOrNull()) |iD| {
                arr.items[iD] = component;
                break :id iD;
            } else {
                try arr.append(component);
                break :id arr.items.len - 1;
            }
        };

        try e.components.append(c);
        return c;
    }

    pub fn removeComponent(self: *Self, entity: anytype, comptime TComponent: type) !bool {
        const entityID = self.getID(entity);
        var e = if (self.getEntity(entityID)) |eid| eid else return error.EntityNotFound;

        if (e.getOne(TComponent)) |c| {
            return try self.remove(e, c);
        }
        return false;
    }

    pub fn removeAll(self: *Self, entity: anytype, comptime TComponent: type) !void {
        const entityID = self.getID(entity);
        var e = if (self.getEntity(entityID)) |eid| eid else return error.EntityNotFound;

        const count = e.count(TComponent);

        var buf: [16 * 1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        var removeList = std.ArrayList(Component).initCapacity(fba.allocator(), count) catch al: {
            break :al try std.ArrayList(Component).initCapacity(self.allocator, count);
        };

        var it = e.getAll(TComponent);
        while (it.next()) |c| {
            removeList.appendAssumeCapacity(c);
        }
        for (removeList.items) |c| {
            if (!try self.remove(e, c)) {
                std.log.err("could not remove component {?}", .{c});
            }
        }
    }

    pub fn remove(self: *Self, entity: anytype, component: Component) !bool {
        const entityID = self.getID(entity);
        var e = if (self.getEntity(entityID)) |eid| eid else return error.EntityNotFound;

        //remove component from the entity's component list
        var index: usize = indeX: {
            for (e.components.items) |c, i| {
                if (component.eql(c)) {
                    break :indeX i;
                }
            }
            return false;
        };
        _ = e.components.swapRemove(index);

        // save the new free component ID
        var freeId: ?*std.ArrayList(usize) = self.freeComponentIDs.getPtr(component.t);
        if (freeId == null) {
            try self.freeComponentIDs.put(component.t, std.ArrayList(usize).init(self.allocator));
            freeId = self.freeComponentIDs.getPtr(component.t).?;
        }
        try freeId.?.append(component.id);
        return true;
    }

    pub fn destroy(self: *Self, entity: anytype) !bool {
        const entityID = self.getID(entity);
        var e = if (self.getEntity(entityID)) |eid| eid else return false;

        while (e.components.items.len > 0) {
            const comp: Component = e.components.items[e.components.items.len - 1];
            const removed = try self.remove(entityID, comp);
            if (!removed) std.log.warn("could not remove component: {?}", .{comp});
        }
        e.deinit();

        return self.entities.remove(e.id);
    }

    pub fn has(self: *Self, entity: anytype, comptime TComponent: type) bool {
        const entityID = self.getID(entity);
        var e = if (self.getEntity(entityID)) |eid| eid else return false;

        return e.has(TComponent);
    }

    /// reference to the component data
    /// this reference can get invalid when adding/removing components so better never store it somewhere
    /// if you wish to have prolonged reference to a particular component use 'Entity.getOne()' to get a 'Component' 
    pub fn getOnePtr(self: *Self, entity: anytype, comptime TComponent: type) ?*TComponent {
        const entityID = self.getID(entity);
        var e = if (self.getEntity(entityID)) |eid| eid else return null;

        if (e.getOne(TComponent)) |c| {
            const address = self.componentData.get(c.t).?;
            var arr: *std.ArrayList(TComponent) = @intToPtr(*std.ArrayList(TComponent), address);
            return &arr.items[c.id];
        }
        return null;
    }

    /// reference to the component data by 'Component'
    /// this reference can get invalid when adding/removing components so better never store it somewhere
    pub fn getPtr(self: *Self, comptime TComponent: type, component: Component) ?*TComponent {
        if (self.componentData.get(component.t)) |address| {
            var arr: *std.ArrayList(TComponent) = @intToPtr(*std.ArrayList(TComponent), address);
            return &arr.items[component.id];
        }
        return null;
    }

    /// query all entities that contain all the components of 'archetype'
    /// called with a slice of types, eg.: &[_]type{Position, *Target}
    /// if the target component is a pointer the component data will be by reference
    pub fn query(self: *Self, comptime archetype: anytype) ArchetypeIterator(archetype) {
        return ArchetypeIterator(archetype){
            .ecs = self,
            .iterator = self.entities.valueIterator(),
        };
    }

    pub fn ArchetypeIterator(comptime types: anytype) type {
        comptime if (@TypeOf(types) != []const type and !std.meta.trait.isTuple(@TypeOf(types))) {
            compError("archetype query must be tuple of types or '[]const type' but was {?}", .{@TypeOf(types)});
        };

        return struct {
            pub const A = std.meta.Tuple(types);
            iterator: EntityContainer.ValueIterator,
            ecs: *ECS,
            pub fn next(self: *@This()) ?*Entity {
                while (self.iterator.next()) |e| {
                    var matches = true;
                    inline for (types) |t| {
                        if (!e.has(t)) {
                            matches = false;
                            break;
                        }
                    }
                    if (matches) return e;
                }
                return null;
            }
        };
    }

    //FIXME: this is only usable with zig 0.10+
    // slice definitions are valid though so use &[_]type{C1, C2,...} instead until then
    // pub fn ArchetypeOf(comptime A: anytype) type {
    //     comptime {
    //         if(@TypeOf(A) == []const type) return std.meta.Tuple(A);

    //         if (!std.meta.trait.isTuple(@TypeOf(A))) {
    //             compError("archetype {?} must be a tuple or slice of types", .{A});
    //         }
    //     }

    //     var arr: [A.len]const type = undefined;
    //     for (A) |c, i| {
    //         arr[i] = c;
    //     }
    //     return arr;
    // }

    pub fn getSystem(self: *Self, comptime TSystem: type) ?*TSystem {
        for (self.systems.items) |sys| {
            if (std.mem.eql(u8, @typeName(TSystem), sys.name))
                return @intToPtr(*TSystem, sys.ptr);
        }
        return null;
    }

    /// Replace system instance with a copy of 'system's data
    pub fn putSystem(self: *Self, system: anytype) !void {
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
    pub fn registerSystem(self: *Self, comptime TSystem: type) !*TSystem {
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
    fn allocSystem(self: *ECS, comptime TSystem: type) !AllocSystemResult(TSystem) {
        var system: *TSystem = try self.allocator.create(TSystem);
        errdefer self.allocator.destroy(system);
        system.* = try TSystem.init(self);

        const gen = struct {
            const hasBefore = std.meta.trait.hasFn("before")(TSystem);
            const hasUpdate = std.meta.trait.hasFn("update")(TSystem);
            const hasAfter = std.meta.trait.hasFn("after")(TSystem);

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
        };

        const sys = System{
            .ptr = @ptrToInt(system),
            .name = @typeName(TSystem),
            .alignment = @alignOf(TSystem),
            .deinitFn = gen.deinitImpl,
            .beforeFn = if (std.meta.trait.hasFn("before")(TSystem)) gen.beforeImpl else null,
            .updateFn = if (std.meta.trait.hasFn("update")(TSystem)) gen.updateImpl else null,
            .afterFn = if (std.meta.trait.hasFn("after")(TSystem)) gen.afterImpl else null,
        };

        return AllocSystemResult(TSystem){
            .ref = sys,
            .system = system,
        };
    }

    pub fn update(self: *Self, dt: f32) !void {
        for (self.systems.items) |*system| {
            try system.before(dt);
        }
        for (self.systems.items) |*system| {
            try system.update(dt);
        }
        for (self.systems.items) |*system| {
            try system.after(dt);
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
};

pub const Entity = struct {
    /// dont touch this
    id: EntityID,
    /// dont touch this: to get components use 'getOne' or 'getAll'
    components: std.ArrayList(Component),

    pub fn has(self: *@This(), comptime T: type) bool {
        for (self.components.items) |comp| {
            if (std.mem.eql(u8, comp.t, @typeName(T))) return true;
        }
        return false;
    }

    pub fn count(self: *@This(), comptime T: type) usize {
        var amount: usize = 0;
        for (self.components.items) |comp| {
            if (std.mem.eql(u8, comp.t, @typeName(T))) amount += 1;
        }
        return amount;
    }

    pub fn getOne(self: *@This(), comptime T: type) ?Component {
        // std.debug.print("getOne {?} {?}", .{ self, T });
        for (self.components.items) |*comp| {
            if (std.mem.eql(u8, comp.t, @typeName(T))) return comp.*;
        }
        return null;
    }

    pub fn getAll(self: *@This(), comptime T: type) EntityComponentIterator(T) {
        return .{ .components = self.components };
    }

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var buf: [100]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "Entity#{d}(component count={d})", .{ value.id, value.components.items.len });
        try writer.writeAll(s);
    }

    pub fn getData(self: *@This(), ecs: *ECS, comptime T: type) ?*T {
        return ecs.getOnePtr(self, T);
    }

    pub fn deinit(self: *@This()) void {
        self.components.deinit();
    }
};

/// use this component reference to access the data via ECS
pub const Component = struct {
    /// dont touch this
    id: usize,
    /// dont touch this
    t: []const u8,

    pub fn eql(self: @This(), other: @This()) bool {
        return self.id == other.id and std.mem.eql(u8, self.t, other.t);
    }

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var buf: [1000]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "{s}#{d}", .{ value.t, value.id });
        try writer.writeAll(s);
    }
};

pub fn EntityComponentIterator(comptime T: type) type {
    return struct {
        components: std.ArrayList(Component),
        index: usize = 0,
        t: []const u8 = @typeName(T),
        pub fn next(self: *@This()) ?Component {
            while (self.index < self.components.items.len) {
                defer self.index += 1;
                const comp = self.components.items[self.index];
                if (std.mem.eql(u8, comp.t, @typeName(T))) return comp;
            }
            return null;
        }
    };
}

fn compError(comptime fmt: []const u8, args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Position = struct { x: f32, y: f32 };
const Target = struct { x: f32, y: f32 };
const Name = struct { name: []const u8 };

test "create empty entity" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    try expectEqual(@as(usize, 1), ecs.entities.count());
    try expectEqual(*Entity, @TypeOf(e));
}

test "create entity with components" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.create(.{Position{ .x = 1, .y = 2 }});
    try expectEqual(@as(usize, 0), e.id);
}

test "add component" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    const component = try ecs.add(e, Position{ .x = 1, .y = 45 });

    try expectEqualStrings(component.t, @typeName(Position));
    try expectEqual(component.id, 0);
    try expectEqual(@as(usize, 1), e.components.items.len);
}

test "add multiple components" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    const component1 = try ecs.add(e, Position{ .x = 1, .y = 45 });
    const component2 = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    const component3 = try ecs.add(e, Name{ .name = "test" });
    try expectEqual(Component{ .t = @typeName(Position), .id = 0 }, component1);
    try expectEqual(Component{ .t = @typeName(Target), .id = 0 }, component2);
    try expectEqual(Component{ .t = @typeName(Name), .id = 0 }, component3);

    try expectEqual(@as(usize, 3), e.components.items.len);
}

test "add multiple components to multiple entities" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e1 = try ecs.createEmpty();
    const component1 = try ecs.add(e1, Position{ .x = 1, .y = 45 });
    const component2 = try ecs.add(e1, Target{ .x = 23, .y = 0.45 });
    const component3 = try ecs.add(e1, Name{ .name = "test" });
    var e2 = try ecs.createEmpty();
    const component2_1 = try ecs.add(e2, Position{ .x = 5, .y = 5 });
    const component2_2 = try ecs.add(e2, Target{ .x = 3.14, .y = 1.6 });

    try expectEqual(Component{ .t = @typeName(Position), .id = 0 }, component1);
    try expectEqual(Component{ .t = @typeName(Target), .id = 0 }, component2);
    try expectEqual(Component{ .t = @typeName(Name), .id = 0 }, component3);
    try expectEqual(Component{ .t = @typeName(Position), .id = 1 }, component2_1);
    try expectEqual(Component{ .t = @typeName(Target), .id = 1 }, component2_2);

    try expectEqual(@as(usize, 3), e1.components.items.len);
    try expectEqual(@as(usize, 2), e2.components.items.len);
}

test "getOne component" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    _ = try ecs.add(e, Position{ .x = 1, .y = 45 });
    _ = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    _ = try ecs.add(e, Name{ .name = "test" });

    const component1 = e.getOne(Position).?;
    const component2 = e.getOne(Target).?;
    const component3 = e.getOne(Name).?;

    try expectEqual(Component{ .t = @typeName(Position), .id = 0 }, component1);
    try expectEqual(Component{ .t = @typeName(Target), .id = 0 }, component2);
    try expectEqual(Component{ .t = @typeName(Name), .id = 0 }, component3);
}

test "getAll components as iterator" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    _ = try ecs.add(e, Position{ .x = 1, .y = 45 });
    _ = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    _ = try ecs.add(e, Target{ .x = 3, .y = 0.5 });
    _ = try ecs.add(e, Target{ .x = 1, .y = 5 });
    _ = try ecs.add(e, Name{ .name = "test" });

    var itTarget = e.getAll(Target);

    try expectEqual(Component{ .t = @typeName(Target), .id = 0 }, itTarget.next().?);
    try expectEqual(Component{ .t = @typeName(Target), .id = 1 }, itTarget.next().?);
    try expectEqual(Component{ .t = @typeName(Target), .id = 2 }, itTarget.next().?);
    try expect(itTarget.next() == null);

    var itPosition = e.getAll(Position);
    try expectEqual(Component{ .t = @typeName(Position), .id = 0 }, itPosition.next().?);

    var itName = e.getAll(Name);
    try expectEqual(Component{ .t = @typeName(Name), .id = 0 }, itName.next().?);
}

test "count components of same type" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    _ = try ecs.add(e, Position{ .x = 1, .y = 45 });
    _ = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    _ = try ecs.add(e, Target{ .x = 3, .y = 0.5 });
    _ = try ecs.add(e, Target{ .x = 1, .y = 5 });
    _ = try ecs.add(e, Name{ .name = "test" });

    try expectEqual(@as(usize, 1), e.count(Position));
    try expectEqual(@as(usize, 3), e.count(Target));
    try expectEqual(@as(usize, 1), e.count(Name));
}

test "has component" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    _ = try ecs.add(e.id, Position{ .x = 1, .y = 45 });

    try expectEqual(true, e.has(Position));
}

test "remove components with 'remove'" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    const component1 = try ecs.add(e, Position{ .x = 1, .y = 45 });
    const component2 = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    _ = try ecs.add(e, Name{ .name = "test" });

    try expectEqual(true, try ecs.remove(e, component2));
    try expectEqual(true, try ecs.remove(e, component1));
    try expectEqual(false, try ecs.remove(e, component1));

    try expectEqual(@as(usize, 1), e.components.items.len);

    //free ids
    try expectEqual(@as(usize, 1), ecs.freeComponentIDs.get(@typeName(Position)).?.items.len);
    try expectEqual(@as(usize, 1), ecs.freeComponentIDs.get(@typeName(Target)).?.items.len);
    try expectEqual(@as(usize, 0), ecs.freeComponentIDs.get(@typeName(Name)).?.items.len);
}

test "remove components with 'removeComponent'" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    _ = try ecs.add(e, Position{ .x = 1, .y = 45 });
    _ = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    _ = try ecs.add(e, Name{ .name = "test" });

    try expectEqual(true, try ecs.removeComponent(e, Target));
    try expectEqual(true, try ecs.removeComponent(e, Position));
    try expectEqual(false, try ecs.removeComponent(e, Position));

    try expectEqual(@as(usize, 1), e.components.items.len);

    //free ids
    try expectEqual(@as(usize, 1), ecs.freeComponentIDs.get(@typeName(Position)).?.items.len);
    try expectEqual(@as(usize, 1), ecs.freeComponentIDs.get(@typeName(Target)).?.items.len);
    try expectEqual(@as(usize, 0), ecs.freeComponentIDs.get(@typeName(Name)).?.items.len);
}

test "remove components with 'removeAll'" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    _ = try ecs.add(e, Position{ .x = 1, .y = 45 });
    _ = try ecs.add(e, Position{ .x = 1, .y = 45 });
    _ = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    _ = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    _ = try ecs.add(e, Target{ .x = 23, .y = 0.45 });
    _ = try ecs.add(e, Name{ .name = "test" });
    try expectEqual(@as(usize, 6), e.components.items.len);

    try ecs.removeAll(e, Position);
    try ecs.removeAll(e, Target);
    try ecs.removeAll(e, Name);

    try expectEqual(@as(usize, 0), e.components.items.len);

    //free ids
    try expectEqual(@as(usize, 2), ecs.freeComponentIDs.get(@typeName(Position)).?.items.len);
    try expectEqual(@as(usize, 3), ecs.freeComponentIDs.get(@typeName(Target)).?.items.len);
    try expectEqual(@as(usize, 1), ecs.freeComponentIDs.get(@typeName(Name)).?.items.len);
}

test "destroy entity" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e1 = try ecs.create(.{
        Position{ .x = 1, .y = 45 },
        Target{ .x = 23, .y = 0.45 },
        Name{ .name = "test" },
    });

    try expect(try ecs.destroy(e1));

    try expectEqual(@as(usize, 0), ecs.entities.count());
}

test "getOnePtr to component data" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e1 = try ecs.create(.{
        Position{ .x = 1, .y = 45 },
        Target{ .x = 23, .y = 0.45 },
        Name{ .name = "test" },
    });

    var pos = ecs.getOnePtr(e1, Position).?;
    try expectEqual(*Position, @TypeOf(pos));
    try expectEqual(Position{ .x = 1, .y = 45 }, pos.*);
}

test "getPtr to get specific component data" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    var e = try ecs.createEmpty();
    const c0 = try ecs.add(e, Target{ .x = 1, .y = 2 });
    _ = try ecs.add(e, Target{ .x = 2, .y = 3 });
    const c2 = try ecs.add(e, Target{ .x = 3, .y = 4 });
    _ = try ecs.add(e, Target{ .x = 4, .y = 5 });
    const c4 = try ecs.add(e, Target{ .x = 5, .y = 6 });

    try expectEqual(@as(usize, 5), e.count(Target));

    var t = ecs.getPtr(Target, c0).?;
    try expectEqual(Target{ .x = 1, .y = 2 }, t.*);
    t = ecs.getPtr(Target, c2).?;
    try expectEqual(Target{ .x = 3, .y = 4 }, t.*);
    t = ecs.getPtr(Target, c4).?;
    try expectEqual(Target{ .x = 5, .y = 6 }, t.*);
}

test "query by archetype (as pointers)" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    _ = try ecs.create(.{Position{ .x = 1, .y = 2 }});
    _ = try ecs.create(.{Position{ .x = 2, .y = 3 }});
    _ = try ecs.create(.{Position{ .x = 3, .y = 4 }});
    _ = try ecs.create(.{ Position{ .x = 4, .y = 5 }, Target{ .x = 11, .y = 22 } });
    _ = try ecs.create(.{ Position{ .x = 5, .y = 6 }, Target{ .x = 22, .y = 33 } });

    var it = ecs.query(&[_]type{Position});

    //order is not preserved
    try expectEqual(Position{ .x = 2, .y = 3 }, it.next().?.getData(&ecs, Position).?.*);
    try expectEqual(Position{ .x = 3, .y = 4 }, it.next().?.getData(&ecs, Position).?.*);
    try expectEqual(Position{ .x = 5, .y = 6 }, it.next().?.getData(&ecs, Position).?.*);
    try expectEqual(Position{ .x = 1, .y = 2 }, it.next().?.getData(&ecs, Position).?.*);
    try expectEqual(Position{ .x = 4, .y = 5 }, it.next().?.getData(&ecs, Position).?.*);
    try expect(it.next() == null);

    var it2 = ecs.query(&[_]type{ Position, Target });
    var e = it2.next().?;
    try expectEqual(Position{ .x = 5, .y = 6 }, e.getData(&ecs, Position).?.*);
    try expectEqual(Target{ .x = 22, .y = 33 }, e.getData(&ecs, Target).?.*);
    e = it2.next().?;
    try expectEqual(Position{ .x = 4, .y = 5 }, e.getData(&ecs, Position).?.*);
    try expectEqual(Target{ .x = 11, .y = 22 }, e.getData(&ecs, Target).?.*);
    try expect(it2.next() == null);
}

test "query by archetype (as values)" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    _ = try ecs.create(.{Position{ .x = 1, .y = 2 }});
    _ = try ecs.create(.{Position{ .x = 2, .y = 3 }});
    _ = try ecs.create(.{Position{ .x = 4, .y = 5 }});
    _ = try ecs.create(.{Position{ .x = 5, .y = 6 }});
    _ = try ecs.create(.{Position{ .x = 6, .y = 7 }});

    var it = ecs.query(&[_]type{Position});
    var e = it.next().?;
    //order is not preserved
    try expectEqual(Position{ .x = 2, .y = 3 }, e.getData(&ecs, Position).?.*);
    try expect(e.getData(&ecs, Target) == null);
}

test "testing for archetype" {
    var arch = .{ Position{ .x = 1, .y = 54 }, Target{ .x = 2, .y = 3 } };
    try expectEqual(Position{ .x = 1, .y = 54 }, arch[0]);
    try expectEqual(Target{ .x = 2, .y = 3 }, arch[1]);

    arch[0].x = 12;
    try expectEqual(Position{ .x = 12, .y = 54 }, arch[0]);
    arch[0] = Position{ .x = 55, .y = 110 };
    try expectEqual(Position{ .x = 55, .y = 110 }, arch[0]);
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
};

pub const MinimalSystem = struct {
    ecs: *ECS,

    pub fn init(ecs: *ECS) !@This() {
        return @This(){ .ecs = ecs };
    }

    pub fn deinit(_: *@This()) void {}
};

test "register system" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
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
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
    defer ecs.deinit();

    const system1: *ExampleSystem = try ecs.registerSystem(ExampleSystem);
    const system2: *MinimalSystem = try ecs.registerSystem(MinimalSystem);
    const system3 = try ecs.registerSystem(ExampleSystem);
    try expect(system1 != system3);

    const minimal = ecs.getSystem(MinimalSystem);
    try expect(minimal == system2);
}

test "ECS.update calls before on all systems, then update on all systems and at last after on all systems" {
    var ecs = try ECS.init(std.testing.allocator, std.testing.allocator);
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
