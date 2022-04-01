//! This is WIP an does not compile at the moment
//! see ./ecs.zig for an alternative implementation
//!
//!
//! cool links
//! - https://medium.com/ingeniouslysimple/entities-components-and-systems-89c31464240d
//! - https://ajmmertens.medium.com/building-an-ecs-2-archetypes-and-vectorization-fe21690805f9
//! - https://devlog.hexops.com/2022/lets-build-ecs-part-1

const std = @import("std");
const meta = std.meta;
const trait = meta.trait;
const builtin = @import("builtin");
const assert = std.debug.assert;
const Stack = @import("utils.zig").Stack;

const MAX_COMPONENT_TYPES = 100;
const MAX_ARCHETYPES = 50;
const MAX_COMPONENTS_PER_ARCHETYPE = 10;

const FREE: usize = std.math.maxInt(usize);

pub const Entity = struct {
    /// reference to the component container ECS.entityComponents
    id: usize,
};

pub const EntityWithComponents = struct {
    id: usize,
    components: []const Component,
};

pub fn TypedComponent(comptime T: type) type {
    return struct {
        id: usize,
        getTypeID: fn (t: type) usize,
        pub fn typeID(self: @This()) usize {
            return self.getTypeID(T);
        }

        pub fn untyped(self: @This()) Component {
            return .{
                .id = self.id,
                .typeID = self.typeID(),
            };
        }
    };
}

pub const Component = struct {
    typeID: usize,
    id: usize,
};

pub const Archetype = struct {
    typeID: usize,
    id: usize,
};

const NextIDs = struct {
    entity: usize = 0,
};

/// every system must have a field called 'ecs' with this type
pub const EntityComponentSystem = struct {
    create: fn ([]usize) anyerror!EntityWithComponents,

    // entity: fn (id: usize) ?EntityWithComponents,

    // destroy: fn (entityID: usize) !bool,

    // remove: fn (typeID: usize, id: usize) !bool,

    // component: fn (comptime T: type, id: usize) ?T,

    // query: fn (comptime archetype: anytype) struct {
    //     index: usize,
    //     next: fn () ?archetypeOf(archetype),
    // },

    // add: fn (entityID: usize, componenT: anytype) !Component,

    // getTypeID: fn (comptime T: type) usize,

    // typed: fn (comptime T: type, c: Component) TypedComponent(T),
};

