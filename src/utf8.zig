const std = @import("std");
const unicode = std.unicode;
const t = std.testing;
const indexOfDiff = std.mem.indexOfDiff;
const TypeInfo = std.builtin.TypeInfo;

//=== some naming conventions ===//

/// one utf8 character
pub const Rune = []const u8;

/// index or length
pub const Runes = usize;

pub const empty_string = utf8("");

/// transform a type into Utf8 (comptime)
/// generates a compileError if it is not possible
///
/// supported types:
/// - Utf8
/// - []const u8
/// - basically any array type with u8
/// - .Int and .Float and also their comptime counterparts
pub inline fn utf8(any: anytype) Utf8 {
    const anyType = @TypeOf(any);
    const info = @typeInfo(anyType);
    if (Utf8.toString(any)) |str| {
        return Utf8{ .bytes = str };
    } else |_| {
        if (anyType == comptime_int or info == .Int or anyType == comptime_float or info == .Float) {
            const str: []const u8 = std.fmt.comptimePrint("{d}", .{any});
            return Utf8{ .bytes = str };
        }
        std.debug.panic("cannot coerse {*} to Utf8", .{@typeName(anyType)});
    }
}

/// Represents a UTF-8 string
pub const Utf8 = struct {
    bytes: []const u8,

    pub fn isValid(self: @This()) bool {
        return unicode.utf8ValidateSlice(self.bytes);
    }

    /// rune count in this string
    pub fn len(self: @This()) usize {
        var count: usize = 0;
        var i: usize = 0;
        while (i < self.bytes.len) : (count += 1) {
            i += unicode.utf8ByteSequenceLength(self.bytes[i]) catch 1;
        }
        return count;
    }

    /// rune at specified utf8 position in string
    pub fn at(self: @This(), index: Runes) !Rune {
        if (index > self.bytes.len) return error.IndexOutOfBounds;

        //not using the unicode.Utf8Iterator here as it can result in an panic if the utf8 bytes contain invalid sequences. i want to skip em or replace with error characters, dunno yet.
        var i: usize = 0;
        while (i <= index and i < self.bytes.len) {
            if (i == index) {
                const length = unicode.utf8ByteSequenceLength(self.bytes[i]) catch 1;
                return self.bytes[i .. i + length];
            } else {
                i += unicode.utf8ByteSequenceLength(self.bytes[i]) catch 1;
            }
        }
        return error.IndexOutOfBounds;
    }

    /// substring of this string
    pub fn sub(self: @This(), begin: ?Runes, cnt: ?Runes) !@This() {
        const start = begin orelse 0;
        const count = cnt orelse self.bytes.len - start;
        if (start + count > self.bytes.len) return error.IndexOutOfBounds;

        var i: usize = 0;
        var runeCount: usize = 0;
        var end: usize = start;
        while (i <= start + count and i < self.bytes.len) {
            if (i >= start) {
                const length = unicode.utf8ByteSequenceLength(self.bytes[i]) catch 1;
                end += length;
                runeCount += 1;
                if (runeCount == count) break;
            }
            i += unicode.utf8ByteSequenceLength(self.bytes[i]) catch 1;
        }

        return @This(){ .bytes = self.bytes[start..end] };
    }

    /// compares two strings
    pub fn eq(self: @This(), other: anytype) bool {
        if (indexOfDiff(u8, utf8(other).bytes, self.bytes)) |_| {
            return false;
        }
        return true;
    }

    /// append at comptime
    pub inline fn append(comptime self: @This(), any: anytype) @This() {
        return @This(){ .bytes = self.bytes ++ utf8(any).bytes };
    }

    /// append at runtime
    pub fn appendAlloc(self: @This(), allocator: std.mem.Allocator, any: anytype) !@This() {
        const other = utf8(any);
        const ptr = try allocator.alloc(u8, self.bytes.len + other.bytes.len);
        std.mem.copy(u8, ptr, self.bytes);
        std.mem.copy(u8, ptr[self.bytes.len..], other.bytes);
        return @This(){ .bytes = ptr };
    }

    /// iterator emitting UTF-8 runes
    pub const Iterator = struct {
        ///string reference
        str: Utf8,
        ///byte index
        i: usize = 0,

        /// is the end reached?
        pub fn exhausted(self: Iterator) bool {
            return self.i >= self.str.bytes.len;
        }

        /// get rune at current index
        pub fn peek(self: Iterator) Rune {
            if (self.exhausted()) return empty_string.bytes;
            const length = unicode.utf8ByteSequenceLength(self.str.bytes[self.i]) catch 1;
            return self.str.bytes[self.i .. self.i + length];
        }

        /// return rune at current index, then advance index by rune-size
        pub fn nextRune(self: *Iterator) Rune {
            if (self.exhausted()) return empty_string.bytes;
            const length = unicode.utf8ByteSequenceLength(self.str.bytes[self.i]) catch 1;
            defer self.i += length;
            return self.str.bytes[self.i .. self.i + length];
        }

        /// return rune as utf8 object at current index, then advance index by rune-size
        pub fn next(self: *Iterator) Utf8 {
            return Utf8{ .bytes = self.nextRune() };
        }

        /// move the cursor forward to skip runes
        pub fn skip(self: *Iterator, runeCount: Runes) void {
            var count = runeCount;
            while (count > 0 and !self.exhausted()) : (count -= 1) {
                _ = self.nextRune();
            }
        }
    };

    /// get iterator
    pub fn iterator(self: @This()) Iterator {
        return Iterator{ .str = self };
    }

    /// replace pattern with replacement
    pub fn replace(self: @This(), searchPattern: anytype, replaceWith: @This()) @This() {
        const pattern = utf8(searchPattern);
        const replacement = utf8(replaceWith);
        var new = utf8("");
        var it = self.iterator();
        while (!it.exhausted()) {
            var clone = it;
            var patternIterator = pattern.iterator();

            const doTheyMatch = while (!clone.exhausted() and !patternIterator.exhausted()) {
                if (std.mem.indexOfDiff(u8, clone.nextRune(), patternIterator.nextRune()) != null) {
                    break false;
                }
            } else true;

            if (doTheyMatch) {
                new = new.append(replacement);
                it.skip(pattern.len());
            } else {
                new = new.append(utf8(it.nextRune()));
            }
        }

        return new;
    }

    /// returns start index of given substring or null if the text cannot be found in the string
    pub fn indexOf(self: @This(), text: anytype) ?usize {
        const pattern = utf8(text);
        var index: Runes = 0;
        var it = self.iterator();
        while (!it.exhausted()) : (index += 1) {
            var clone = it;
            var patternIterator = pattern.iterator();

            const doTheyMatch = while (!clone.exhausted() and !patternIterator.exhausted()) {
                if (std.mem.indexOfDiff(u8, clone.nextRune(), patternIterator.nextRune()) != null) {
                    break false;
                }
            } else true;

            if (doTheyMatch) {
                return index;
            } else {
                _ = it.nextRune();
            }
        }

        return null;
    }

    /// does the string start with given prefix
    pub fn hasPrefix(self: @This(), prefix: anytype) bool {
        const prefixBytes: []const u8 = asString(prefix);
        if (prefixBytes.len == 0) return true;

        var i: usize = 0;
        while (i < self.bytes.len and i < prefixBytes.len) : (i += 1) {
            if (self.bytes[i] != prefixBytes[i]) {
                return false;
            }
        } else {
            return true;
        }
    }

    /// does the string end with given suffix
    pub fn hasSuffix(self: @This(), suffix: anytype) bool {
        const suffixBytes: []const u8 = asString(suffix);
        if (suffixBytes.len > self.bytes.len or self.bytes.len == 0 and suffixBytes.len > 0) return false;
        if (suffixBytes.len == 0) return true;

        var iSelf: isize = @intCast(isize, self.bytes.len - 1);
        var iSuffix: isize = @intCast(isize, suffixBytes.len - 1);
        while (iSuffix >= 0 and iSelf >= 0) : (iSelf -= 1) {
            if (self.bytes[@intCast(usize, iSelf)] != suffixBytes[@intCast(usize, iSuffix)]) {
                return false;
            }
            iSuffix -= 1;
        } else {
            return iSuffix < 0;
        }
    }

    /// tries to convert/extract the underlying slice to u8
    /// if the value is not "stringy" enough, null is returned
    pub fn toString(stringLike: anytype) error{NotStringLike}![]const u8 {
        const strType = @TypeOf(stringLike);
        const strTypeInfo: TypeInfo = @typeInfo(strType);
        comptime if (strType == []const u8) {
            return stringLike;
        } else if (strTypeInfo == .Pointer) {
            const ptrTypeInfo = @typeInfo(strTypeInfo.Pointer.child);
            if (ptrTypeInfo == .Array and ptrTypeInfo.Array.child == u8) {
                return stringLike;
            } else if (ptrTypeInfo == .Pointer and ptrTypeInfo.Pointer.size == .Slice and ptrTypeInfo.Pointer.child == u8) {
                return stringLike;
            } else if (ptrTypeInfo == .Pointer and ptrTypeInfo.Pointer.size == .C and ptrTypeInfo.Pointer.child == u8) {
                return stringLike;
            } else if (strTypeInfo.Pointer.child == Utf8) {
                return stringLike.*.bytes;
            } else {
                return error.NotStringLike;
            }
        } else if (strTypeInfo == .Array and strTypeInfo.Array.child == u8) {
            return stringLike;
        } else if (strType == Utf8) {
            return stringLike.bytes;
        } else {
            return error.NotStringLike;
        };
    }

    /// compile error if stringLike is not a string in any way
    fn asString(stringLike: anytype) []const u8 {
        return toString(stringLike) catch describeType(@TypeOf(stringLike)) ++ "\n-> cannot be transformed to []const u8";
    }

    //TODO implement std.fmt.format to be printable
    // pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    //     try std.fmt.formatBuf(value.bytes, options, writer);
    // }
};

