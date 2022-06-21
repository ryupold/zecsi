const std = @import("std");
const meta = std.meta;
const t = std.testing;
const expect = t.expect;
const expectEqual = t.expectEqual;
const expectEqualStrings = t.expectEqualStrings;

const EntityID = @import("entity.zig").EntityID;
pub const ArchetypeHash = u64;
/// obtained with `typeID()`
const ComponentType = usize;

/// type erased archetype data column storing one type of component
const ArchetypeColumn = struct {
    typ: ComponentType,
    allocator: std.mem.Allocator,
    column: *anyopaque,
    len: usize = 0,
    _append: fn (this: *@This()) std.mem.Allocator.Error!usize,
    _copyFrom: fn (this: *@This(), from: @This(), fromIndex: usize) std.mem.Allocator.Error!usize,
    _remove: fn (this: *@This(), index: usize) void,
    _deinit: fn (this: *@This()) void,

    pub fn init(allocator: std.mem.Allocator, comptime TComponent: type) !@This() {
        var list = try allocator.create(std.ArrayList(TComponent));
        list.* = std.ArrayList(TComponent).init(allocator);

        return @This(){
            .typ = typeId(TComponent),
            .allocator = allocator,
            .column = @ptrCast(*anyopaque, list),
            ._append = (struct {
                fn append(column: *ArchetypeColumn) std.mem.Allocator.Error!usize {
                    var list = column.cast(TComponent) catch unreachable;
                    _ = try list.addOne();
                    column.len = list.items.len;
                    return list.items.len - 1;
                }
            }).append,
            ._copyFrom = (struct {
                fn copyFrom(column: *ArchetypeColumn, from: ArchetypeColumn, fromIndex: usize) (std.mem.Allocator.Error || error.WrongComponentType)!usize {
                    var fromList = try from.cast(TComponent);
                    try column.append(fromList.items[index]);
                    return column.len - 1;
                }
            }).copyFrom,
            ._remove = (struct {
                fn remove(column: *ArchetypeColumn, index: usize) void {
                    var list = column.cast(TComponent) catch unreachable;
                    _ = list.swapRemove(index);
                    column.len = list.items.len;
                }
            }).remove,
            ._deinit = (struct {
                fn deinit(column: *ArchetypeColumn) void {
                    var list = column.cast(TComponent) catch unreachable;
                    list.deinit();
                    column.len = 0;
                    column.allocator.destroy(list);
                }
            }).deinit,
        };
    }

    pub fn deinit(this: *@This()) void {
        this._deinit(this);
    }

    pub fn append(this: *@This(), value: anytype) !void {
        var list = try this.cast(@TypeOf(value));
        try list.append(value);
        this.len = list.len;
    }

    /// append one uninitialized entry and return index to it
    pub fn addOne(this: *@This()) !usize {
        return try this._append(this);
    }

    pub fn set(this: *@This(), value: anytype, atIndex: usize) !void {
        var list = try this.cast(@TypeOf(value));
        list.items[atIndex] = value;
    }

    pub fn getPtr(this: *@This(), comptime TComponent: type, index: usize) !*TComponent {
        var list = try this.cast(@TypeOf(value));
        return &list.items[index];
    }

    pub fn get(this: *@This(), comptime TComponent: type, index: usize) !TComponent {
        var list = try this.cast(@TypeOf(value));
        return list.items[index];
    }

    pub fn remove(this: *@This(), index: usize) void {
        this._remove(this, index);
    }

    pub fn copyFrom(this: *@This(), from: @This(), fromIndex: usize) !void {
        try this._copyFrom(this, from, fromIndex);
    }

    /// cast column pointer to arraylist pointer of T (if possible)
    fn cast(this: *@This(), comptime T: type) error.WrongComponentType!*std.ArrayList(T) {
        if (typeId(T) != this.typ) return error.WrongComponentType;
        return @ptrCast(*std.ArrayList(T), @alignCast(@alignOf(*std.ArrayList(T)), this.column));
    }
};