/// call with an array holding your system types
pub fn ECS(comptime systems: anytype) type {
    return struct {
        pub const Self = @This();
        pub const systems = getSystemTypes(systems);
        pub const composition = getComponentComposition(systems, false);

        /// system instances (as usize pointers)
        systems: [systems.len]usize = [_]usize{0} ** systems.len,

        /// list of all entities (same index as 'entityComponents')
        entities: std.ArrayList(Entity),
        /// list of all components to a given entity [entityID][componentID] (same index as 'entities')
        entityComponents: std.ArrayList(std.ArrayList(Component)),

        /// list of all components to query all components of a given type [componentType][componentID]
        components: [composition.components.len]std.ArrayList(Component) = undefined,
        /// the component data in a 2d array [componentType][@sizeOf(componentType)*componentID]
        componentsData: [composition.components.len][]u8 = [_][]u8{&[_]u8{}} ** composition.components.len,

        // archetypes: [composition.archetypes.len]std.ArrayList(Archetype),
        // archetypeData: [composition.archetypes.len][]u8 = [_][]u8{&[_]u8{}} ** composition.archetypes.len,

        /// incremental next id
        nextIDs: NextIDs = .{},

        /// when an component or archetype is destroyed, its free id is put into here
        /// so we only grow memory if needed and reuse old space
        freeIDs: FreeIDs(composition.components.len, composition.archetypes.len),
        allocator: std.mem.Allocator,

        /// create ecs instance and initialize all systems
        /// if the systems implement 'init' use it to create them
        /// otherwise they will be created assuming no field needs initialization
        pub fn init(allocator: std.mem.Allocator) !*Self {
            var ecs = try allocator.create(Self);
            ecs.allocator = allocator;
            ecs.freeIDs = FreeIDs(composition.components.len, composition.archetypes.len).init(allocator);
            ecs.entities = std.ArrayList(Entity).init(allocator);
            ecs.entityComponents = std.ArrayList(std.ArrayList(Component)).init(allocator);

            for (ecs.components) |_, i| {
                ecs.components[i] = std.ArrayList(Component).init(allocator);
            }

            inline for (systems) |sys, i| {
                if (ecs.systems[i] != 0) @panic(@typeName(sys) ++ " already initialized!");

                const systemInit = findInit(sys);
                if (systemInit != null) {
                    const ptr = try systemInit.?(allocator, handle);
                    ecs.systems[i] = @ptrToInt(ptr);
                } else {
                    var s = @ptrToInt(try allocator.create(sys));
                    s.ecs = handle;
                    ecs.systems[i] = s;
                }
            }
            return ecs;
        }

        /// call 'deinit' on all systems that implement it
        /// otherwise call 'Allocator.destroy' on the pointer
        pub fn deinit(self: *Self) void {
            inline for (systems) |sys, i| {
                if (self.systems[i] == 0) @panic(@typeName(sys) ++ " already deinitialized!");

                const systemDeinit = findDeinit(sys);
                const ptr = @intToPtr(*sys, self.systems[i]);
                if (systemDeinit != null) {
                    systemDeinit.?(ptr);
                } else {
                    self.allocator.destroy(ptr);
                }
                self.systems[i] = 0;
            }

            for (self.entityComponents.items) |*ec| {
                ec.clearAndFree();
            }
            // for(self.entities.items) |e|{
            //     _ = self.destroy(e.id) catch @panic("cannot destroy entity in deinit");
            // }
            self.entities.clearAndFree();
            self.entityComponents.clearAndFree();

            for (self.components) |_, i| {
                self.components[i].clearAndFree();
                self.allocator.free(self.componentsData[i]);
            }

            self.freeIDs.deinit();
        }

        /// call 'before' on all systems that implement it before 'update'
        pub fn before(self: *Self, dt: f32) void {
            inline for (systems) |sys, i| {
                const systemUpdate = findUpdate("before", sys);
                if (systemUpdate != null) {
                    const ptr = @intToPtr(*sys, self.systems[i]);
                    systemUpdate.?(ptr, dt);
                }
            }
        }
        /// call 'update' on all systems that implement it
        pub fn update(self: *Self, dt: f32) void {
            inline for (systems) |sys, i| {
                const systemUpdate = findUpdate("update", sys);
                if (systemUpdate != null) {
                    const ptr = @intToPtr(*sys, self.systems[i]);
                    systemUpdate.?(ptr, dt);
                }
            }
        }
        /// call 'after' on all systems that implement it after 'update'
        pub fn after(self: *Self, dt: f32) void {
            inline for (systems) |sys, i| {
                const systemUpdate = findUpdate("after", sys);
                if (systemUpdate != null) {
                    const ptr = @intToPtr(*sys, self.systems[i]);
                    systemUpdate.?(ptr, dt);
                }
            }
        }

        /// get system instance by type
        pub fn system(self: *Self, comptime systemType: type) *systemType {
            comptime var index: ?usize = null;
            comptime {
                for (systems) |sys, i| {
                    if (sys == systemType) {
                        index = i;
                        break;
                    }
                }
                if (index == null) compError("{s} not registered as system in this ecs", .{@typeName(systemType)});
            }

            const ptr = self.systems[index.?];
            return @intToPtr(*systemType, ptr);
        }

        /// create a new entity with a start set of components
        pub fn create(self: *Self, comptime components: anytype) anyerror!EntityWithComponents {
            comptime {
                const componentsInfo = @typeInfo(@TypeOf(components));
                if (componentsInfo != .Struct and componentsInfo != .Array and componentsInfo != .Slice) {
                    compError("create needs an interable (or empty) collection of components. you passed: {?}", .{componentsInfo});
                }
            }

            var e: Entity = .{ .id = undefined };
            self.nextIDs.entity += 1;
            try self.entities.append(e);

            //get a free entityComponents index or append at the end with a new one
            var entityComponentsId: ?usize = self.freeIDs.entity.pop();
            if (entityComponentsId) |componentsId| {
                e.id = componentsId;
                self.entityComponents.items[e.id].clearAndFree(); //TODO: maybe retain capacity?
                // self.entityComponents.items[e.id].items[componentsId].clearAndFree();
            } else {
                e.id = self.entityComponents.items.len;
                try self.entityComponents.append(std.ArrayList(Component).init(self.allocator));
            }

            inline for (components) |comp| {
                _ = try self.add(e.id, comp);
            }
            return EntityWithComponents{
                .id = e.id,
                .components = self.entityComponents.items[e.id].items,
            };
        }

        fn entity(self: *Self, id: usize) ?EntityWithComponents {
            if (id >= self.entities.items.len) return null;

            return EntityWithComponents{ .id = id, .components = self.entityComponents.items[id].items };
        }

        fn destroy(self: *Self, entityID: usize) !bool {
            if (entityID >= self.entities.items.len) return false;

            var eComponents = self.entityComponents.items[entityID];
            for (eComponents.items) |c| {
                _ = try self.remove(c.typeID, c.id);
            }
            // eComponents.clearAndFree(); //TODO: maybe retain capacity?
            _ = self.entities.orderedRemove(entityID);
            // _ = self.entityComponents.orderedRemove(entityID);
            try self.freeIDs.entity.push(entityID);
            return true;
        }

        fn remove(self: *Self, typeID: usize, id: usize) !bool {
            if (typeID >= Self.composition.components.len or id >= self.components[typeID].items.len) return false;

            _ = self.components[typeID].orderedRemove(id);
            try self.freeIDs.component[typeID].push(id);
            return true;
        }

        fn component(self: *Self, comptime T: type, id: usize) ?T {
            const typeID = Self.composition.componentTypeID(T);

            if (id < 0 or id > self.components[typeID].items.len) return null;

            return std.mem.bytesToValue(T, @ptrCast(*[@sizeOf(T)]u8, self.componentsData[typeID][id .. id + @sizeOf(T)]));
        }

        fn componentsIterator(self: *Self, comptime T: type) struct {
            ecs: *Self,
            index: usize = 0,
            comps: []Component,
            data: []const u8,
            fn next(this: *@This()) ?T {
                if (this.index >= this.comps.len) return null;
                defer this.index += 1;

                return this.ecs.component(T, this.comps[this.index].id);
            }
        } {
            const typeID = Self.composition.componentTypeID(T);

            return .{
                .ecs = self,
                .comps = self.components[typeID].items,
                .data = self.componentsData[typeID],
            };
        }

        pub fn add(self: *Self, entityID: usize, componenT: anytype) !Component {
            const componentTypeID = composition.componentTypeID(@TypeOf(componenT));

            var componentMeta = Component{ .typeID = componentTypeID, .id = undefined };
            //get a free ID or append at the end with a new one
            var nextID: ?usize = self.freeIDs.component[componentTypeID].pop();
            if (nextID) |id| {
                componentMeta.id = id;
            } else {
                componentMeta.id = self.components[componentTypeID].items.len;
                self.componentsData[componentTypeID] = try self.allocator.realloc(self.componentsData[componentTypeID], self.componentsData[componentTypeID].len + @sizeOf(@TypeOf(componenT)));
            }
            try self.components[componentTypeID].append(componentMeta);
            std.mem.copy(
                u8,
                self.componentsData[componentTypeID][componentMeta.id .. componentMeta.id + @sizeOf(@TypeOf(componenT))],
                &std.mem.toBytes(componenT),
            );

            try self.entityComponents.items[entityID].append(componentMeta);
            return componentMeta;
        }

        // fn archetype(self: *Self, comptime A: type, id: usize) ?T {
        //     const typeID = Self.composition.componentTypeID(T);

        //     if (id < 0 or id > self.components[typeID].items.len) return null;

        //     return std.mem.bytesToValue(T, @ptrCast(*[@sizeOf(T)]u8, self.componentsData[typeID][id .. id + @sizeOf(T)]));
        // }

        pub fn query(self: *Self, comptime archetype: anytype) struct {
            ecs: *Self,
            index: usize = 0,
            comps: []Archetype,
            data: []const u8,
            fn next(this: *@This()) ?archetypeOf(archetype) {
                if (this.index >= this.comps.len) return null;
                defer this.index += 1;

                return .{this.ecs.component(archetype[0], this.comps[this.index].id)};
            }
        } {
            if (!trait.isTuple(archetype) or archetype.len > 1) {
                compError("currently only 1 element tuples can be queried for archetype", .{});
            }

            const typeID = self.getTypeID(archetype[0]);

            return .{
                .ecs = self,
                .comps = self.components[typeID].items,
                .data = self.componentsData[typeID],
            };
        }

        fn getTypeID(comptime T: type) usize {
            return Self.composition.componentTypeID(T);
        }

        pub fn typed(c: Component) TypedComponent(Self.composition.components[c.typeID]) {
            return TypedComponent(Self.composition.components[c.typeID]){
                .id = c.id,
                .getTypeID = Self.getTypeID,
            };
        }
    };
}