fn describeType(comptime typ: type) []const u8 {
    comptime var description: []const u8 = "(";
    const name: []const u8 = @typeName(typ);
    const info: TypeInfo = @typeInfo(typ);
    description = description ++ name ++ ": ";

    description = description ++ switch (info) {
        .Pointer => ".Pointer size=" ++ switch (info.Pointer.size) {
            .One => "one, child=" ++ describeType(info.Pointer.child),
            .Many => "many, child=" ++ describeType(info.Pointer.child),
            .C => "c, child=" ++ describeType(info.Pointer.child),
            .Slice => "slice, child=" ++ describeType(info.Pointer.child),
        },
        .Array => ".Array " ++ (if (info.Array.sentinel != null) "sentinel=true, " else "") ++ "child=" ++ describeType(info.Array.child),
        .Optional => ".Optional child=" ++ describeType(info.Optional.child),
        .Struct => ".Struct",
        .Type => ".Type",
        .Void => ".Void",
        .Bool => ".Bool",
        .NoReturn => ".NoReturn",
        .Int => ".Int",
        .Float => ".Float",
        .ComptimeFloat => ".ComptimeFloat",
        .ComptimeInt => ".ComptimeInt",
        .Undefined => ".Undefined",
        .Null => ".Null",
        .ErrorUnion => ".ErrorUnion",
        .ErrorSet => ".ErrorSet",
        .Enum => ".Enum",
        .Union => ".Union",
        .Fn => ".Fn",
        .BoundFn => ".BoundFn",
        .Opaque => ".Opaque",
        .Frame => ".Frame",
        .AnyFrame => ".AnyFrame",
        .Vector => ".Vector",
        .EnumLiteral => ".EnumLiteral",
    };
    return description ++ ")";
}