pub const ArchetypeStorage = struct {
    allocator: std.mem.Allocator,
    hash: ArchetypeHash = archetypeHash(.{}),

    entityIndexMap: std.AutoArrayHashMap(EntityID, usize),
    entityIDRow: std.ArrayList(EntityID),
    addedEntityIDRow: std.ArrayList(EntityID),
    removedEntities: std.AutoArrayHashMap(EntityID, void),

    data: std.AutoArrayHashMap(ComponentType, ArchetypeColumn),
    addedData: std.AutoArrayHashMap(ComponentType, ArchetypeColumn),

    // _addEntry: fn (this: *@This(), entity: EntityID, previousStorage: ArchetypeStorage) anyerror!void,
    // _removeEntry: fn (this: *@This(), entity: EntityID) anyerror!void,
    // _sync: fn (this: *@This()) anyerror!void,
    // _deinit: fn (this: *@This()) void,

    pub fn init(
        allocator: std.mem.Allocator,
        // , comptime arch: anytype
    ) !@This() {
        // const hash = archetypeHash(arch);
        var data = std.AutoArrayHashMap(ComponentType, ArchetypeColumn).init(allocator);
        var addedData = std.AutoArrayHashMap(ComponentType, ArchetypeColumn).init(allocator);
        var removedEntities = std.AutoArrayHashMap(EntityID, void).init(allocator);

        // inline for (arch) |T| {
        //     var list = try allocator.create(std.ArrayList(T));
        //     list.* = std.ArrayList(T).init(allocator);
        //     try data.put(typeId(T), @ptrCast(*anyopaque, list));

        //     var addedList = try allocator.create(std.ArrayList(T));
        //     addedList.* = std.ArrayList(T).init(allocator);
        //     try addedData.put(typeId(T), @ptrCast(*anyopaque, addedList));
        // }

        return @This(){
            .allocator = allocator,
            // .hash = hash,
            .data = data,
            .addedData = addedData,
            .entityIndexMap = std.AutoArrayHashMap(EntityID, usize).init(allocator),
            .entityIDRow = std.ArrayList(EntityID).init(allocator),
            .addedEntityIDRow = std.ArrayList(EntityID).init(allocator),
            .removedEntities = removedEntities,

            // ._addEntry = if (arch.len == 0) (struct {
            //     pub fn addToVoid(this: *ArchetypeStorage, entity: EntityID, previousStorage: ArchetypeStorage) !void {
            //         //find index of entity in previous archetype
            //         var index = previousStorage.entityIndexMap.get(entity);
            //         // if it was added in this frame, it is held in the addedData container of previousStorage
            //         const isVolatile = index == null;
            //         if (isVolatile) {
            //             for (previousStorage.addedEntityIDRow.items) |aE, i| {
            //                 if (aE == entity) {
            //                     index = i;
            //                     break;
            //                 }
            //             }
            //         }
            //         if (index != null) return;

            //         // add entity to added list
            //         try this.addedEntityIDRow.append(entity);
            //     }
            // }).addToVoid else (struct {
            //     pub fn addEntry(this: *ArchetypeStorage, entity: EntityID, previousStorage: ArchetypeStorage) !void {
            //         //do nothing if it's the same storage
            //         if (this.hash == previousStorage.hash) return;

            //         //find index of entity in previous archetype
            //         var index = previousStorage.entityIndexMap.get(entity);
            //         // if it was added in this frame, it is held in the addedData container of previousStorage
            //         const isVolatile = index == null;
            //         if (isVolatile) {
            //             for (previousStorage.addedEntityIDRow.items) |aE, i| {
            //                 if (aE == entity) {
            //                     index = i;
            //                     break;
            //                 }
            //             }
            //         }
            //         if (index == null) return error.EntityNotFound;

            //         //find correct storage
            //         var dataStorage = if (isVolatile)
            //             previousStorage.addedData
            //         else
            //             previousStorage.data;

            //         //for each component type
            //         inline for (arch) |T| {
            //             // if previos archetype contained this component
            //             var listPtr = this.addedData.get(typeId(T)).?;
            //             var list = castColumn(T, listPtr);
            //             if (dataStorage.get(typeId(T))) |previousListPtr| {
            //                 var previousList = castColumn(T, previousListPtr);
            //                 // add component to added list
            //                 try list.append(previousList.items[index.?]);
            //             } else {
            //                 //this case only occurs if we are stepping up to a greater archetype
            //                 //add entry to component list which previousStorage hadn't
            //                 _ = try list.addOne(); // component data needs to be set via `put`
            //             }
            //         }
            //         // add entity to added list
            //         try this.addedEntityIDRow.append(entity);
            //     }
            // }).addEntry,
            // ._removeEntry = (struct {
            //     pub fn removeEntry(this: *ArchetypeStorage, entity: EntityID) !void {
            //         //is entity in "persistent" storage?
            //         var index = this.entityIndexMap.get(entity);
            //         const isVolatile = index == null;

            //         // is entity in temp storage?
            //         if (index == null) {
            //             for (this.addedEntityIDRow.items) |aE, i| {
            //                 if (aE == entity) {
            //                     index = i;
            //                     break;
            //                 }
            //             }
            //         }
            //         if (index == null) return error.EntityNotFound;

            //         //if the storage contains the entity to remove in the temp data
            //         if (isVolatile) {
            //             //delete the entry before it gets synced
            //             inline for (arch) |T| {
            //                 var listPtr = this.addedData.get(typeId(T)).?;
            //                 var list = castColumn(T, listPtr);
            //                 _ = list.swapRemove(index.?);
            //             }
            //             _ = this.addedEntityIDRow.swapRemove(index.?);
            //         } else {
            //             //otherwise add to removed list
            //             try this.removedEntities.put(entity, {});
            //         }
            //     }
            // }).removeEntry,
            // ._sync = (struct {
            //     pub fn sync(this: *ArchetypeStorage) !void {
            //         //add
            //         inline for (arch) |T| {
            //             var addedListPtr = this.addedData.get(typeId(T)).?;
            //             var addedList = castColumn(T, addedListPtr);

            //             var listPtr = this.data.get(typeId(T)).?;
            //             var list = castColumn(T, listPtr);

            //             try list.appendSlice(addedList.items);
            //             addedList.clearAndFree();
            //         }
            //         for (this.addedEntityIDRow.items) |aE| {
            //             const index = this.entityIDRow.items.len;
            //             try this.entityIDRow.append(aE);
            //             try this.entityIndexMap.put(aE, index);
            //         }
            //         this.addedEntityIDRow.clearAndFree();

            //         //remove
            //         for (this.removedEntities.keys()) |removed| {
            //             if (this.entityIndexMap.get(removed)) |index| {
            //                 inline for (arch) |T| {
            //                     var listPtr = this.data.get(typeId(T)).?;
            //                     var list = castColumn(T, listPtr);

            //                     _ = list.swapRemove(index);
            //                 }
            //                 _ = this.entityIDRow.swapRemove(index);
            //                 if (this.entityIDRow.items.len > 0 and index < this.entityIDRow.items.len - 1) {
            //                     const swappedEntity = this.entityIDRow.items[index];
            //                     try this.entityIndexMap.put(swappedEntity, index);
            //                 }
            //             }
            //             _ = this.entityIndexMap.swapRemove(removed);
            //         }
            //         this.removedEntities.clearAndFree();
            //     }
            // }).sync,
            // ._deinit = (struct {
            //     pub fn deinit(this: *ArchetypeStorage) void {
            //         inline for (arch) |T| {
            //             var listPtr = this.data.get(typeId(T)).?;
            //             var list = castColumn(T, listPtr);
            //             list.deinit();
            //             this.allocator.destroy(list);

            //             var addedListPtr = this.addedData.get(typeId(T)).?;
            //             var addedList = castColumn(T, addedListPtr);
            //             addedList.deinit();
            //             this.allocator.destroy(addedList);
            //         }
            //     }
            // }).deinit,
        };
    }

    /// add a column to a newly created ArchetypeStorage
    pub fn addColumn(this: *@This(), comptime TComponent: type) error{ OutOfMemory, AlreadyContainsComponentType, StorageAlreadyContainsData }!void {
        if (this.has(TComponent)) return error.AlreadyContainsComponentType;
        if (this.entityIDRow.items.len > 0 or this.addedEntityIDRow.items.len > 0) return error.StorageAlreadyContainsData;

        var column = try ArchetypeColumn.init(this.allocator, TComponent);
        try this.data.put(typeID(TComponent), column);
    }

    pub fn deinit(this: *@This()) void {
        // this._deinit(this);

        for (this.data.values()) |*column| {
            column.deinit();
        }
        for (this.addedData.values()) |*column| {
            column.deinit();
        }

        this.entityIndexMap.deinit();
        this.entityIDRow.deinit();
        this.data.deinit();
        this.addedData.deinit();
        this.addedEntityIDRow.deinit();
        this.removedEntities.deinit();
    }

    // /// cast pointer to Component column
    // fn castColumn(comptime T: type, ptr: *anyopaque) *std.ArrayList(T) {
    //     return @ptrCast(*std.ArrayList(T), @alignCast(@alignOf(*std.ArrayList(T)), ptr));
    // }

    /// put component data for specified entity
    /// ```
    /// const e: EntityID = 312; //assuming this entity exists in this ArchetypeStorage
    /// const p = Position{.x = 5, .y=0.7};
    /// try put(e, .{p});
    /// ```
    pub fn put(this: *@This(), entity: EntityID, componentData: anytype) !void {
        const T = @TypeOf(componentData);
        // entity is already synced
        if (this.entityIndexMap.get(entity)) |index| {
            if (this.data.getPtr(typeId(T))) |column| {
                try column.set(componentData, index);
                return;
            } else {
                return error.ComponentNotPartOfArchetype;
            }
        }
        // entity is newly added to this storage
        else {
            for (this.addedEntityIDRow.items) |aE, index| {
                if (aE == entity) {
                    if (this.addedData.getPtr(typeId(T))) |addedColumn| {
                        addedColumn.set(componentData, index);
                        return;
                    } else {
                        return error.ComponentNotPartOfArchetype;
                    }
                }
            }
        }
        // entity is not part of this storage
        return error.EntityNotFound;
    }

    /// return all entities `sync`ed with this archetype
    pub fn entities(this: @This()) []EntityID {
        return this.entityIDRow.items;
    }

    /// get reference to component data
    /// can become invalid after `sync`
    pub fn getPtr(this: @This(), entity: EntityID, comptime T: type) error{ ComponentNotPartOfArchetype, EntityNotFound }!*T {
        if (this.data.getPtr(typeId(T))) |columnPtr| {
            // entity is already synced
            if (this.entityIndexMap.get(entity)) |index| {
                return columnPtr.getPtr(T, index);
            }
            // entity is newly added to this storage
            else {
                for (this.addedEntityIDRow.items) |aE, index| {
                    if (aE == entity) {
                        var addedColumnPtr = this.addedData.getPtr(typeId(T)).?;
                        return addedColumnPtr.getPtr(T, index);
                    }
                }
            }
            // entity is not part of this storage
            return error.EntityNotFound;
        }
        return error.ComponentNotPartOfArchetype;
    }

    /// get component data
    pub fn get(this: @This(), entity: EntityID, comptime T: type) error{ ComponentNotPartOfArchetype, EntityNotFound }!T {
        const ref = try this.getPtr(entity, T);
        return ref.*;
    }

    /// true if `this` archetype has `T` components
    pub fn has(this: *@This(), comptime T: type) bool {
        return this.data.contains(typeId(T));
    }

    /// true if `this` archetype contains `entity` (must be synced)
    pub fn hasEntity(this: *@This(), entity: EntityID) bool {
        return this.entityIndexMap.contains(entity);
    }

    /// return direct data access to the `TComponent` column
    /// this is a guaranteed valid reference until the next call to `sync`
    pub fn slice(this: *@This(), comptime TComponent: type) error{ComponentNotPartOfArchetype}![]TComponent {
        if (this.data.get(typeId(TComponent))) |columnPtr| {
            var column = columnPtr.cast(TComponent) catch unreachable;
            return column.items;
        }
        return error.ComponentNotPartOfArchetype;
    }

    /// copy entity to this ArchetypeStorage with data of previous storage
    /// this won't make the entity (data) available directly but a call to `sync` is necessary to
    /// make the change permanent. This happens usually at the end of the frame (after all before, update, after, ui steps).
    /// this is a readonly operation on the previous ArchetypeStorage, it will keep its values.
    /// call `delete` on the previous storage afterwards
    pub fn copy(this: *@This(), entity: EntityID, fromStorage: ArchetypeStorage) !void {
        // _ = try this._addEntry(this, entity, fromStorage);
        //TODO ...
    }

    /// mark an entity as deleted in this storage.
    /// this will take effect after a call to `sync`
    pub fn delete(this: *@This(), entity: EntityID) !void {
        try this._removeEntry(this, entity);
    }

    /// sync all added and removed data from temp storage to real
    /// this is called usually after each frame (after all before, update, after, ui steps).
    /// after this operation `addedData`, `addedEntityIDRow` and `removedEntities` will be empty
    pub fn sync(this: *@This()) !void {
        try this._sync(this);
    }

    /// get number of `sync`ed entities in this storage
    pub fn count(this: @This()) usize {
        return this.entityIndexMap.count();
    }

    /// get a struct with a slice for all entities and each component type.
    /// each `ArchetypeSlices.get` call reveals a struct with
    /// pointers to the component data of the entity at that specific index.
    /// it can be used with just a subset of all available components in this storage.
    ///
    /// the slices are valid until the next call to `sync`
    ///
    /// example:
    /// ```
    /// var slices = try storage.query(.{.{"position", Position}, .{"name", Name}});
    /// for(slices.data.entities) |entity, index| {
    ///     _ = entity;               // EntityID
    ///     _ = slices.data.position; // []Position
    ///     _ = slices.data.name;     // []Name
    ///
    ///     var entry = slices.get(index) catch unreachable;
    ///     _ = entry.entity;   // EntityID
    ///     _ = entry.position; // *Position
    ///     _ = entry.name;     // *Name
    /// }
    ///
    /// ```
    pub fn query(this: *@This(), comptime arch: anytype) error{ComponentNotPartOfArchetype}!ArchetypeSlices(arch) {
        var slices: ArchetypeSlices(arch) = undefined;
        slices.data.entities = this.entities();

        inline for (arch) |lT| {
            @field(slices.data, lT[0]) = try this.slice(lT[1]);
        }
        return slices;
    }
};