fn SystemInfo(comptime systems: anytype) type {
    return struct {
        systemTypes: [systems.len]type = undefined,
        systemsInfo: [systems.len]std.builtin.TypeInfo = undefined,
    };
}

fn findInit(comptime system: type) ?fn (std.mem.Allocator) anyerror!*system {
    comptime {
        const info = @typeInfo(system);
        for (info.Struct.decls) |decl| {
            if (std.mem.eql(u8, decl.name, "init") and decl.data == .Fn) {
                if (@typeInfo(decl.data.Fn.fn_type).Fn.args.len != 1 or @typeInfo(decl.data.Fn.fn_type).Fn.args[0].arg_type != std.mem.Allocator or @typeInfo(decl.data.Fn.return_type) != .ErrorUnion or @typeInfo(decl.data.Fn.return_type).ErrorUnion.payload != *system) {
                    compError("{s}.{s}(...) signature must be {s}.init(std.mem.Allocator) !*{s}", .{
                        @typeName(system),
                        decl.name,
                        @typeName(system),
                        @typeName(system),
                    });
                }
                return system.init;
            }
        }
    }
    return null;
}

fn findDeinit(comptime system: type) ?fn (*system) void {
    comptime {
        const info = @typeInfo(system);
        for (info.Struct.decls) |decl| {
            if (std.mem.eql(u8, decl.name, "deinit") and decl.data == .Fn) {
                if (@typeInfo(decl.data.Fn.fn_type).Fn.args.len != 1 or @typeInfo(@typeInfo(decl.data.Fn.fn_type).Fn.args[0].arg_type.?) != .Pointer or @typeInfo(decl.data.Fn.fn_type).Fn.args[0].arg_type != *system) {
                    compError("{s}.{s}(...) signature must be {s}.deinit(*{s}) void", .{
                        @typeName(system),
                        decl.name,
                        @typeName(system),
                        @typeName(system),
                    });
                }
                return system.deinit;
            }
        }
    }
    return null;
}

