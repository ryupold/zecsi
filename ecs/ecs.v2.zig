//! inspired by:
//! https://devlog.hexops.com/2022/lets-build-ecs-part-1/
//! https://devlog.hexops.com/2022/lets-build-ecs-part-2-databases/

const std = @import("std");
const meta = std.meta;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const voidArchetype: u64 = std.math.maxInt(u64);
pub const EntityID = usize;
const ArchetypeHash = u64;

pub fn archetypeHash(comptime arch: anytype) ArchetypeHash {
    const ty = @TypeOf(arch);
    const tyInfo: std.builtin.Type = @typeInfo(ty);
    comptime if (!meta.trait.isTuple(ty)) {
        compError("expected tuple of types but got {?}", .{arch});
    };
    // comptime var ty = @TypeOf(arch);
    // const isStruct = ty == type or @typeInfo(ty) == .Struct;
    // if(ty == type){ ty = arch;}
    // comptime var archLen: usize = 0;
    // comptime if (isStruct) {
    //     archLen = @typeInfo(arch).Struct.fields.len;
    //     ty = arch;
    // } else {
    //     archLen = arch.len;
    // };

    if (arch.len == 0) {
        return voidArchetype;
    }

    // comptime if (tyInfo != .Struct) {
    //     compError("expected tuple or Archetype(T), but was {?} ", .{ty});
    // };

    inline for (tyInfo.Struct.fields) |field| {
        if (@TypeOf(field.field_type) != type) {
            compError("expected tuple of types but got {?}", .{arch});
        }
    }

    var hash: ArchetypeHash = 0;
    inline for (arch) |T| {
        const name = @typeName(T);
        hash ^= std.hash.Wyhash.hash(0, name);
    }

    return hash;
}