test "ArchetypeStorage init" {
    var sut = try ArchetypeStorage.init(t.allocator, .{ Position, Name }); //void archetype
    defer sut.deinit();

    try t.expectEqual(@as(usize, 2), sut.data.keys().len);
    try t.expectEqual(@as(usize, 2), sut.addedData.keys().len);
    try t.expectEqual(@as(usize, 0), sut.removedEntities.count());
    try t.expectEqual(@as(usize, 0), sut.entityIDRow.items.len);
    try t.expectEqual(@as(usize, 0), sut.entityIndexMap.count());
}

test "ArchetypeStorage extend" {
    // var voidArch = try ArchetypeStorage.init(t.allocator, .{}); //void archetype
    // defer voidArch.deinit();
    // var positionNameArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name }); //void archetype
    // defer positionNameArch.deinit();

    // const entity1: EntityID = 1;
    // const entity2: EntityID = 2;
    // try voidArch.copy(entity1, voidArch);
    // try voidArch.copy(entity2, voidArch);

    // try positionNameArch.copy(entity1, voidArch);
    // try positionNameArch.put(entity1, Position{ .x = 1, .y = 2 });
    // try positionNameArch.put(entity1, Name{ .name = "foo" });
    // try positionNameArch.copy(entity2, voidArch);
    // try positionNameArch.put(entity2, Position{ .x = 2, .y = 4 });
    // try positionNameArch.put(entity2, Name{ .name = "bar" });

    // var extension = try sut.extend(.{Target});
    // defer extension.deinit();

    // try extension.copy(entity1, positionNameArch);
    // try extension.put(entity1, Target{ .x = 5, .y = 10 });
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

    // sync steps puts moves components from `addedData` to `data`
    try voidArch.sync();

    // it should also work without a call to sync
    // then the components in `addedData` are used
    try voidArch.copy(entity2, voidArch);

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

test "ArchetypeStorage has" {
    var voidArch = try ArchetypeStorage.init(t.allocator, .{});
    defer voidArch.deinit();
    var positionNameArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name });
    defer positionNameArch.deinit();

    try expect(voidArch.has(Position) == false);
    try expect(voidArch.has(Name) == false);

    try expect(positionNameArch.has(Position));
    try expect(positionNameArch.has(Name));
    try expect(positionNameArch.has(Target) == false);
}