fn findUpdate(comptime name: []const u8, comptime system: type) ?fn (*system, f32) void {
    comptime {
        const info = @typeInfo(system);
        for (info.Struct.decls) |decl| {
            if (std.mem.eql(u8, decl.name, name) and decl.data == .Fn) {
                if (@typeInfo(decl.data.Fn.fn_type).Fn.args.len != 1 or @typeInfo(@typeInfo(decl.data.Fn.fn_type).Fn.args[0].arg_type.?) != .Pointer or @typeInfo(decl.data.Fn.fn_type).Fn.args[0].arg_type != *system or @typeInfo(decl.data.Fn.fn_type).Fn.args[1].arg_type != f32) {
                    compError("{s}.{s}(...) signature must be {s}.update(*{s},f32) void", .{
                        @typeName(system),
                        decl.name,
                        @typeName(system),
                        @typeName(system),
                    });
                }
                return system.deinit;
            }
        }
    }
    return null;
}

/// checks the passed in tuple, array or slice of system types for correctness
/// normalizes it into an array -> [systems.len]type
fn getSystemTypes(comptime systems: anytype) [systems.len]type {
    const anyType = @TypeOf(systems);
    const systemsInfo = @typeInfo(anyType);
    if (systemsInfo != .Struct and systemsInfo != .Array and systemsInfo != .Slice) {
        compError("You passed as systems: {?} of type {?}\n'systems' parameter must be an Tuple, Array or Slice holding struct like system types. ", .{ systems, anyType });
    } else {
        comptime var systemData: [systems.len]type = undefined;
        comptime var i = 0;
        for (systems) |sys| {
            if (@TypeOf(sys) != type) {
                compError("System no. {d} is a {?}.\nEvery system registration must be a 'type'", .{ i, @TypeOf(sys) });
            }
            const sysInfo: std.builtin.TypeInfo = @typeInfo(sys);
            systemData[i] = sys;
            if (sysInfo != .Struct) {
                compError("System no. {d} is a {?}.\nEvery system must be a 'struct'", .{ i, sysInfo });
            }
            i += 1;
        }
        return systemData;
    }
}

const ComponentCompositionInfo = struct {
    componentCount: usize,
    archetypeCount: usize,
    archetypesSize: usize,
};

fn ComponentComposition(comptime info: ComponentCompositionInfo) type {
    return struct {
        components: [info.componentCount]type,
        archetypes: [info.archetypesSize]type,
        archetypesSizes: [info.archetypeCount]usize,

        fn componentTypeID(comptime self: @This(), comptime componentType: type) usize {
            comptime {
                for (self.components) |c, i| {
                    if (c == componentType) return i;
                }
                compError("{s} not registered by any system in this ecs", .{@typeName(componentType)});
            }
        }

        fn archetypeID(comptime self: @This(), comptime components: anytype) usize {
            comptime {
                if (@typeInfo(@TypeOf(components)) != .Struct) compError("archetype query must be a tuple", .{});

                var componentIndex = 0;
                for (self.archetypesSizes) |s, i| {
                    if (s == components.len) {
                        var j = 0;
                        while (j < s) : (j += 1) {
                            if (self.archetypes[componentIndex + j] != components[j]) break;
                        }
                        if (j == s) {
                            return i;
                        }
                    }
                    componentIndex += s;
                }

                compError("no archetype found for {?}", .{components});
            }
        }
    };
}

