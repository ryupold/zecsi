const std = @import("std");
const meta = std.meta;
const t = std.testing;
const expect = t.expect;
const expectEqual = t.expectEqual;
const expectEqualStrings = t.expectEqualStrings;

const EntityID = @import("entity.zig").EntityID;
pub const ArchetypeHash = u64;
/// obtained with `typeId()`
const ComponentType = usize;

/// type erased archetype data column storing one type of component
const ArchetypeColumn = struct {
    typ: ComponentType,
    allocator: std.mem.Allocator,
    column: *anyopaque,
    len: usize = 0,
    _append: *const fn (this: *@This()) std.mem.Allocator.Error!usize,
    _copyFrom: *const fn (this: *@This(), from: *@This(), fromIndex: usize) (std.mem.Allocator.Error || error{WrongComponentType})!usize,
    _remove: *const fn (this: *@This(), index: usize) void,
    _clear: *const fn (this: *@This()) void,
    _addToOtherStorage: *const fn (storage: *ArchetypeStorage) anyerror!void,
    _deinit: *const fn (this: *@This()) void,

    /// create a column for components of type `TComponent`
    pub fn init(allocator: std.mem.Allocator, comptime TComponent: type) !@This() {
        var columnPtr = try allocator.create(std.ArrayList(TComponent));
        columnPtr.* = std.ArrayList(TComponent).init(allocator);

        return @This(){
            .typ = typeId(TComponent),
            .allocator = allocator,
            .column = @ptrCast(*anyopaque, columnPtr),
            ._append = &(struct {
                fn append(column: *ArchetypeColumn) std.mem.Allocator.Error!usize {
                    var list = column.cast(TComponent) catch unreachable;
                    _ = try list.addOne();
                    column.len = list.items.len;
                    return list.items.len - 1;
                }
            }).append,
            ._copyFrom = &(struct {
                fn copyFrom(column: *ArchetypeColumn, from: *ArchetypeColumn, fromIndex: usize) (std.mem.Allocator.Error || error{WrongComponentType})!usize {
                    var fromList = try from.cast(TComponent);
                    try column.append(fromList.items[fromIndex]);
                    return column.len - 1;
                }
            }).copyFrom,
            ._remove = &(struct {
                fn remove(column: *ArchetypeColumn, index: usize) void {
                    var list = column.cast(TComponent) catch unreachable;
                    _ = list.swapRemove(index);
                    column.len = list.items.len;
                }
            }).remove,
            ._clear = &(struct {
                fn clear(column: *ArchetypeColumn) void {
                    var list = column.cast(TComponent) catch unreachable;
                    list.clearAndFree();
                    column.len = 0;
                }
            }).clear,
            ._addToOtherStorage = &(struct {
                fn addToOtherStorage(storage: *ArchetypeStorage) !void {
                    try storage.addColumn(TComponent);
                }
            }).addToOtherStorage,
            ._deinit = &(struct {
                fn deinit(column: *ArchetypeColumn) void {
                    var list = column.cast(TComponent) catch unreachable;
                    list.deinit();
                    column.len = 0;
                    column.allocator.destroy(list);
                }
            }).deinit,
        };
    }

    /// free the underlying component list
    pub fn deinit(this: *@This()) void {
        this._deinit(this);
    }

    /// add new component to this column
    /// `@TypeOf(value)` must be same used in `init`
    pub fn append(this: *@This(), value: anytype) !void {
        var list = try this.cast(@TypeOf(value));
        try list.append(value);
        this.len = list.items.len;
    }

    /// append one uninitialized entry and return index to it
    pub fn addOne(this: *@This()) !usize {
        return try this._append(this);
    }

    /// set component data at `index`
    pub fn set(this: *@This(), value: anytype, atIndex: usize) !void {
        var list = try this.cast(@TypeOf(value));
        list.items[atIndex] = value;
    }

    /// get a pointer to component at `index`
    pub fn getPtr(this: *@This(), comptime TComponent: type, index: usize) !*TComponent {
        var list = try this.cast(TComponent);
        return &list.items[index];
    }

    /// get a copy of component at `index`
    pub fn get(this: *@This(), comptime TComponent: type, index: usize) !TComponent {
        var list = try this.cast(TComponent);
        return list.items[index];
    }

    /// performs a `swapRemove` on the underlying list
    pub fn remove(this: *@This(), index: usize) void {
        this._remove(this, index);
    }

    /// remove all entries in this column
    pub fn clear(this: *@This()) void {
        this._clear(this);
    }

    /// append new entry to this column by copying data `from` other column at `fromIndex`
    pub fn copyFrom(this: *@This(), from: *@This(), fromIndex: usize) !usize {
        return try this._copyFrom(this, from, fromIndex);
    }

    /// cast column pointer to arraylist pointer of `TComponent` (if possible)
    fn cast(this: *@This(), comptime TComponent: type) error{WrongComponentType}!*std.ArrayList(TComponent) {
        if (typeId(TComponent) != this.typ) return error.WrongComponentType;
        return @ptrCast(*std.ArrayList(TComponent), @alignCast(@alignOf(*std.ArrayList(TComponent)), this.column));
    }

    /// create a empty column with same type information
    fn addToOtherStorage(this: @This(), storage: *ArchetypeStorage) !void {
        return try this._addToOtherStorage(storage);
    }
};