//== TESTS ========================================================================================

fn assertEqual(a: anytype, b: anytype) void {
    const aStr = utf8(a);
    const bStr = utf8(b);
    var aIt = aStr.iterator();
    var bIt = bStr.iterator();
    var index: usize = 0;
    while (true) {
        if (aIt.exhausted() and !bIt.exhausted() or !aIt.exhausted() and bIt.exhausted()) {
            std.debug.print("length differs \"{s}\"({d}) != \"{s}\"({d})\n", .{ aStr.bytes, aStr.len(), bStr.bytes, bStr.len() });
            @panic("unequal length");
        } else if (aIt.exhausted() and bIt.exhausted()) {
            break;
        }

        if (!aIt.next().eq(bIt.next())) {
            std.debug.print("diff at index={} \"{s}\"({d}) != \"{s}\"({d})\n", .{ index, aStr.bytes, aStr.len(), bStr.bytes, bStr.len() });
            @panic("not equal");
        }
        index += 1;
    }
}

test "to utf8" {
    _ = utf8("this is a test");

    assertEqual(utf8("this"), "this");
    assertEqual(utf8(5), "5");
    assertEqual(utf8(5.123), "5.123");
    assertEqual(utf8(1.123 + 5.123), "6.246");
    assertEqual(utf8(0 / 5), "0");
    assertEqual(utf8(0.0 / 5.0), "0");
    assertEqual(utf8(5.0 / 5.0), "1");
    assertEqual(utf8(1.0 / 5.0), "0.2");
}