test "ArchetypeStorage put, get, getPtr, slice" {
    var voidArch = try ArchetypeStorage.init(t.allocator, .{});
    defer voidArch.deinit();
    var positionNameArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name });
    defer positionNameArch.deinit();

    const entity1: EntityID = 1;
    try voidArch.copy(entity1, voidArch);
    try voidArch.sync();

    try positionNameArch.copy(entity1, voidArch);

    //put
    const p = Position{ .x = 123, .y = 567 };
    try positionNameArch.put(entity1, p); // works for newly added ...

    try positionNameArch.sync();

    const n = Name{ .name = "lorizzle ma nizzle" };
    try positionNameArch.put(entity1, n); // ... and already synced entities

    //get
    try expectEqual(p, try positionNameArch.get(entity1, Position));
    try expectEqual(n, try positionNameArch.get(entity1, Name));
    try t.expectError(error.EntityNotFound, positionNameArch.get(1337, Position));
    try t.expectError(error.ComponentNotPartOfArchetype, positionNameArch.get(entity1, Target));

    //getPtr
    try expectEqual(p, (try positionNameArch.getPtr(entity1, Position)).*);
    try expectEqual(n, (try positionNameArch.getPtr(entity1, Name)).*);
    try t.expectError(error.EntityNotFound, positionNameArch.getPtr(1337, Position));
    try t.expectError(error.ComponentNotPartOfArchetype, positionNameArch.getPtr(entity1, Target));

    //slice
    try t.expectEqualSlices(Position, &.{p}, try positionNameArch.slice(Position));
    try t.expectEqualSlices(Name, &.{n}, try positionNameArch.slice(Name));
    try t.expectError(error.ComponentNotPartOfArchetype, positionNameArch.slice(Target));
}