/// components: [info.componentCount]type
/// archetypes: [info.archetypesSize]type
/// archetypesSizes: [info.archetypeCount]usize
fn getComponentComposition(comptime systems: anytype, comptime count: bool) if (count) ComponentCompositionInfo else ComponentComposition(getComponentComposition(systems, true)) {
    comptime var componentTypeCount = 0;
    comptime var componentTypes = [_]?type{null} ** MAX_COMPONENT_TYPES;
    comptime var archetypeCount = 0;
    comptime var archetypeComponents: [MAX_ARCHETYPES][MAX_COMPONENTS_PER_ARCHETYPE]?type = undefined;
    comptime var archetypeComponentsCount = [_]usize{0} ** MAX_ARCHETYPES;

    comptime for (systems) |sys| {
        const sysInfo: std.builtin.TypeInfo = @typeInfo(sys);
        for (sysInfo.Struct.decls) |decl| {
            comptime var currentArchetype = [_]?type{null} ** MAX_COMPONENTS_PER_ARCHETYPE;
            //---- filter register* methods ----
            if (std.mem.startsWith(u8, decl.name, "register") and decl.data == .Fn) {
                if (decl.data.Fn.return_type != void) {
                    compError("return type of {s}.{s} must be void but was {s}", .{
                        @typeName(sys),
                        decl.name,
                        decl.data.Fn.return_type,
                    });
                }
                const registerInfo = @typeInfo(decl.data.Fn.fn_type);
                var last: []const u8 = "";
                var iArg = 0;
                //==== Check arguments ====
                //---- must have at least one component registration ----
                if (registerInfo.Fn.args.len < 3) {
                    compError("{s}.{s} must register at least one component", .{ @typeName(sys), decl.name });
                }
                for (registerInfo.Fn.args) |arg| {
                    //---- cannot be generic ----
                    if (arg.is_generic) {
                        compError("{s}.{s} cannot have generic parameters", .{ @typeName(sys), decl.name });
                    }
                    //---- first parameter must be self reference to the system ----
                    if (iArg == 0) {
                        if (arg.arg_type.? != *sys) {
                            compError("first parameter of {s}.{s} must be a self-reference", .{ @typeName(sys), decl.name });
                        }
                    }
                    //---- second parameter must be the entity ----
                    else if (iArg == 1) {
                        if (arg.arg_type.? != Entity) {
                            compError("second parameter of {s}.{s} must be an Entity-ID (usize)", .{ @typeName(sys), decl.name });
                        }
                    } else {
                        const currentComponent = @typeName(arg.arg_type.?);
                        if (last.len == 0) {
                            last = currentComponent;
                        }
                        //---- check that components are sorted alphabetically ----
                        else if (std.mem.lessThan(u8, currentComponent, last)) {
                            compError("please sort component parameters of {s}.{s} alphabetically", .{ @typeName(sys), decl.name });
                        }
                        //---- check that not the same component is used twice ----
                        else if (std.mem.eql(u8, currentComponent, last)) {
                            compError("please different component parameters in {s}.{s}", .{ @typeName(sys), decl.name });
                        }
                        //---- check that components are pointers to value types ----
                        if (arg.arg_type) |argType| {
                            const argInfo = @typeInfo(argType);
                            if (argInfo == .Pointer and @typeInfo(argInfo.Pointer.child) != .Pointer) {
                                //---- check if its a new component ----
                                comptime var i = 0;
                                while (i < componentTypeCount) : (i += 1) {
                                    if (componentTypes[i] == argInfo.Pointer.child) {
                                        break;
                                    }
                                }
                                //---- it's a new component type ----
                                if (i >= componentTypeCount or componentTypeCount == 0) {
                                    componentTypes[componentTypeCount] = argInfo.Pointer.child;
                                    componentTypeCount += 1;
                                }

                                //---- add component to tmp archetype ----
                                currentArchetype[iArg - 2] = argInfo.Pointer.child;
                            } else {
                                //TODO: can i support components as value types?
                                compError("{s}.{s} parameter #{d} {?} must be pointers to value type", .{ @typeName(sys), decl.name, iArg, arg.arg_type });
                            }
                        }
                        //---- TODO: find out when this case occurs ----
                        else {
                            compError("parameter {?} of {s}.{s} has no type", .{
                                arg,
                                @typeName(sys),
                                decl.name,
                            });
                        }
                    }
                    iArg += 1;
                }

                const componentCount = iArg - 2;

                //---- check if 'currentArchetype' is new ----
                var sameAs = -1;
                var archIndex = 0;
                while (archIndex < archetypeCount) : (archIndex += 1) {
                    comptime var compIndex = 0;
                    comptime var matchesArchetype = true;
                    while (compIndex < componentCount and compIndex < archetypeComponentsCount[archIndex]) : (compIndex += 1) {
                        if (archetypeComponents[archIndex][compIndex] == currentArchetype[compIndex].?) {
                            matchesArchetype = true;
                        } else {
                            //---- this is not the archetype im searching for ----
                            matchesArchetype = false;
                            break;
                        }
                    }
                    if (matchesArchetype and archetypeComponentsCount[archIndex] == componentCount) {
                        //---- found one archetype at 'archIndex' that matches the signature of 'registerInfo' ----
                        sameAs = archIndex;
                        break;
                    }
                }
                //---- is a new archetype ----
                if (sameAs < 0) {
                    var compIndex = 0;
                    while (compIndex < componentCount) : (compIndex += 1) {
                        archetypeComponents[archetypeCount][compIndex] = currentArchetype[compIndex];
                    }

                    archetypeComponentsCount[archetypeCount] = componentCount;
                    archetypeCount += 1;
                }
            }
        }
    };

    comptime var allArchetypeComponentCount = 0;
    comptime var i = 0;
    while (i < archetypeCount) : (i += 1) {
        allArchetypeComponentCount += archetypeComponentsCount[i];
    }
    comptime var info = ComponentCompositionInfo{
        .componentCount = componentTypeCount,
        .archetypeCount = archetypeCount,
        .archetypesSize = allArchetypeComponentCount,
    };

    if (count) {
        return info;
    }

    comptime var allComponents: [componentTypeCount]type = undefined;
    comptime var allArchetypes: [allArchetypeComponentCount]type = undefined;
    comptime var allArchetypeSizes: [archetypeCount]usize = undefined;
    i = 0;
    while (i < componentTypeCount) : (i += 1) {
        allComponents[i] = componentTypes[i].?;
    }

    i = 0;
    comptime var k = 0;
    while (i < archetypeCount) : (i += 1) {
        comptime var j = 0;
        while (j < archetypeComponentsCount[i]) : (j += 1) {
            allArchetypes[k] = archetypeComponents[i][j].?;
            k += 1;
        }
        allArchetypeSizes[i] = archetypeComponentsCount[i];
    }

    return ComponentComposition(info){
        .components = allComponents,
        .archetypes = allArchetypes,
        .archetypesSizes = allArchetypeSizes,
    };
}