test "toString" {
    comptime {
        assertEqual(Utf8.asString("panic if not string"), "panic if not string");
        assertEqual(try Utf8.toString("yes"), "yes");
        assertEqual(try Utf8.toString(utf8("yes")), "yes");
        assertEqual(try Utf8.toString(&utf8("yes")), "yes");
        try t.expectError(error.NotStringLike, Utf8.toString(5));
    }
}

test "isValid" {
    const sut = Utf8{ .bytes = "this is a test" };

    try t.expect(sut.isValid());

    const invalidUtf8Bytes = [_]u8{ 0xFF, 0xFF };
    const invalidSut = Utf8{ .bytes = invalidUtf8Bytes[0..] };

    try t.expect(!invalidSut.isValid());
}

test "at" {
    const sut: Utf8 = Utf8{ .bytes = "this is a test" };

    assertEqual("i", sut.at(5) catch "error");
    comptime {
        assertEqual("i", sut.at(5) catch "error");
    }
}

test "len" {
    try t.expect(empty_string.len() == 0);
    try t.expect(utf8("this is a test").len() == 14);
    try t.expect(utf8("😁").len() == 1);
    try t.expect(utf8("😁").bytes.len > 1);
    try t.expect(utf8("hey 😘").len() == 5);
    try t.expect(utf8("\n").len() == 1);

    comptime {
        try t.expect(empty_string.len() == 0);
        try t.expect(utf8("this is a test").len() == 14);
        try t.expect(utf8("😁").len() == 1);
        try t.expect(utf8("hey 😘").len() == 5);
        try t.expect(utf8("\n").len() == 1);
    }
}

test "eq" {
    const sut: Utf8 = Utf8{ .bytes = "this is a test" };

    try t.expect(utf8("this is a test").eq(sut));
    try t.expect(sut.eq(utf8("this is a test")));

    comptime {
        try t.expect(utf8("this is a test").eq(sut));
        try t.expect(sut.eq(utf8("this is a test")));
    }
}

test "sub" {
    const sut: Utf8 = Utf8{ .bytes = "this is a test" };

    try t.expect((try sut.sub(0, 4)).eq(utf8("this")));
    try t.expect((try sut.sub(null, 4)).eq(utf8("this")));
    try t.expect((try sut.sub(5, 2)).eq(utf8("is")));
    try t.expect((try sut.sub(8, 6)).eq(utf8("a test")));
    try t.expect((try sut.sub(8, null)).eq(utf8("a test")));
    try t.expect((try sut.sub(null, null)).eq(utf8("this is a test")));

    comptime {
        try t.expect((try sut.sub(0, 4)).eq(utf8("this")));
        try t.expect((try sut.sub(null, 4)).eq(utf8("this")));
        try t.expect((try sut.sub(5, 2)).eq(utf8("is")));
        try t.expect((try sut.sub(8, 6)).eq(utf8("a test")));
        try t.expect((try sut.sub(8, null)).eq(utf8("a test")));
        try t.expect((try sut.sub(null, null)).eq(utf8("this is a test")));
    }
}

