//! inspired by:
//! https://devlog.hexops.com/2022/lets-build-ecs-part-1/
//! https://devlog.hexops.com/2022/lets-build-ecs-part-2-databases/

const std = @import("std");
const meta = std.meta;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const voidArchetype: u64 = 0;
pub const EntityID = usize;
const ArchetypeHash = u64;

pub fn archetypeHash(comptime arch: anytype) ArchetypeHash {
    comptime var ty = @TypeOf(arch);
    const isStruct = ty == type or @typeInfo(ty) == .Struct;
    comptime var archLen: usize = 0;
    comptime if (isStruct) {
        archLen = @typeInfo(arch).Struct.fields.len;
        ty = arch;
    } else {
        archLen = arch.len;
    };

    if (archLen == 0) {
        return voidArchetype;
    }

    const tyInfo: std.builtin.Type = @typeInfo(ty);
    comptime if (tyInfo != .Struct) {
        compError("expected tuple or Archetype(T), but was {?} ", .{ty});
    };

    comptime if (!meta.trait.isTuple(ty)) {
        inline for (tyInfo.Struct.fields) |field| {
            if (!std.mem.eql(u8, field.name, @typeName(field.field_type))) {
                //field names must match type names
                compError("this struct was not created with Archetype(T)", .{});
            }
        }
    };

    var hash: ArchetypeHash = 0;
    inline for (if (isStruct) @typeInfo(arch).Struct.fields else arch) |TQ| {
        const T = if (isStruct) TQ.field_type else TQ;
        const name = @typeName(T);
        hash ^= std.hash.Wyhash.hash(0, name);
    }

    return hash;
}

test "archetypeHash" {
    try expectEqual(
        @as(ArchetypeHash, 16681995284927388974),
        archetypeHash(.{Position}),
    );

    //same
    try expectEqual(
        @as(ArchetypeHash, 8074083904701951711),
        archetypeHash(.{ Position, Target }),
    );
    try expectEqual(
        @as(ArchetypeHash, 8074083904701951711),
        archetypeHash(.{ Target, Position }),
    );
    //----

    //same
    try expectEqual(
        @as(ArchetypeHash, 12484014990812011213),
        archetypeHash(.{ Target, Position, Name }),
    );
    try expectEqual(
        @as(ArchetypeHash, 12484014990812011213),
        archetypeHash(.{ Position, Target, Name }),
    );
    try expectEqual(
        @as(ArchetypeHash, 12484014990812011213),
        archetypeHash(.{ Name, Target, Position }),
    );
    //----
}

fn Archetype(comptime arch: anytype) type {
    comptime var ty = @TypeOf(arch);
    const isStruct = ty == type;
    comptime var archLen: usize = 0;
    comptime if (isStruct) {
        archLen = @typeInfo(arch).Struct.fields.len;
        ty = arch;
    } else {
        archLen = arch.len;
    };
    const tyInfo: std.builtin.Type = @typeInfo(ty);
    comptime if (tyInfo != .Struct) {
        compError("expected tuple or Archetype(T), but was {?} ", .{ty});
    };

    comptime if (!meta.trait.isTuple(ty)) {
        inline for (tyInfo.Struct.fields) |field| {
            if (!std.mem.eql(u8, field.name, @typeName(field.field_type))) {
                //field names must match type names
                compError("this struct was not created with Archetype(T)\n\texpected: {1s}: {1s},\n\tactual: {0s}: {1s},", .{ field.name, @typeName(field.field_type) });
            }
        }
    };

    var structFields: [archLen]std.builtin.Type.StructField = undefined;
    inline for (if (isStruct) @typeInfo(arch).Struct.fields else arch) |TQ, i| {
        const T = if (isStruct) TQ.field_type else TQ;
        @setEvalBranchQuota(10_000);
        var nameBuf: [4 * 1024]u8 = undefined;
        structFields[i] = .{
            .name = std.fmt.bufPrint(&nameBuf, "{s}", .{@typeName(T)}) catch unreachable,
            .field_type = *T,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(T) > 0) @alignOf(T) else 0,
        };
    }

    const lessThan = (struct {
        pub fn lessThan(_: void, comptime lhs: std.builtin.Type.StructField, comptime rhs: std.builtin.Type.StructField) bool {
            const smaller = std.math.min(lhs.name.len, rhs.name.len);
            var i: usize = 0;
            while (i < smaller) : (i += 1) {
                if (lhs.name[i] < rhs.name[i]) {
                    return true;
                }
            }

            return lhs.name.len < rhs.name.len;
        }
    }).lessThan;

    std.sort.sort(std.builtin.Type.StructField, &structFields, {}, lessThan);

    return @Type(.{
        .Struct = .{
            .is_tuple = false,
            .layout = .Auto,
            .decls = &.{},
            .fields = &structFields,
        },
    });
}