fn archetypeOf(comptime A: anytype) type {
    const info = @typeInfo(@TypeOf(A));
    comptime {
        if (!trait.isTuple(@TypeOf(A))) {
            compError("archetype {?} must be a tuple", .{A});
        }
        var last: []const u8 = "";
        for (A) |c, i| {
            if (last.len != 0 and !std.mem.lessThan(u8, last, @as([]const u8, @typeName(c))))
                compError("archetype types must be alphabetically sorted and unique {?} index {d} is wrong", .{ A, i });
            last = @as([]const u8, @typeName(c));
        }
    }
    _ = info;

    var fields: [A.len]std.builtin.TypeInfo.StructField = undefined;
    for (A) |c, i| {
        fields[i] = std.builtin.TypeInfo.StructField{
            .name = @typeName(c),
            .field_type = c,
            .default_value = @as(?c, null),
            .is_comptime = false,
            .alignment = if (@sizeOf(c) > 0) @alignOf(c) else 0,
        };
    }
    var instanceType = std.builtin.TypeInfo{ .Struct = .{
        .layout = .Auto,
        .fields = &fields,
        .decls = &[_]std.builtin.TypeInfo.Declaration{},
        .is_tuple = true,
    } };
    return @Type(instanceType);
}

pub fn FreeIDs(comptime componentTypeCount: usize, comptime archetypeCount: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        entity: Stack(usize),
        component: [componentTypeCount]Stack(usize) = undefined,
        archetype: [archetypeCount]Stack(usize) = undefined,

        pub fn init(allocator: std.mem.Allocator) @This() {
            var ids = @This(){
                .allocator = allocator,
                .entity = Stack(usize).init(allocator),
            };
            var i: usize = 0;
            while (i < componentTypeCount) : (i += 1) {
                ids.component[i] = Stack(usize).init(allocator);
            }
            i = 0;
            while (i < archetypeCount) : (i += 1) {
                ids.archetype[i] = Stack(usize).init(allocator);
            }
            return ids;
        }

        pub fn deinit(self: *@This()) void {
            self.entity.deinit();
            var i: usize = 0;
            while (i < componentTypeCount) : (i += 1) {
                self.component[i].deinit();
            }
            i = 0;
            while (i < archetypeCount) : (i += 1) {
                self.archetype[i].deinit();
            }
        }
    };
}