test "ArchetypeStorage move data from lower to higher and from higher to lower" {
    var voidArch = try ArchetypeStorage.init(t.allocator, .{});
    defer voidArch.deinit();
    var positionNameArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name });
    defer positionNameArch.deinit();
    var positionNameTargetArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name, Target });
    defer positionNameTargetArch.deinit();

    const entity1: EntityID = 1;
    try voidArch.copy(entity1, voidArch);
    try voidArch.sync();

    // move to {Position,Name,Target} archetype
    try positionNameTargetArch.copy(entity1, voidArch);
    try positionNameTargetArch.sync();

    //put
    const p = Position{ .x = 123, .y = 567 };
    try positionNameTargetArch.put(entity1, p);
    const n = Name{ .name = "lorizzle ma nizzle" };
    try positionNameTargetArch.put(entity1, n);
    const target = Target{ .x = 0, .y = 5 };
    try positionNameTargetArch.put(entity1, target);

    try expectEqual(p, try positionNameTargetArch.get(entity1, Position));
    try expectEqual(n, try positionNameTargetArch.get(entity1, Name));
    try expectEqual(target, try positionNameTargetArch.get(entity1, Target));

    // move to {Position,Name} archetype
    try positionNameArch.copy(entity1, positionNameTargetArch);
    try positionNameArch.sync();

    try expectEqual(p, try positionNameArch.get(entity1, Position));
    try expectEqual(n, try positionNameArch.get(entity1, Name));
    try t.expectError(error.ComponentNotPartOfArchetype, positionNameArch.get(entity1, Target));
}