pub const ArchetypeStorage = struct {
    allocator: std.mem.Allocator,
    hash: ArchetypeHash = archetypeHash(.{}),

    entityIndexMap: std.AutoArrayHashMap(EntityID, usize),
    entityIDs: std.ArrayList(EntityID),
    addedEntityIDs: std.ArrayList(EntityID),
    removedEntities: std.AutoArrayHashMap(EntityID, void),

    data: std.AutoArrayHashMap(ComponentType, ArchetypeColumn),
    addedData: std.AutoArrayHashMap(ComponentType, ArchetypeColumn),

    /// create a new storage without any columns
    pub fn init(allocator: std.mem.Allocator) !@This() {
        var data = std.AutoArrayHashMap(ComponentType, ArchetypeColumn).init(allocator);
        var addedData = std.AutoArrayHashMap(ComponentType, ArchetypeColumn).init(allocator);
        var removedEntities = std.AutoArrayHashMap(EntityID, void).init(allocator);

        return @This(){
            .allocator = allocator,
            .data = data,
            .addedData = addedData,
            .entityIndexMap = std.AutoArrayHashMap(EntityID, usize).init(allocator),
            .entityIDs = std.ArrayList(EntityID).init(allocator),
            .addedEntityIDs = std.ArrayList(EntityID).init(allocator),
            .removedEntities = removedEntities,
        };
    }

    /// create a new storage based on `subset`s template and `addColumn(AdditionalComponentType)`
    pub fn initExtension(allocator: std.mem.Allocator, subset: @This(), comptime AdditionalComponentType: type) !@This() {
        var extension = try init(allocator);
        for (subset.data.values()) |column| {
            try column.addToOtherStorage(&extension);
        }
        try extension.addColumn(AdditionalComponentType);
        return extension;
    }

    /// create a new storage based on `subset`s template and `addColumn(AdditionalComponentType)`
    pub fn initReduction(allocator: std.mem.Allocator, subset: @This(), comptime WithoutComponentType: type) !@This() {
        var reduction = try init(allocator);
        var iterator = subset.data.iterator();
        while (iterator.next()) |column| {
            if (typeId(WithoutComponentType) != column.key_ptr.*)
                try column.value_ptr.addToOtherStorage(&reduction);
        }
        return reduction;
    }

    /// add a column to a newly created ArchetypeStorage
    pub fn addColumn(this: *@This(), comptime TComponent: type) error{ OutOfMemory, AlreadyContainsComponentType, StorageAlreadyContainsData }!void {
        if (this.has(TComponent)) return error.AlreadyContainsComponentType;
        if (this.entityIDs.items.len > 0 or this.addedEntityIDs.items.len > 0) return error.StorageAlreadyContainsData;

        try this.data.put(
            typeId(TComponent),
            try ArchetypeColumn.init(this.allocator, TComponent),
        );
        try this.addedData.put(
            typeId(TComponent),
            try ArchetypeColumn.init(this.allocator, TComponent),
        );
        this.hash = combineArchetypeHash(this.hash, .{TComponent});
    }

    pub fn removeColumn(this: *@This(), comptime TComponent: type) void {
        if (!this.has(TComponent)) return error.DoesNotContainComponentType;
        if (this.entityIDs.items.len > 0 or this.addedEntityIDs.items.len > 0) return error.StorageAlreadyContainsData;

        try this.data.swapRemove(typeId(TComponent));
        try this.addedData.swapRemove(typeId(TComponent));
        this.hash = combineArchetypeHash(this.hash, .{TComponent});
    }

    pub fn deinit(this: *@This()) void {
        for (this.data.values()) |*column| {
            column.deinit();
        }
        for (this.addedData.values()) |*column| {
            column.deinit();
        }

        this.data.deinit();
        this.addedData.deinit();
        this.addedEntityIDs.deinit();
        this.removedEntities.deinit();
        this.entityIDs.deinit();
        this.entityIndexMap.deinit();
    }

    /// put component data for specified entity
    /// ```
    /// const e: EntityID = 312; //assuming this entity exists in this ArchetypeStorage
    /// const p = Position{.x = 5, .y=0.7};
    /// try put(e, p);
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
            for (this.addedEntityIDs.items) |aE, index| {
                if (aE == entity) {
                    if (this.addedData.getPtr(typeId(T))) |addedColumn| {
                        try addedColumn.set(componentData, index);
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
        return this.entityIDs.items;
    }

    /// get reference to component data
    /// can become invalid after `sync`
    pub fn getPtr(this: @This(), entity: EntityID, comptime T: type) !*T {
        if (this.data.getPtr(typeId(T))) |columnPtr| {
            // entity is already synced
            if (this.entityIndexMap.get(entity)) |index| {
                return try columnPtr.getPtr(T, index);
            }
            // entity is newly added to this storage
            else {
                for (this.addedEntityIDs.items) |aE, index| {
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

    /// get component data copy
    pub fn get(this: @This(), entity: EntityID, comptime T: type) !T {
        const ref = try this.getPtr(entity, T);
        return ref.*;
    }

    /// true if `this` archetype has `T` components
    pub fn has(this: @This(), comptime T: type) bool {
        return this.data.contains(typeId(T));
    }

    /// true if `this` archetype contains `entity` (must be synced)
    pub fn hasEntity(this: @This(), entity: EntityID) bool {
        return this.entityIndexMap.contains(entity);
    }

    /// return direct data access to the `TComponent` column
    /// this is a guaranteed valid reference until the next call to `sync`
    pub fn slice(this: *@This(), comptime TComponent: type) error{ComponentNotPartOfArchetype}![]TComponent {
        if (this.data.getPtr(typeId(TComponent))) |columnPtr| {
            var column = columnPtr.cast(TComponent) catch unreachable;
            return column.items;
        }
        return error.ComponentNotPartOfArchetype;
    }

    /// create a new entry for existing entity and copy all data from previous Storage
    pub fn copyFromOldArchetype(this: *@This(), entity: EntityID, oldStorage: ArchetypeStorage) !usize {
        if (this.removedEntities.contains(entity)) {
            _ = this.removedEntities.swapRemove(entity);
        } else if (this.entityIndexMap.contains(entity)) return error.AlreadyContainsEntity;

        const index = this.addedEntityIDs.items.len;

        var data: std.AutoArrayHashMap(ComponentType, ArchetypeColumn) = undefined;
        var oldIndex: usize = getIndex: {
            if (oldStorage.entityIndexMap.get(entity)) |i| {
                data = oldStorage.data;
                break :getIndex i;
            } else {
                for (oldStorage.addedEntityIDs.items) |e, i| {
                    if (e == entity) {
                        data = oldStorage.addedData;
                        break :getIndex i;
                    }
                }
                return error.EntityNotFound;
            }
        };

        try this.addedEntityIDs.append(entity);

        errdefer {
            var it = data.iterator();
            while (it.next()) |kv| {
                // append all components that this archetype supports
                if (this.addedData.getPtr(kv.key_ptr.*)) |addedColumn| {
                    if (addedColumn.len > index) {
                        addedColumn.remove(index);
                    }
                }
            }
            _ = this.addedEntityIDs.swapRemove(index);
        }

        var addedDataIterator = this.addedData.iterator();
        while (addedDataIterator.next()) |kv| {
            // old storage has this component type, then copy data
            if (data.getPtr(kv.key_ptr.*)) |oldColumn| {
                _ = try kv.value_ptr.copyFrom(oldColumn, oldIndex);
            }
            // old storage is missing this component type so just add a new entry (undefined)
            else {
                _ = try kv.value_ptr.addOne();
            }
        }

        return index;
    }

    /// add a new entity with given components (tuple) to this storage
    pub fn newEntity(this: *@This(), entity: EntityID) !usize {
        if (this.removedEntities.contains(entity)) {
            _ = this.removedEntities.swapRemove(entity);
            return this.entityIndexMap.get(entity).?;
        }
        if (this.entityIndexMap.contains(entity)) return error.AlreadyContainsEntity;

        const index = this.addedEntityIDs.items.len;
        try this.addedEntityIDs.append(entity);
        errdefer {
            for (this.addedData.values()) |*column| {
                if (column.len > index) {
                    column.remove(index);
                }
            }
            _ = this.addedEntityIDs.swapRemove(index);
        }

        for (this.addedData.values()) |*column| {
            const newIndexInAddedData = try column.addOne();
            std.debug.assert(newIndexInAddedData == index);
        }

        return index;
    }

    /// mark an entity as deleted in this storage.
    /// this will take effect after a call to `sync`
    pub fn delete(this: *@This(), entity: EntityID) !void {
        // is already synced
        if (this.entityIndexMap.contains(entity)) {
            try this.removedEntities.put(entity, {});
        }
        // otherwise it should be in addedEntityIDs
        else {
            for (this.addedEntityIDs.items) |e, i| {
                if (e == entity) {
                    for (this.addedData.values()) |*column| {
                        column.remove(i);
                    }
                    std.debug.assert(this.addedEntityIDs.swapRemove(i) == entity);
                    return;
                }
            }
            return error.EntityNotFound;
        }
    }

    /// sync all added and removed data from temp storage to real
    /// this is called usually after each frame (after all before, update, after, ui steps).
    /// after this operation `addedData`, `addedEntityIDs` and `removedEntities` will be empty
    pub fn sync(this: *@This()) !void {
        //=== add ====
        // transfer entity IDs
        for (this.addedEntityIDs.items) |aE| {
            const index = this.entityIDs.items.len;
            try this.entityIDs.append(aE);
            try this.entityIndexMap.put(aE, index);
        }
        this.addedEntityIDs.clearAndFree();

        // transfer component data
        var it = this.addedData.iterator();
        while (it.next()) |kv| {
            var column = this.data.getPtr(kv.key_ptr.*).?;
            var i: usize = 0;
            while (i < kv.value_ptr.len) : (i += 1) {
                _ = try column.copyFrom(kv.value_ptr, i);
            }
        }
        for (this.addedData.values()) |*column| {
            column.clear();
        }

        //=== remove ====
        for (this.removedEntities.keys()) |removed| {
            if (this.entityIndexMap.get(removed)) |index| {
                // remove from entityIDs
                std.debug.assert(this.entityIDs.swapRemove(index) == removed);
                if (this.entityIDs.items.len > 0 and index < this.entityIDs.items.len) {
                    const swappedEntity = this.entityIDs.items[index];
                    try this.entityIndexMap.put(swappedEntity, index);
                }

                // remove component data
                for (this.data.values()) |*column| {
                    column.remove(index);
                }
            }
            std.debug.assert(this.entityIndexMap.swapRemove(removed));
        }
        this.removedEntities.clearAndFree();
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
        if (arch.len > this.data.keys().len) return error.ComponentNotPartOfArchetype;

        var slices: ArchetypeSlices(arch) = undefined;
        inline for (arch) |lT| {
            @field(slices.data, lT[0]) = try this.slice(lT[1]);
        }

        slices.data.entities = this.entities();
        return slices;
    }
};

test "ArchetypeStorage init" {
    var sut = try ArchetypeStorage.init(t.allocator); //void archetype
    defer sut.deinit();

    try sut.addColumn(Position);
    try sut.addColumn(Name);

    try t.expectEqual(@as(usize, 2), sut.data.keys().len);
    try t.expectEqual(@as(usize, 2), sut.addedData.keys().len);
    try t.expectEqual(@as(usize, 0), sut.removedEntities.count());
    try t.expectEqual(@as(usize, 0), sut.entityIDs.items.len);
    try t.expectEqual(@as(usize, 0), sut.entityIndexMap.count());
}

test "ArchetypeStorage add to {}" {
    var voidArch = try ArchetypeStorage.init(t.allocator); //void archetype
    defer voidArch.deinit();

    const entity1: EntityID = 1;
    const entity2: EntityID = 2;

    // initially every entity is added to the void storage
    _ = try voidArch.newEntity(entity1);
    _ = try voidArch.newEntity(entity2);
    try expectEqual(entity1, voidArch.addedEntityIDs.items[0]);
    try expectEqual(entity2, voidArch.addedEntityIDs.items[1]);
    try expectEqual(@as(usize, 0), voidArch.entityIndexMap.count());

    // sync everything from addedData to data
    try voidArch.sync();

    try expectEqual(@as(usize, 0), voidArch.addedEntityIDs.items.len);
    try expectEqual(entity1, voidArch.entityIDs.items[0]);
    try expectEqual(entity2, voidArch.entityIDs.items[1]);
    try expectEqual(@as(usize, 2), voidArch.entityIndexMap.count());
    try expectEqual(@as(usize, 0), voidArch.entityIndexMap.get(entity1).?);
    try expectEqual(@as(usize, 1), voidArch.entityIndexMap.get(entity2).?);
}

test "ArchetypeStorage move from {Position} to {} and set data" {
    var voidArch = try ArchetypeStorage.init(t.allocator); //void archetype
    defer voidArch.deinit();
    var positionArch = try ArchetypeStorage.init(t.allocator); //position archetype
    defer positionArch.deinit();
    try positionArch.addColumn(Position);

    const entity1: EntityID = 1;
    const entity2: EntityID = 2;

    // initially every entity is added to the void storage
    _ = try voidArch.newEntity(entity1);

    // sync steps puts moves components from `addedData` to `data`
    try voidArch.sync();

    // it should also work without a call to sync
    // then the components in `addedData` are used
    _ = try voidArch.newEntity(entity2);
    try expectEqual(entity2, voidArch.addedEntityIDs.items[0]);

    _ = try positionArch.copyFromOldArchetype(entity1, voidArch);
    _ = try positionArch.copyFromOldArchetype(entity2, voidArch);
    try expectEqual(entity1, positionArch.addedEntityIDs.items[0]);
    try expectEqual(entity2, positionArch.addedEntityIDs.items[1]);

    try expectEqual(positionArch.addedEntityIDs.items.len, positionArch.addedData.values()[0].len);
    try positionArch.sync();
    try expectEqual(positionArch.entityIndexMap.count(), positionArch.data.values()[0].len);

    // sync everything from addedData to data
    try expectEqual(@as(usize, 0), positionArch.addedEntityIDs.items.len);
    try expectEqual(entity1, positionArch.entityIDs.items[0]);
    try expectEqual(entity2, positionArch.entityIDs.items[1]);

    const p = Position{ .x = 73, .y = 123 };
    try positionArch.put(entity1, p);
    try positionArch.put(entity2, p);
    const slice = try positionArch.slice(Position);
    try expectEqual(p, slice[0]);
    try expectEqual(p, slice[1]);
}

test "ArchetypeStorage has" {
    var voidArch = try ArchetypeStorage.init(t.allocator);
    defer voidArch.deinit();
    var positionNameArch = try ArchetypeStorage.init(t.allocator);
    defer positionNameArch.deinit();
    try positionNameArch.addColumn(Position);
    try positionNameArch.addColumn(Name);

    try expect(voidArch.has(Position) == false);
    try expect(voidArch.has(Name) == false);

    try expect(positionNameArch.has(Position));
    try expect(positionNameArch.has(Name));
    try expect(positionNameArch.has(Target) == false);
}

test "ArchetypeStorage put, get, getPtr, slice" {
    var voidArch = try ArchetypeStorage.init(t.allocator);
    defer voidArch.deinit();
    var positionNameArch = try ArchetypeStorage.init(t.allocator);
    defer positionNameArch.deinit();
    try positionNameArch.addColumn(Position);
    try positionNameArch.addColumn(Name);

    const entity1: EntityID = 1;
    _ = try voidArch.newEntity(entity1);
    try voidArch.sync();

    _ = try positionNameArch.copyFromOldArchetype(entity1, voidArch);

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
    var voidArch = try ArchetypeStorage.init(t.allocator);
    defer voidArch.deinit();
    var positionNameArch = try ArchetypeStorage.init(t.allocator);
    defer positionNameArch.deinit();
    try positionNameArch.addColumn(Position);
    try positionNameArch.addColumn(Name);
    var positionNameTargetArch = try ArchetypeStorage.init(t.allocator);
    defer positionNameTargetArch.deinit();
    try positionNameTargetArch.addColumn(Position);
    try positionNameTargetArch.addColumn(Name);
    try positionNameTargetArch.addColumn(Target);

    const entity1: EntityID = 1;
    _ = try voidArch.newEntity(entity1);
    try voidArch.sync();

    // move to {Position,Name,Target} archetype
    _ = try positionNameTargetArch.copyFromOldArchetype(entity1, voidArch);
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
    _ = try positionNameArch.copyFromOldArchetype(entity1, positionNameTargetArch);
    try positionNameArch.sync();

    try expectEqual(p, try positionNameArch.get(entity1, Position));
    try expectEqual(n, try positionNameArch.get(entity1, Name));
    try t.expectError(error.ComponentNotPartOfArchetype, positionNameArch.get(entity1, Target));
}

test "ArchetypeStorage count, delete and hasEntity" {
    var voidArch = try ArchetypeStorage.init(t.allocator);
    defer voidArch.deinit();
    var positionNameArch = try ArchetypeStorage.init(t.allocator);
    defer positionNameArch.deinit();
    try positionNameArch.addColumn(Position);
    try positionNameArch.addColumn(Name);
    var positionNameTargetArch = try ArchetypeStorage.init(t.allocator);
    defer positionNameTargetArch.deinit();
    try positionNameTargetArch.addColumn(Position);
    try positionNameTargetArch.addColumn(Name);
    try positionNameTargetArch.addColumn(Target);

    const entity1: EntityID = 1;
    try expectEqual(@as(usize, 0), voidArch.count());
    _ = try voidArch.newEntity(entity1);
    try expectEqual(@as(usize, 0), voidArch.count());
    try voidArch.sync();
    try expectEqual(@as(usize, 1), voidArch.count());

    // move to {Position,Name,Target} archetype
    _ = try positionNameTargetArch.copyFromOldArchetype(entity1, voidArch);
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
    var voidArch = try ArchetypeStorage.init(t.allocator);
    defer voidArch.deinit();
    var testArch = try ArchetypeStorage.init(t.allocator);
    defer testArch.deinit();
    try testArch.addColumn(Position);
    try testArch.addColumn(Name);
    try testArch.addColumn(Target);

    // add 4 entities
    const entities = [_]EntityID{ 1, 2, 3, 4 };
    for (entities) |entity| {
        _ = try voidArch.newEntity(entity);
    }
    try voidArch.sync();

    // move to {Position,Name,Target} archetype
    for (voidArch.entities()) |entity, i| {
        _ = try testArch.copyFromOldArchetype(entity, voidArch);

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
    var voidArch = try ArchetypeStorage.init(t.allocator);
    defer voidArch.deinit();
    var testArch = try ArchetypeStorage.init(t.allocator);
    defer testArch.deinit();
    try testArch.addColumn(Position);
    try testArch.addColumn(Name);
    try testArch.addColumn(Target);

    // add 4 entities
    const entities = [_]EntityID{ 1, 2, 3, 4 };
    for (entities) |entity| {
        _ = try voidArch.newEntity(entity);
    }
    try voidArch.sync();

    // move to {Position,Name,Target} archetype
    for (voidArch.entities()) |entity, i| {
        _ = try testArch.copyFromOldArchetype(entity, voidArch);

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

const voidArchetypeHash: ArchetypeHash = std.math.maxInt(u64);

pub fn archetypeHash(arch: anytype) ArchetypeHash {
    if (@TypeOf(arch) == type) return archetypeHash(.{arch});

    const ty = @TypeOf(arch);
    const tyInfo = @typeInfo(ty);
    comptime if (!meta.trait.isTuple(ty)) {
        compError("expected tuple of types but got {?}", .{arch});
    };

    if (arch.len == 0) {
        return voidArchetypeHash;
    }

    inline for (tyInfo.Struct.fields) |field| {
        if (@TypeOf(field.type) != type) {
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

pub fn combineArchetypeHash(hash: ArchetypeHash, arch: anytype) ArchetypeHash {
    if (@TypeOf(arch) == type) return combineArchetypeHash(hash, .{arch});
    if (arch.len == 0) return hash;
    if (hash == voidArchetypeHash) return archetypeHash(arch);

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
        voidArchetypeHash,
        combineArchetypeHash(voidArchetypeHash, .{}),
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
        archetypeHash(.{ Position, Target }),
        combineArchetypeHash(combineArchetypeHash(archetypeHash(.{}), .{Position}), .{Target}),
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

    try expectEqual(
        archetypeHash(.{Name}),
        combineArchetypeHash(archetypeHash(.{ Name, Target, Position }), .{ Target, Position }),
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
        comptime if (!meta.trait.isTuple(field.type)) {
            compError("expected tuple of tuples of {{[]const u8, type}} but got {?}", .{arch});
        };
        comptime if (arch[i].len != 2 or @TypeOf(arch[i][1]) != type) {
            compError("expected tuple of tuples of {{[]const u8, type}} but got {?}", .{arch});
        };
    }

    var structFields: [arch.len + 1]std.builtin.Type.StructField = undefined;
    structFields[0] = .{
        .name = "entity",
        .type = EntityID,
        .default_value = null,
        .is_comptime = false,
        .alignment = @alignOf(EntityID),
    };
    inline for (arch) |lT, i| {
        @setEvalBranchQuota(10_000);
        structFields[i + 1] = .{
            .name = lT[0],
            .type = *lT[1],
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
        compError("expected tuple of tuples of {{[]const u8, type}} but got {any}", .{ty});
    };

    inline for (tyInfo.Struct.fields) |field, i| {
        comptime if (!meta.trait.isTuple(field.type)) {
            compError("expected tuple of tuples of {{[]const u8, type}} but got {any}", .{ty});
        };
        comptime if (arch[i].len != 2 or @TypeOf(arch[i][1]) != type) {
            compError("expected tuple of tuples of {{[]const u8, type}} but got {any}", .{ty});
        };
    }

    var structFields: [arch.len + 1]std.builtin.Type.StructField = undefined;
    structFields[0] = .{
        .name = "entities",
        .type = []EntityID,
        .default_value = null,
        .is_comptime = false,
        .alignment = @alignOf([]EntityID),
    };

    inline for (arch) |lT, i| {
        structFields[i + 1] = .{
            .name = lT[0],
            .type = []lT[1],
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