fn compError(comptime fmt: []const u8, args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

//=== TESTS =======================================================================================

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

test "ECS" {
    // const expect = std.testing.expect;

    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    var system0 = @intToPtr(*Ecs.systems[0], ecs.systems[0]);
    try expectEqual(*TestABCSystem, @TypeOf(system0));
    system0.update(0.123);
}

test "ECS.system(self, type)" {
    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(std.testing.allocator);
    defer ecs.deinit();

    const aSystem = ecs.system(TestASystem);
    try expectEqual(*TestASystem, @TypeOf(aSystem));
}

test "ECS.create(self, components)" {
    const allocator = std.testing.allocator;
    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(allocator);
    defer ecs.deinit();

    const entity = try ecs.create(.{ AComponent{ .x = 123, .y = 456 }, BComponent{ .x = "9001" } });

    try expectEqual(@as(usize, 2), entity.components.len);
    try expectEqual(AComponent{ .x = 123, .y = 456 }, ecs.component(AComponent, entity.components[0].id).?);
}

test "ECS.componentIterator(self, T)" {
    const allocator = std.testing.allocator;
    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(allocator);
    defer ecs.deinit();

    _ = try ecs.create(.{ AComponent{ .x = 123, .y = 456 }, BComponent{ .x = "9001" } });

    var it = ecs.componentsIterator(AComponent);
    try expectEqual(AComponent{ .x = 123, .y = 456 }, it.next().?);
    try expect(it.next() == null);
}

test "ECS.remove(self, components)" {
    const allocator = std.testing.allocator;
    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(allocator);
    defer ecs.deinit();

    const entity = try ecs.create(.{ AComponent{ .x = 123, .y = 456 }, BComponent{ .x = "9001" } });

    try expectEqual(true, try ecs.remove(entity.components[0].typeID, entity.components[0].id));
    try expectEqual(false, try ecs.remove(entity.components[0].typeID, entity.components[0].id));
    try expectEqual(true, try ecs.remove(entity.components[1].typeID, entity.components[1].id));
    try expectEqual(false, try ecs.remove(entity.components[1].typeID, entity.components[1].id));
}

test "ECS.entity(self, id)" {
    const allocator = std.testing.allocator;
    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(allocator);
    defer ecs.deinit();

    const e = try ecs.create(.{ AComponent{ .x = 1, .y = 2 }, BComponent{ .x = "9001" } });
    try expectEqual(@as(usize, 0), e.id);
    try expectEqual(@as(usize, 2), e.components.len);
    try expectEqual(AComponent{ .x = 1, .y = 2 }, ecs.component(AComponent, e.components[0].id).?);
    try expectEqual(BComponent{ .x = "9001" }, ecs.component(BComponent, e.components[1].id).?);

    const entity = ecs.entity(0);
    try expect(entity != null);
    try expectEqual(@as(usize, 0), entity.?.id);
    try expectEqual(@as(usize, 2), entity.?.components.len);
    try expectEqual(AComponent{ .x = 1, .y = 2 }, ecs.component(AComponent, entity.?.components[0].id).?);
    try expectEqual(BComponent{ .x = "9001" }, ecs.component(BComponent, entity.?.components[1].id).?);
}

test "ECS.destroy(self, id)" {
    const allocator = std.testing.allocator;
    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(allocator);
    defer ecs.deinit();

    const e = try ecs.create(.{ AComponent{ .x = 1, .y = 2 }, BComponent{ .x = "9001" } });

    try expectEqual(true, try ecs.destroy(e.id));

    const notFound = ecs.entity(e.id);
    try expect(notFound == null);
}

test "ECS.destroy create destroy" {
    const allocator = std.testing.allocator;
    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(allocator);
    defer ecs.deinit();

    var e = try ecs.create(.{ AComponent{ .x = 1, .y = 2 }, BComponent{ .x = "9001" } });
    try expectEqual(true, try ecs.destroy(e.id));
    e = try ecs.create(.{ AComponent{ .x = 2, .y = 3 }, BComponent{ .x = "9002" } });
    e = ecs.entity(e.id).?;

    try expectEqual(@as(usize, 0), e.id);
    try expectEqual(@as(usize, 2), e.components.len);
    try expectEqual(AComponent{ .x = 2, .y = 3 }, ecs.component(AComponent, e.components[0].id).?);
    try expectEqual(BComponent{ .x = "9002" }, ecs.component(BComponent, e.components[1].id).?);
}

test "ECS.add(self, component)" {
    const allocator = std.testing.allocator;
    const Ecs = ECS(.{ TestABCSystem, TestASystem });
    var ecs = try Ecs.init(allocator);
    defer ecs.deinit();

    var e1 = try ecs.create(.{AComponent{ .x = 1, .y = 2 }});
    var e2 = try ecs.create(.{AComponent{ .x = 1, .y = 2 }});
    const newComponent1 = try ecs.add(e1.id, CComponent{ .x = 5, .y = 545, .speed = 0.11 });
    const newComponent2 = try ecs.add(e1.id, CComponent{ .x = 5, .y = 545, .speed = 0.11 });
    const newComponent3 = try ecs.add(e2.id, CComponent{ .x = 5, .y = 545, .speed = 0.11 });

    try expectEqual(Component{
        .id = 0, //because its a different component
        .typeID = Ecs.composition.componentTypeID(CComponent),
    }, newComponent1);
    try expectEqual(Component{
        .id = 1,
        .typeID = Ecs.composition.componentTypeID(CComponent),
    }, newComponent2);
    try expectEqual(Component{
        .id = 2,
        .typeID = Ecs.composition.componentTypeID(CComponent),
    }, newComponent3);
}

test "archetypeOf" {
    const a = archetypeOf(.{ AComponent, BComponent, CComponent });
    const aInfo = @typeInfo(a);
    try expect(aInfo == .Struct);
    try expectEqual(AComponent, aInfo.Struct.fields[0].field_type);
    try expectEqual(BComponent, aInfo.Struct.fields[1].field_type);
    try expectEqual(CComponent, aInfo.Struct.fields[2].field_type);

    var instanceOfA = a{
        AComponent{ .x = 1, .y = 2 },
        BComponent{ .x = "123" },
        CComponent{ .x = 3, .y = 4, .speed = 11 },
    };

    try expectEqual(@as(usize, 3), instanceOfA.len);
    try expectEqual(AComponent{ .x = 1, .y = 2 }, instanceOfA[0]);
    try expectEqual(BComponent{ .x = "123" }, instanceOfA[1]);
    try expectEqual(CComponent{ .x = 3, .y = 4, .speed = 11 }, instanceOfA[2]);
}

test "" {}

test "getSystemTypes" {
    const systemTypes = getSystemTypes(.{ TestABCSystem, TestASystem });

    try expectEqual(2, systemTypes.len);
    try expectEqual(TestABCSystem, systemTypes[0]);
    try expectEqual(TestASystem, systemTypes[1]);
}

test "getComponentComposition(_, true)" {
    const componentCompositionInfo: ComponentCompositionInfo = comptime getComponentComposition(.{ TestASystem, TestABCSystem }, true);
    // comptime compError("{?}", .{componentCompositionInfo});
    try expectEqual(3, componentCompositionInfo.componentCount);
    try expectEqual(6, componentCompositionInfo.archetypeCount);
    try expectEqual(10, componentCompositionInfo.archetypesSize);
}

test "getComponentComposition(_, false)" {
    const componentComposition = comptime getComponentComposition(.{ TestASystem, TestABCSystem }, false);

    // comptime compError("{?}", .{componentComposition});
    try expectEqual(3, componentComposition.components.len);
    try expectEqual(AComponent, componentComposition.components[0]);
    try expectEqual(BComponent, componentComposition.components[1]);
    try expectEqual(CComponent, componentComposition.components[2]);

    try expectEqual(6, componentComposition.archetypesSizes.len);
    try expectEqual(1, componentComposition.archetypesSizes[0]);
    try expectEqual(2, componentComposition.archetypesSizes[1]);
    try expectEqual(3, componentComposition.archetypesSizes[2]);
    try expectEqual(2, componentComposition.archetypesSizes[3]);
    try expectEqual(1, componentComposition.archetypesSizes[4]);
    try expectEqual(1, componentComposition.archetypesSizes[5]);

    try expectEqual(10, componentComposition.archetypes.len);
    try expectEqual(AComponent, componentComposition.archetypes[0]);
    try expectEqual(AComponent, componentComposition.archetypes[1]);
    try expectEqual(BComponent, componentComposition.archetypes[2]);
    try expectEqual(AComponent, componentComposition.archetypes[3]);
    try expectEqual(BComponent, componentComposition.archetypes[4]);
    try expectEqual(CComponent, componentComposition.archetypes[5]);
    try expectEqual(BComponent, componentComposition.archetypes[6]);
    try expectEqual(CComponent, componentComposition.archetypes[7]);
    try expectEqual(CComponent, componentComposition.archetypes[8]);
    try expectEqual(BComponent, componentComposition.archetypes[9]);
}

test "ComponentComposition.componentTypeID" {
    const sut = comptime getComponentComposition(.{TestASystem}, false);

    try expectEqual(sut.componentTypeID(AComponent), 0);
    try expectEqual(sut.componentTypeID(BComponent), 1);
}

test "ComponentComposition.archetypeID" {
    const sut = comptime getComponentComposition(.{TestABCSystem}, false);

    try expectEqual(sut.archetypeID(.{ AComponent, BComponent, CComponent }), 0);
    try expectEqual(sut.archetypeID(.{AComponent}), 1);
    try expectEqual(sut.archetypeID(.{ BComponent, CComponent }), 2);
}

test "component to bytes and back" {
    //if the memory layout of this struct changes, the test will fail
    var compA = AComponent{ .x = 1.0, .y = 2.0 };

    const v = std.mem.toBytes(compA);
    try expectEqual([_]u8{ 0, 0, 128, 63, 0, 0, 0, 64 }, v);

    const p = std.mem.asBytes(&compA);
    try expectEqualSlices(u8, &[_]u8{ 0, 0, 128, 63, 0, 0, 0, 64 }, p);

    const cloneOfCompA = std.mem.bytesToValue(AComponent, &v);
    try expectEqual(compA, cloneOfCompA);
    const ptrToCompA = std.mem.bytesAsValue(AComponent, &v);
    try expectEqual(compA, ptrToCompA.*);
}

const TestASystem = struct {
    ecs: EntityComponentSystem,

    //>>>>>>> Allocaton >>>>>>>>>>>>>>>>>>>>>>>>>
    // a System can have its own allocation scheme
    // otherwise it is created with:
    // ecs.allocator.create(SystenType)
    // and destroyed with:
    // self.allocator.destroy(self)
    //-------------------------------------------
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator, ecs: EntityComponentSystem) !*@This() {
        var this = try allocator.create(@This());
        this.allocator = allocator;
        this.ecs = ecs;
        return this;
    }
    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self);
    }
    //<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    pub fn update(_: *@This(), dt: f32) void {
        _ = dt;
    }

    pub fn registerA(self: *@This(), entity: Entity, _: *AComponent) void {
        _ = self;
        _ = entity;
    }

    pub fn registerC(self: *@This(), entity: Entity, _: *AComponent, _: *BComponent) void {
        _ = self;
        _ = entity;
    }
};