test "ArchetypeStorage count, delete and hasEntity" {
    var voidArch = try ArchetypeStorage.init(t.allocator, .{});
    defer voidArch.deinit();
    var positionNameArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name });
    defer positionNameArch.deinit();
    var positionNameTargetArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name, Target });
    defer positionNameTargetArch.deinit();

    const entity1: EntityID = 1;
    try expectEqual(@as(usize, 0), voidArch.count());
    try voidArch.copy(entity1, voidArch);
    try expectEqual(@as(usize, 0), voidArch.count());
    try voidArch.sync();
    try expectEqual(@as(usize, 1), voidArch.count());

    // move to {Position,Name,Target} archetype
    try positionNameTargetArch.copy(entity1, voidArch);
    try expect(positionNameTargetArch.hasEntity(entity1) == false);
    try positionNameTargetArch.sync();
    try expect(positionNameTargetArch.hasEntity(entity1)); //only available after sync

    try expectEqual(true, voidArch.hasEntity(entity1));
    try voidArch.delete(entity1);
    try expectEqual(true, voidArch.hasEntity(entity1));
    try voidArch.sync();
    try expectEqual(false, voidArch.hasEntity(entity1)); //only removed after sync
}

test "ArchetypeStorage query (ArchetypeSlices)" {
    var voidArch = try ArchetypeStorage.init(t.allocator, .{});
    defer voidArch.deinit();
    var testArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name, Target });
    defer testArch.deinit();

    // add 4 entities
    const entities = [_]EntityID{ 1, 2, 3, 4 };
    for (entities) |entity| {
        try voidArch.copy(entity, voidArch);
    }
    try voidArch.sync();

    // move to {Position,Name,Target} archetype
    for (voidArch.entities()) |entity, i| {
        try testArch.copy(entity, voidArch);

        //put data (works before and after sync)
        const p = Position{ .x = @intToFloat(f32, i), .y = @intToFloat(f32, i) * 2 };
        try testArch.put(entity, p);
        const n = Name{ .name = "lorizzle" };
        try testArch.put(entity, n);
        const target = Target{ .x = @intToFloat(f32, i) * 3, .y = @intToFloat(f32, i) * 4 };
        try testArch.put(entity, target);
    }
    try testArch.sync();

    var allComponents = try testArch.query(.{
        .{ "position", Position },
        .{ "name", Name },
        .{ "target", Target },
    });
    try expectEqual(allComponents.data.entities.len, 4);
    try expectEqual(allComponents.data.position.len, 4);
    try expectEqual(allComponents.data.name.len, 4);
    try expectEqual(allComponents.data.target.len, 4);
    try expectEqual(Position{ .x = 1, .y = 2 }, allComponents.data.position[1]);
    try expectEqual(Name{ .name = "lorizzle" }, allComponents.data.name[1]);
    try expectEqual(Target{ .x = 3, .y = 4 }, allComponents.data.target[1]);

    //direct access to the memory
    allComponents.data.position[1] = .{ .x = 111, .y = 222 };

    // query subset of components
    var positions = try testArch.query(.{.{ "position", Position }});
    try expectEqual(Position{ .x = 111, .y = 222 }, positions.data.position[1]);

    // query component that is not present in archetype
    try t.expectError(error.ComponentNotPartOfArchetype, testArch.query(.{
        .{ "position", Position },
        .{ "dunno", Dunno },
    }));
}