test "append / appendAlloc" {
    const a: Utf8 = Utf8{ .bytes = "this is " };
    const b: Utf8 = Utf8{ .bytes = "a test" };

    const c = try a.appendAlloc(t.allocator, b);
    defer t.allocator.free(c.bytes);
    try t.expect(c.eq(utf8("this is a test")));

    comptime {
        try t.expect(a.append(b).eq(utf8("this is a test")));
    }
}

test "iterator" {
    const sut = utf8("this is a test");
    var it = sut.iterator();
    var it2 = &it;
    var it3 = it;
    var it4 = sut.iterator();

    try t.expect(!it.exhausted());
    try t.expectEqualStrings("t", it.nextRune());
    try t.expectEqualStrings("h", it.nextRune());
    try t.expectEqualStrings("i", it.nextRune());
    try t.expectEqualStrings("s", it.nextRune());
    try t.expectEqualStrings(" ", it.nextRune());
    try t.expectEqualStrings("i", it.nextRune());
    try t.expectEqualStrings("s", it.nextRune());
    try t.expect(!it.exhausted());
    try t.expectEqualStrings(" ", it.nextRune());
    try t.expectEqualStrings("a", it.nextRune());
    try t.expectEqualStrings(" ", it.nextRune());
    try t.expectEqualStrings("t", it.nextRune());
    try t.expectEqualStrings("e", it.nextRune());
    try t.expectEqualStrings("s", it.nextRune());
    try t.expectEqualStrings("t", it.nextRune());

    try t.expect(it.exhausted());

    //then only empty strings
    try t.expectEqualStrings("", it.nextRune());
    try t.expectEqualStrings("", it.nextRune());
    try t.expectEqualStrings("", it.nextRune());

    try t.expectEqualStrings("", it2.nextRune());
    try t.expectEqualStrings("t", it3.nextRune());
    try t.expectEqualStrings("t", it4.nextRune());
}

test "replace" {
    comptime {
        const sut = utf8("this is a test");
        const result = sut.replace(utf8("is"), utf8("was"));

        try t.expectEqualStrings(result.bytes, "thwas was a test");
    }
}

test "hasPrefix" {
    try t.expect(utf8("this is a test").hasPrefix(utf8("this is")));
    try t.expect(utf8("this is a test").hasPrefix(utf8("this is a test")));
    try t.expect(utf8("this is a test").hasPrefix(utf8("")));
    try t.expect(utf8("this is a test").hasPrefix("this"));
}

test "hasSuffix" {
    try t.expect(utf8("this is a test").hasSuffix(utf8("a test")));
    try t.expect(utf8("this is a test").hasSuffix(utf8("this is a test")));
    try t.expect(utf8("this is a test").hasSuffix(utf8("")));
    try t.expect(utf8("this is a test").hasSuffix("test"));
}

test "indexOf" {
    try t.expect(utf8("this is a test").indexOf("a").? == 8);
    try t.expect(utf8("random text").indexOf("z") == null);
    try t.expect(utf8("this is a test!!111!!").indexOf("test").? == 10);
    try t.expect(utf8("this is a test!!111!!").indexOf(1).? == 16);
    try t.expect(utf8("this is a test!!111!!").indexOf(111).? == 16);
    try t.expect(utf8(3.14159265359).indexOf(926).? == 6);
    try t.expect(utf8(5).indexOf(5).? == 0);
    try t.expect(utf8(5).indexOf("5").? == 0);
    try t.expect(utf8("5").indexOf(5).? == 0);
    try t.expect(utf8("5").indexOf("5").? == 0);
}

fn testWrite(context: []u8, str: []const u8) error{TestError}!usize {
    for (str) |b, i| {
        context[i] = b;
    }
    return str.len;
}
pub const TestWriter = std.io.Writer([]u8, error{TestError}, testWrite);

// test "format" {
//     var buffer: [256]u8 = undefined;
//     var writer = TestWriter{ .context = buffer[0..] };

//     try std.fmt.format(writer, "{}", utf8("this is a test"));

//     try t.expectEqualStrings("this is a test", buffer[0..(utf8("this is a test").bytes.len)]);
// }

//===================================================================
// test "compiler bug" {
//     std.debug.print("{}", .{(utf8("lol test").sub(4, 8) catch utf8("error"))});
// }
//===================================================================