test "Archetype with tuples" {
    const Sone = Archetype(.{Position});
    var s1: Sone = .{ .Position = Position{ .x = 1, .y = 2 } };
    try expectEqual(s1.Position, Position{ .x = 1, .y = 2 });

    const Stwo = Archetype(.{ Position, Name, Target });
    var s2: Stwo = .{
        .Position = Position{ .x = 1, .y = 2 },
        .Name = .{ .name = "test" },
        .Target = .{ .x = 0.5, .y = 10 },
    };
    try expectEqual(s2.Position, Position{ .x = 1, .y = 2 });
    try expectEqual(s2.Target, Target{ .x = 0.5, .y = 10 });
    try expectEqual(s2.Name, Name{ .name = "test" });

    //// dont compare archetype types like that, use `archetypeHash(a1) == archetypeHash(a2)` instead
    // try expectEqual(Archetype(.{ Position, Name, Target }), Archetype(.{ Position, Name, Target }));
    // try expectEqual(Archetype(.{ Position, Name, Target }), Archetype(.{ Name, Position, Target }));
}

test "Archetype with structs" {
    const Archetype1 = struct {
        Position: Position,
        Target: Target,
        Name: Name,
    };
    const A1 = Archetype(Archetype1);

    const a1: Archetype1 = .{
        .Position = .{ .x = 0, .y = 0 },
        .Target = .{ .x = 0, .y = 0 },
        .Name = .{ .name = "" },
    };

    try expectEqual(archetypeHash(.{ Position, Target, Name }), archetypeHash(A1));
    try expectEqual(archetypeHash(.{ Name, Target, Position }), archetypeHash(A1));
    try expectEqual(archetypeHash(.{ Name, Target, Position }), archetypeHash(Archetype1));
    try expectEqual(archetypeHash(.{ Position, Target, Name }), archetypeHash(Archetype1));
    try expectEqual(archetypeHash(A1), archetypeHash(a1));

    //// this will not work as field names must match type names
    // const NotAnArchetype = struct {
    //     lol: Position,
    //     foo: Target,
    //     bar: Name,
    // };
    // _ = Archetype(NotAnArchetype);
}

const ArchetypeEntry = struct {
    storage: ArchetypeHash,
    index: usize,
};