test "ArchetypeStorage query (ArchetypeEntry)" {
    var voidArch = try ArchetypeStorage.init(t.allocator, .{});
    defer voidArch.deinit();
    var testArch = try ArchetypeStorage.init(t.allocator, .{ Position, Name, Target });
    defer testArch.deinit();

    // add 4 entities
    const entities = [_]EntityID{ 1, 2, 3, 4 };
    for (entities) |entity| {
        try voidArch.copy(entity, voidArch);
    }
    try voidArch.sync();

    // move to {Position,Name,Target} archetype
    for (voidArch.entities()) |entity, i| {
        try testArch.copy(entity, voidArch);

        //put data (works before and after sync)
        const p = Position{ .x = @intToFloat(f32, i), .y = @intToFloat(f32, i) * 2 };
        try testArch.put(entity, p);
        const n = Name{ .name = "lorizzle" };
        try testArch.put(entity, n);
        const target = Target{ .x = @intToFloat(f32, i) * 3, .y = @intToFloat(f32, i) * 4 };
        try testArch.put(entity, target);
    }
    try testArch.sync();

    var allComponents = try testArch.query(.{
        .{ "pos", Position },
        .{ "name", Name },
        .{ "target", Target },
    });
    const entry0 = allComponents.get(0).?;
    const entry1 = allComponents.get(1).?;
    const entry2 = allComponents.get(2).?;
    const entry3 = allComponents.get(3).?;

    try expectEqual(Position{ .x = 0, .y = 0 }, entry0.pos.*);

    try expectEqual(Position{ .x = 1, .y = 2 }, entry1.pos.*);
    try expectEqual(Name{ .name = "lorizzle" }, entry1.name.*);
    try expectEqual(Target{ .x = 3, .y = 4 }, entry1.target.*);

    try expectEqual(Position{ .x = 2, .y = 4 }, entry2.pos.*);
    try expectEqual(Name{ .name = "lorizzle" }, entry2.name.*);
    try expectEqual(Target{ .x = 6, .y = 8 }, entry2.target.*);

    try expectEqual(Position{ .x = 3, .y = 6 }, entry3.pos.*);
    try expectEqual(Name{ .name = "lorizzle" }, entry3.name.*);
    try expectEqual(Target{ .x = 9, .y = 12 }, entry3.target.*);

    try t.expect(allComponents.get(4) == null);
}

/// get usize id for a given type (magic)
/// typeId implementation by Felix "xq" Queißner
/// from: https://zig.news/xq/cool-zig-patterns-type-identifier-3mfd
pub fn typeId(comptime T: type) ComponentType {
    _ = T;
    const H = struct {
        var byte: u8 = 0;
    };
    return @ptrToInt(&H.byte);
}

pub fn archetypeHash(comptime arch: anytype) ArchetypeHash {
    const ty = @TypeOf(arch);
    const tyInfo = @typeInfo(ty);
    comptime if (!meta.trait.isTuple(ty)) {
        compError("expected tuple of types but got {?}", .{arch});
    };

    if (arch.len == 0) {
        return std.math.maxInt(u64);
    }

    inline for (tyInfo.Struct.fields) |field| {
        if (@TypeOf(field.field_type) != type) {
            compError("expected tuple of types but got {?}", .{arch});
        }
    }

    var hash: ArchetypeHash = 0;
    inline for (arch) |T| {
        const bytes = std.mem.toBytes(typeId(T));
        hash ^= std.hash.Wyhash.hash(0, &bytes);
    }

    return hash;
}

pub fn combineArchetypeHash(hash: ArchetypeHash, comptime arch: anytype) ArchetypeHash {
    if (arch.len == 0) return hash;

    var newHash: ArchetypeHash = hash;
    inline for (arch) |T| {
        const bytes = std.mem.toBytes(typeId(T));
        newHash ^= std.hash.Wyhash.hash(0, &bytes);
    }

    return newHash;
}

test "archetypeHash" {
    // void storage has ID std.math.maxInt(u64)
    try expectEqual(
        @as(ArchetypeHash, std.math.maxInt(u64)),
        archetypeHash(.{}),
    );

    try expect(archetypeHash(.{Position}) != archetypeHash(.{}));
    try expect(archetypeHash(.{Position}) != archetypeHash(.{ Target, Position }));

    //same
    try expectEqual(
        archetypeHash(.{ Target, Position }),
        archetypeHash(.{ Position, Target }),
    );
    //----

    //same
    try expectEqual(
        archetypeHash(.{ Position, Target, Name }),
        archetypeHash(.{ Target, Position, Name }),
    );
    try expectEqual(
        archetypeHash(.{ Name, Target, Position }),
        archetypeHash(.{ Position, Target, Name }),
    );
    try expectEqual(
        archetypeHash(.{ Target, Position, Name }),
        archetypeHash(.{ Name, Target, Position }),
    );
    //----
}

test "combineArchetypeHash" {
    try expectEqual(
        @as(ArchetypeHash, std.math.maxInt(u64)),
        combineArchetypeHash(std.math.maxInt(u64), .{}),
    );

    try expectEqual(
        archetypeHash(.{Position}),
        combineArchetypeHash(archetypeHash(.{Position}), .{}),
    );

    try expectEqual(
        archetypeHash(.{ Position, Target }),
        combineArchetypeHash(archetypeHash(.{Position}), .{Target}),
    );

    try expectEqual(
        archetypeHash(.{ Position, Target, Name }),
        combineArchetypeHash(archetypeHash(.{ Position, Name }), .{Target}),
    );
    try expectEqual(
        archetypeHash(.{ Position, Target, Name }),
        combineArchetypeHash(archetypeHash(.{ Target, Name }), .{Position}),
    );
    try expectEqual(
        archetypeHash(.{ Position, Target, Name }),
        combineArchetypeHash(archetypeHash(.{ Target, Position }), .{Name}),
    );
    try expectEqual(
        archetypeHash(.{ Position, Target, Name }),
        combineArchetypeHash(archetypeHash(.{Name}), .{ Target, Position }),
    );
}