test "archetypeHash" {
    // void storage has ID std.math.maxInt(u64)
    try expectEqual(
        @as(ArchetypeHash, std.math.maxInt(u64)),
        archetypeHash(.{}),
    );

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

fn ArchetypePointers(comptime arch: anytype) type {
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

fn ArchetypeSlices(comptime arch: anytype) type {
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
            .field_type = []T,
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

test "ArchetypePointers with tuples" {
    const Sone = ArchetypePointers(.{Position});
    var p = Position{ .x = 1, .y = 2 };
    var s1: Sone = .{ .Position = &p };
    try expectEqual(s1.Position, &p);

    // const Stwo = ArchetypePointers(.{ Position, Name, Target });
    // var s2: Stwo = .{
    //     .Position = Position{ .x = 1, .y = 2 },
    //     .Name = .{ .name = "test" },
    //     .Target = .{ .x = 0.5, .y = 10 },
    // };
    // try expectEqual(s2.Position, Position{ .x = 1, .y = 2 });
    // try expectEqual(s2.Target, Target{ .x = 0.5, .y = 10 });
    // try expectEqual(s2.Name, Name{ .name = "test" });

    //// dont compare archetype types like that, use `archetypeHash(a1) == archetypeHash(a2)` instead
    // try expectEqual(Archetype(.{ Position, Name, Target }), Archetype(.{ Position, Name, Target }));
    // try expectEqual(Archetype(.{ Position, Name, Target }), Archetype(.{ Name, Position, Target }));
}

test "ArchetypePointers with structs" {
    // const Archetype1 = struct {
    //     Position: Position,
    //     Target: Target,
    //     Name: Name,
    // };
    // const A1 = ArchetypePointers(Archetype1);

    // const a1: Archetype1 = .{
    //     .Position = .{ .x = 0, .y = 0 },
    //     .Target = .{ .x = 0, .y = 0 },
    //     .Name = .{ .name = "" },
    // };

    // try expectEqual(archetypeHash(.{ Position, Target, Name }), archetypeHash(A1));
    // try expectEqual(archetypeHash(.{ Name, Target, Position }), archetypeHash(A1));
    // try expectEqual(archetypeHash(.{ Name, Target, Position }), archetypeHash(Archetype1));
    // try expectEqual(archetypeHash(.{ Position, Target, Name }), archetypeHash(Archetype1));
    // try expectEqual(archetypeHash(A1), archetypeHash(a1));

    //// this will not work as field names must match type names
    // const NotAnArchetype = struct {
    //     lol: Position,
    //     foo: Target,
    //     bar: Name,
    // };
    // _ = Archetype(NotAnArchetype);
}

test "ArchetypeSlices" {
    //TODO:
}

const ArchetypeStorage = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    hash: ArchetypeHash,
    len: usize = 0,

    entityIndexMap: std.AutoArrayHashMap(EntityID, usize),
    entityIDRow: std.ArrayList(EntityID),
    addedEntityIDRow: std.ArrayList(EntityID),
    removedEntities: std.AutoArrayHashMap(EntityID, void),

    data: std.AutoArrayHashMap(usize, *anyopaque),
    addedData: std.AutoArrayHashMap(usize, *anyopaque),

    _addEntry: fn (this: *Self, entity: EntityID, previousStorage: ArchetypeStorage) anyerror!void,
    _removeEntry: fn (this: *Self, entity: EntityID) anyerror!void,
    _sync: fn (this: *Self) anyerror!void,
    _deinit: fn (this: *Self) void,

    pub fn init(allocator: std.mem.Allocator, comptime arch: anytype) !Self {
        const hash = archetypeHash(arch);
        var data = std.AutoArrayHashMap(usize, *anyopaque).init(allocator);
        var addedData = std.AutoArrayHashMap(usize, *anyopaque).init(allocator);
        var removedEntities = std.AutoArrayHashMap(EntityID, void).init(allocator);

        inline for (arch) |T| {
            var list = try allocator.create(std.ArrayList(T));
            list.* = std.ArrayList(T).init(allocator);
            try data.put(typeId(T), @ptrCast(*anyopaque, list));

            var addedList = try allocator.create(std.ArrayList(T));
            addedList.* = std.ArrayList(T).init(allocator);
            try addedData.put(typeId(T), @ptrCast(*anyopaque, addedList));
        }

        return Self{
            .allocator = allocator,
            .hash = hash,
            .data = data,
            .addedData = addedData,
            .entityIndexMap = std.AutoArrayHashMap(EntityID, usize).init(allocator),
            .entityIDRow = std.ArrayList(EntityID).init(allocator),
            .addedEntityIDRow = std.ArrayList(EntityID).init(allocator),
            .removedEntities = removedEntities,

            ._addEntry = if (arch.len == 0) (struct {
                pub fn addToVoid(this: *Self, entity: EntityID, previousStorage: ArchetypeStorage) !void {
                    //find index of entity in previous archetype
                    var index = previousStorage.entityIndexMap.get(entity);
                    // if it was added in this frame, it is held in the addedData container of previousStorage
                    const isVolatile = index == null;
                    if (isVolatile) {
                        for (previousStorage.addedEntityIDRow.items) |aE, i| {
                            if (aE == entity) {
                                index = i;
                                break;
                            }
                        }
                    }
                    if (index != null) return;

                    // add entity to added list
                    try this.addedEntityIDRow.append(entity);
                }
            }).addToVoid else (struct {
                pub fn addEntry(this: *Self, entity: EntityID, previousStorage: ArchetypeStorage) !void {
                    //find index of entity in previous archetype
                    var index = previousStorage.entityIndexMap.get(entity);
                    // if it was added in this frame, it is held in the addedData container of previousStorage
                    const isVolatile = index == null;
                    if (isVolatile) {
                        for (previousStorage.addedEntityIDRow.items) |aE, i| {
                            if (aE == entity) {
                                index = i;
                                break;
                            }
                        }
                    }
                    if (index == null) return error.EntityNotFound;

                    //find correct storage
                    var dataStorage = if (isVolatile)
                        previousStorage.addedData
                    else
                        previousStorage.data;

                    //for each component type
                    inline for (arch) |T| {
                        // if previos archetype contained this component
                        var listPtr = this.addedData.get(typeId(T)).?;
                        var list = castColumn(T, listPtr);
                        if (dataStorage.get(typeId(T))) |previousListPtr| {
                            var previousList = castColumn(T, previousListPtr);
                            // add component to added list
                            try list.append(previousList.items[index.?]);
                        } else {
                            //this case only occurs if we are stepping up to a greater archetype
                            //add entry to component list which previousStorage hadn't
                            _ = try list.addOne(); //TODO: put new component data in here
                        }
                    }
                    // add entity to added list
                    try this.addedEntityIDRow.append(entity);
                }
            }).addEntry,
            ._removeEntry = (struct {
                pub fn removeEntry(this: *Self, entity: EntityID) !void {
                    //is entity in "persistent" storage?
                    var index = this.entityIndexMap.get(entity);
                    const isVolatile = index == null;

                    // is entity in temp storage?
                    if (index == null) {
                        for (this.addedEntityIDRow.items) |aE, i| {
                            if (aE == entity) {
                                index = i;
                                break;
                            }
                        }
                    }
                    if (index == null) return error.EntityNotFound;

                    //if the storage contains the entity to remove in the temp data
                    if (isVolatile) {
                        //delete the entry before it gets synced
                        inline for (arch) |T| {
                            var listPtr = this.addedData.get(typeId(T)).?;
                            var list = castColumn(T, listPtr);
                            _ = list.swapRemove(index.?);
                        }
                        _ = this.addedEntityIDRow.swapRemove(index.?);
                    } else {
                        //otherwise add to removed list
                        try this.removedEntities.put(entity, {});
                    }
                }
            }).removeEntry,
            ._sync = (struct {
                pub fn sync(this: *Self) !void {
                    //add
                    inline for (arch) |T| {
                        var addedListPtr = this.addedData.get(typeId(T)).?;
                        var addedList = castColumn(T, addedListPtr);

                        var listPtr = this.data.get(typeId(T)).?;
                        var list = castColumn(T, listPtr);

                        try list.appendSlice(addedList.items);
                        this.len += addedList.items.len;
                        addedList.clearAndFree();
                    }
                    for(this.addedEntityIDRow.items) |aE| {
                        const index = this.entityIDRow.items.len;
                        try this.entityIDRow.append(aE);
                        try this.entityIndexMap.put(aE, index);
                    }
                    this.addedEntityIDRow.clearAndFree();

                    //remove
                    for (this.removedEntities.keys()) |removed| {
                        if (this.entityIndexMap.get(removed)) |index| {
                            inline for (arch) |T| {
                                var listPtr = this.data.get(typeId(T)).?;
                                var list = castColumn(T, listPtr);

                                _ = list.swapRemove(index);
                            }
                            _ = this.entityIDRow.swapRemove(index);
                            if (index < this.entityIDRow.items.len - 1) {
                                const swappedEntity = this.entityIDRow.items[index];
                                try this.entityIndexMap.put(swappedEntity, index);
                            }
                        }
                        _ = this.entityIndexMap.swapRemove(removed);
                    }
                    this.len -= this.removedEntities.count();
                    this.removedEntities.clearAndFree();
                }
            }).sync,
            ._deinit = (struct {
                pub fn deinit(this: *Self) void {
                    inline for (arch) |T| {
                        var listPtr = this.data.get(typeId(T)).?;
                        var list = castColumn(T, listPtr);
                        list.deinit();
                        this.allocator.destroy(list);

                        var addedListPtr = this.addedData.get(typeId(T)).?;
                        var addedList = castColumn(T, addedListPtr);
                        addedList.deinit();
                        this.allocator.destroy(addedList);
                    }
                }
            }).deinit,
        };
    }

    pub fn deinit(this: *@This()) void {
        this._deinit(this);
        this.entityIndexMap.deinit();
        this.entityIDRow.deinit();
        this.data.deinit();
        this.addedData.deinit();
        this.addedEntityIDRow.deinit();
        this.removedEntities.deinit();
    }

    fn castColumn(comptime T: type, ptr: *anyopaque) *std.ArrayList(T) {
        return @ptrCast(*std.ArrayList(T), @alignCast(@alignOf(*std.ArrayList(T)), ptr));
    }

    pub fn has(this: *Self, comptime TComponent: type) bool {
        return this.data.contains(typeId(TComponent));
    }

    /// put component data for specified entity
    /// ```zig
    /// const e: EntityID = 312; //assuming this entity exists in this ArchetypeStorage
    /// const p = Position{.x = 5, .y=0.7};
    /// try put(e, .{p});
    /// ```
    pub fn put(this: *Self, entity: EntityID, componentData: anytype) error{ ComponentNotPartOfArchetype, EntityNotFound }!void {
        const T = @TypeOf(componentData);
        if (this.entityIndexMap.get(entity)) |index| {
            if (this.data.get(typeId(T))) |listPtr| {
                var list = castColumn(T, listPtr);
                list.items[index] = componentData;
            } else return error.ComponentNotPartOfArchetype;
        } else {
            for (this.addedEntityIDRow.items) |aE, index| {
                if (aE == entity) {
                    if (this.addedData.get(typeId(T))) |addedListPtr| {
                        var addedList = castColumn(T, addedListPtr);
                        addedList.items[index] = componentData;
                        return;
                    }
                }
            }
            return error.EntityNotFound;
        }
    }

    /// always check first, with `has`, if this storage really contains components of type `TComponent`
    pub fn slice(this: *Self, comptime TComponent: type) error{ComponentNotPartOfArchetype}![]TComponent {
        if (this.data.get(typeId(TComponent))) |listPtr| {
            var list = castColumn(TComponent, listPtr);
            return list.items;
        }
        return error.ComponentNotPartOfArchetype;
    }

    // pub fn query(this: *Self, arch: anytype) ?ArchetypeIterator(Archetype(arch)) {
    //     //TODO: implement query
    // }

    /// copy entity to this ArchetypeStorage with data of previous storage
    /// this won't make the entity (data) available directly but a call to `sync` is necessary to
    /// make the change permanent. This happens usually at the end of the frame (after all before, update, after, ui steps).
    /// this is a readonly operation on the previous ArchetypeStorage, it will keep its values
    /// call `delete` on the previous storage afterwards
    pub fn copy(this: *Self, entity: EntityID, previousStorage: ArchetypeStorage) !void {
        _ = try this._addEntry(this, entity, previousStorage);
    }

    /// mark an entity as deleted in this storage.
    /// this will take effect after a call to `sync`
    pub fn delete(this: *Self, entity: EntityID) !void {
        try this._removeEntry(this, entity);
    }

    /// sync all added and removed data from temp storage to real
    /// this is called usually after each frame (after all before, update, after, ui steps).
    /// after this operation `addedData`, `addedEntityIDRow` and `removedEntities` will be empty
    pub fn sync(this: *Self) !void {
        try this._sync(this);
    }
};

test "ArchetypeStorage init" {
    var sut = try ArchetypeStorage.init(t.allocator, .{}); //void archetype

    try t.expectEqual(@as(usize, 0), sut.addedData.count());
    try t.expectEqual(@as(usize, 0), sut.data.count());
    try t.expectEqual(@as(usize, 0), sut.removedEntities.count());
    try t.expectEqual(@as(usize, 0), sut.entityIDRow.items.len);
    try t.expectEqual(@as(usize, 0), sut.entityIndexMap.count());
}

test "ArchetypeStorage add to {}" {
    var voidArch = try ArchetypeStorage.init(t.allocator, .{}); //void archetype
    defer voidArch.deinit();

    const entity1: EntityID = 1;
    const entity2: EntityID = 2;

    // initially every entity is added to the void storage
    try voidArch.copy(entity1, voidArch);
    try voidArch.copy(entity2, voidArch);
    try expectEqual(entity1, voidArch.addedEntityIDRow.items[0]);
    try expectEqual(entity2, voidArch.addedEntityIDRow.items[1]);
    try expectEqual(@as(usize, 0), voidArch.entityIndexMap.count());

    // sync everything from addedData to data
    try voidArch.sync();

    try expectEqual(@as(usize, 0), voidArch.addedEntityIDRow.items.len);
    try expectEqual(entity1, voidArch.entityIDRow.items[0]);
    try expectEqual(entity2, voidArch.entityIDRow.items[1]);
    try expectEqual(@as(usize, 2), voidArch.entityIndexMap.count());
    try expectEqual(@as(usize, 0), voidArch.entityIndexMap.get(entity1).?);
    try expectEqual(@as(usize, 1), voidArch.entityIndexMap.get(entity2).?);
}

test "ArchetypeStorage move from {Position} to {} and set data" {
    var voidArch = try ArchetypeStorage.init(t.allocator, .{}); //void archetype
    var positionArch = try ArchetypeStorage.init(t.allocator, .{Position}); //position archetype
    defer voidArch.deinit();
    defer positionArch.deinit();

    const entity1: EntityID = 1;
    const entity2: EntityID = 2;

    // initially every entity is added to the void storage
    try voidArch.copy(entity1, voidArch);
    try voidArch.copy(entity2, voidArch);
    try voidArch.sync();

    try positionArch.copy(entity1, voidArch);
    try positionArch.copy(entity2, voidArch);
    try expectEqual(entity1, positionArch.addedEntityIDRow.items[0]);
    try expectEqual(entity2, positionArch.addedEntityIDRow.items[1]);

    try positionArch.sync();

    // sync everything from addedData to data
    try expectEqual(@as(usize, 0), positionArch.addedEntityIDRow.items.len);
    try expectEqual(entity1, positionArch.entityIDRow.items[0]);
    try expectEqual(entity2, positionArch.entityIDRow.items[1]);

    const p = Position{ .x = 73, .y = 123 };
    try positionArch.put(entity1, p);
    const slice = try positionArch.slice(Position);
    try expectEqual(p, slice[0]);
}

// test "ArchetypeStorage move from lower archetype to higher" {
//     var voidArch = try ArchetypeStorage.init(t.allocator, .{}); //void archetype
//     var positionArch = try ArchetypeStorage.init(t.allocator, .{Position}); //position archetype
//     var positionNameArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name }); //position & name archetype

//     try t.expectEqual(@as(usize, 0), sut.addedData.count());
//     try t.expectEqual(@as(usize, 0), sut.data.count());
//     try t.expectEqual(@as(usize, 0), sut.removedEntities.count());
//     try t.expectEqual(@as(usize, 0), sut.entityIDRow.items.len);
//     try t.expectEqual(@as(usize, 0), sut.entityIndexMap.count());
// }

///TODO: implement iterator that jumps to next archetype
// pub fn ArchetypeIterator(comptime ArchetypeTuple: type) type {
//     return struct {
//         ecs: *ECS,
//         currentHashIndex: usize,
//         currentData: ArchetypeSlices(ArchetypeTuple),
//         indexInStorage: usize,

//         pub fn next(this: *@This()) ?ArchetypePointers(ArchetypeTuple) {
//             //TODO:
//             // std.AutoHashMap(ArchetypeHash, ArchetypeStorage).valueIterator(self: *const Self)
//         }
//     };
// }

// test "query" {
//     var ecs = try ECS.init(t.allocator);
//     defer ecs.deinit();

//     // var it = ecs.query(.{ Position, Name });
// }

pub const ECS = struct {
    allocator: std.mem.Allocator,
    window: struct { size: struct { x: f32, y: f32 } = .{ .x = 100, .y = 100 } } = .{},
    systems: std.ArrayList(System),
    nextEnitityID: EntityID = 1,
    enitities: std.AutoArrayHashMap(EntityID, ArchetypeHash),
    archetypes: std.AutoArrayHashMap(ArchetypeHash, ArchetypeStorage),

    ///
    pub fn init(
        allocator: std.mem.Allocator,
    ) !@This() {
        return @This(){
            .allocator = allocator,
            .systems = std.ArrayList(System).init(allocator),
            .enitities = std.AutoArrayHashMap(EntityID, ArchetypeHash).init(allocator),
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