const ArchetypeStorage = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    hash: ArchetypeHash,
    len: usize = 0,

    entities: std.AutoArrayHashMap(EntityID, usize),
    data: std.AutoArrayHashMap(usize, *anyopaque),
    _addEntry: fn (this: *Self) anyerror!usize,
    _removeEntry: fn (this: *Self, index: usize) void,

    pub fn init(allocator: std.mem.Allocator, comptime arch: anytype) !Self {
        var data = std.AutoArrayHashMap(usize, *anyopaque).init(allocator);

        inline for (arch) |T| {
            var list = try allocator.create(std.ArrayList(T));
            list.* = std.ArrayList(T).init(allocator);

            data.put(typeId(T), @ptrCast(*anyopaque, list));
        }

        return Self{
            .allocator = allocator,
            .data = data,
            ._addEntry = (struct {
                pub fn addEntry(this: *Self, entity: EntityID) !usize {
                    inline for (arch) |T| {
                        var listPtr = this.data.getPtr(typeId(T)).?;
                        var list = @ptrCast(*std.ArrayList(T), listPtr);
                        _ = try list.addOne();
                        errdefer list.swapRemove(list.items.len - 1);
                    }
                    const index = this.len;
                    try this.entities.put(entity, index);
                    this.len += 1;
                    return index;
                }
            }).addEntry,
            ._removeEntry = (struct {
                pub fn removeEntry(this: *Self, index: usize) void {
                    const lastIndex = this.len - 1;
                    inline for (arch) |T| {
                        var listPtr = this.data.getPtr(typeId(T)).?;
                        var list = @ptrCast(*std.ArrayList(T), listPtr);
                        list.swapRemove(index);
                    }
                    var indices = this.entities.values();
                    for (indices) |*i| {
                        if (i.* == lastIndex) {
                            i.* = index;
                            break;
                        }
                    }
                    this.len -= 1;
                }
            }).removeEntry,
        };
    }

    pub fn has(this: *Self, comptime TComponent: type) bool {
        return this.data.contains(typeId(TComponent));
    }

    /// always check first, with `has`, if this storage really contains components of type `TComponent`
    pub fn slice(this: *Self, comptime TComponent: type) []TComponent {
        var ptr = this.data.getPtr(typeId(TComponent));
        var list = @ptrCast(*std.ArrayList(TComponent), ptr);
        return list.items;
    }

    // pub fn query(this: *Self, arch: anytype) ArchetypeIterator(Archetype(arch)) {
    //     //TODO: implement query
    // }

    pub fn insert(this: *Self, entity: anytype) !Archetype(entity) {
        const info: std.builtin.Type = @typeInfo(@TypeOf(entity));
        if (info != .Struct) compError("entity is not in Archetype(T) format", .{});

        const index = try this.addEntry();
        var arch = Archetype(entity);

        inline for (info.Struct.fields) |field| {
            const fieldInfo = @typeInfo(field.field_type);
            const isArchetypeField = fieldInfo == .Pointer and std.mem.eql(u8, field.name, @typeName(field.field_type));
            if (!isArchetypeField) continue;
            const typeKey = typeId(fieldInfo.Pointer.child);
            if (this.data.getPtr(typeKey)) |listPtr| {
                var list = @ptrCast(*std.ArrayList(fieldInfo.Pointer.child), listPtr);
                list.items[index] = @field(entity, field.name).*;
                @field(arch, field.name) = &list.items[index];
            }
        }
        return arch;
    }

    pub fn remove(this: *Self, index: usize) void {
        this.removeEntry(index);
    }
};

//TODO: implement iterator that jumps to next archetype
// pub fn ArchetypeIterator(comptime A: type) type {
//     return struct {};
// }

test "query" {
    var ecs = try ECS.init(t.allocator);
    defer ecs.deinit();

    // var it = ecs.query(.{ Position, Name });
}

pub const ECS = struct {
    allocator: std.mem.Allocator,
    window: struct { size: struct { x: f32, y: f32 } = .{ .x = 100, .y = 100 } } = .{},
    systems: std.ArrayList(System),
    nextEnitityID: EntityID = 1,
    enitities: std.AutoArrayHashMap(EntityID, *ArchetypeStorage),
    archetypes: std.AutoArrayHashMap(ArchetypeHash, ArchetypeStorage),

    ///
    pub fn init(
        allocator: std.mem.Allocator,
    ) !@This() {
        return @This(){
            .allocator = allocator,
            .systems = std.ArrayList(System).init(allocator),
            .enitities = std.AutoArrayHashMap(EntityID, ArchetypeEntry).init(allocator),
            .archetypes = std.AutoArrayHashMap(ArchetypeHash, ArchetypeStorage).init(allocator),
        };
    }

    pub fn deinit(this: *@This()) void {
        for (this.systems.items) |*sys| {
            sys.deinit();
        }
        this.systems.deinit();

        for (this.archetypes.values()) |*storage| {
            storage.deinit();
        }
        this.archetypes.deinit();

        this.enitities.deinit();
    }

    //=== Entity ==================================================================================
    pub fn create(this: *@This(), archetype: anytype) !EntityID {
        var entry = try this.archetypes.getOrPut(archetypeHash(archetype));
        errdefer this.archetypes.swapRemove(entry.key_ptr.*);
        const id = this.nextEnitityID;
        this.nextEnitityID += 1;

        if (!entry.found_existing) {
            entry.value_ptr.* = try ArchetypeStorage.init(this.allocator, archetype);
        }

        return id;
    }

    //=== Component ===============================================================================

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