pub fn ArchetypeEntry(comptime arch: anytype) type {
    @setEvalBranchQuota(10_000);
    const ty = @TypeOf(arch);
    const tyInfo = @typeInfo(ty);
    comptime if (!meta.trait.isTuple(ty)) {
        compError("expected tuple of tuples of {{[]const u8, type}} but got {?}", .{arch});
    };

    inline for (tyInfo.Struct.fields) |field, i| {
        comptime if (!meta.trait.isTuple(field.field_type)) {
            compError("expected tuple of tuples of {{[]const u8, type}} but got {?}", .{arch});
        };
        comptime if (arch[i].len != 2 or @TypeOf(arch[i][1]) != type) {
            compError("expected tuple of tuples of {{[]const u8, type}} but got {?}", .{arch});
        };
    }

    var structFields: [arch.len + 1]std.builtin.TypeInfo.StructField = undefined;
    structFields[0] = .{
        .name = "entity",
        .field_type = EntityID,
        .default_value = null,
        .is_comptime = false,
        .alignment = @alignOf(EntityID),
    };
    inline for (arch) |lT, i| {
        @setEvalBranchQuota(10_000);
        structFields[i + 1] = .{
            .name = lT[0],
            .field_type = *lT[1],
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(lT[1]) > 0) @alignOf(lT[1]) else 0,
        };
    }

    return @Type(.{
        .Struct = .{
            .is_tuple = false,
            .layout = .Auto,
            .decls = &.{},
            .fields = &structFields,
        },
    });
}

/// Return struct in which all data for an archetype `query` can fit
///
/// ```
/// const Slices = ArchetypeSlices(.{.{"position", Position}, .{"name", Name}});
/// // would be equvalent to:
/// struct{
///     data: struct {
///       entities: []EntityID,
///       position: []Position,
///       name: []Name,
///   }
/// }
/// ```
pub fn ArchetypeSlices(comptime arch: anytype) type {
    @setEvalBranchQuota(10_000);
    const ty = @TypeOf(arch);
    const tyInfo = @typeInfo(ty);
    comptime if (!meta.trait.isTuple(ty)) {
        compError("expected tuple of tuples of {{[]const u8, type}} but got {?}", .{arch});
    };

    inline for (tyInfo.Struct.fields) |field, i| {
        comptime if (!meta.trait.isTuple(field.field_type)) {
            compError("expected tuple of tuples of {{[]const u8, type}} but got {?}", .{arch});
        };
        comptime if (arch[i].len != 2 or @TypeOf(arch[i][1]) != type) {
            compError("expected tuple of tuples of {{[]const u8, type}} but got {?}", .{arch});
        };
    }

    var structFields: [arch.len + 1]std.builtin.TypeInfo.StructField = undefined;
    structFields[0] = .{
        .name = "entities",
        .field_type = []EntityID,
        .default_value = null,
        .is_comptime = false,
        .alignment = @alignOf([]EntityID),
    };

    inline for (arch) |lT, i| {
        structFields[i + 1] = .{
            .name = lT[0],
            .field_type = []lT[1],
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(lT[1]) > 0) @alignOf(lT[1]) else 0,
        };
    }

    const fields = structFields[0..];

    return struct {
        data: @Type(.{
            .Struct = .{
                .is_tuple = false,
                .layout = .Auto,
                .decls = &.{},
                .fields = fields,
            },
        }),

        pub fn get(this: *@This(), index: usize) ?ArchetypeEntry(arch) {
            if (index >= this.data.entities.len) return null;

            var entry: ArchetypeEntry(arch) = undefined;

            entry.entity = this.data.entities[index];
            inline for (arch) |lT| {
                @field(entry, lT[0]) = &@field(this.data, lT[0])[index];
            }

            return entry;
        }

        pub fn count(this: @This()) usize {
            return this.data.entities.len;
        }
    };
}

inline fn compError(comptime fmt: []const u8, args: anytype) noreturn {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

//=== components used in unit tests ==================
const Position = struct { x: f32, y: f32 };
const Target = struct { x: f32, y: f32 };
const Name = struct { name: []const u8 };
const Dunno = struct { label: []const u8, wtf: i32 };
//====================================================