const TestABCSystem = struct {
    ecs: EntityComponentSystem,

    /// all before's are called before all update functions
    pub fn before(_: *@This(), dt: f32) void {
        _ = dt;
    }

    /// called every frame
    pub fn update(_: *@This(), dt: f32) void {
        _ = dt;
    }

    /// all after's are called after all update functions
    pub fn after(_: *@This(), dt: f32) void {
        _ = dt;
    }

    pub fn registerABC(self: *@This(), entity: Entity, _: *AComponent, _: *BComponent, _: *CComponent) void {
        _ = self;
        _ = entity;
    }

    pub fn registerA(self: *@This(), entity: Entity, _: *AComponent) void {
        _ = self;
        _ = entity;
    }

    pub fn registerBC(self: *@This(), entity: Entity, _: *BComponent, _: *CComponent) void {
        _ = self;
        _ = entity;
    }

    pub fn registerC(self: *@This(), entity: Entity, _: *CComponent) void {
        _ = self;
        _ = entity;
    }

    pub fn registerB(self: *@This(), entity: Entity, _: *BComponent) void {
        _ = self;
        _ = entity;
    }
};

const AComponent = struct {
    x: f32,
    y: f32,
};

const BComponent = struct {
    x: []const u8,
};

const CComponent = struct {
    x: f32,
    y: f32,
    speed: f32,
};
