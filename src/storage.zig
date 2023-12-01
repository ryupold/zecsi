//! Abstraction for LocalStorage
//! On desktop the data is written to a JSON file `localStorage.json`
const std = @import("std");
const builtin = @import("builtin");

pub fn get(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    return switch (builtin.os.tag) {
        //web
        .emscripten, .wasi => {
            const c = @cImport({
                @cDefine("__EMSCRIPTEN__", "1");
                @cInclude("emscripten/emscripten.h");
                @cInclude("stdlib.h");
            });
            const cKey = try std.fmt.allocPrintZ(allocator, "{s}", .{key});
            const cKeyPtr = @intFromPtr(cKey.ptr);
            defer c.free(@as(*anyopaque, @ptrFromInt(cKeyPtr)));
            const cValue = getItem(@as([*c]const u8, @ptrCast(cKey)));
            if (cValue != null) {
                const v = try allocator.dupe(u8, cValue[0..std.mem.len(cValue)]);
                const cValuePtr = @intFromPtr(cValue);
                c.free(@as(*anyopaque, @ptrFromInt(cValuePtr)));
                return v;
            }
            return null;
        },
        //desktop
        else => {
            const cwd = std.fs.cwd();
            const data = cwd.readFileAlloc(allocator, "localStorage.json", 2 * 1024 * 1024) catch {
                return null;
            };
            defer allocator.free(data);

            const map = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
            defer map.deinit();

            if (map.value.object.get(key)) |v| {
                std.debug.print("loaded data", .{});
                return try allocator.dupe(u8, v.string);
            }

            return null;
        },
    };
}

extern fn getItem(key: [*c]const u8) [*c]const u8;
extern fn setItem(key: [*c]const u8, value: [*c]const u8) void;

/// Uses temporary an allocator to load the json but frees it in this method
pub fn set(allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
    return switch (builtin.os.tag) {
        //web
        .emscripten, .wasi => {
            const c = @cImport({
                @cDefine("__EMSCRIPTEN__", "1");
                @cInclude("emscripten/emscripten.h");
                @cInclude("stdlib.h");
            });
            const cKey = try std.fmt.allocPrintZ(allocator, "{s}", .{key});
            const cKeyPtr = @intFromPtr(cKey.ptr);
            defer c.free(@as(*anyopaque, @ptrFromInt(cKeyPtr)));
            const cValue = try std.fmt.allocPrintZ(allocator, "{s}", .{value});
            const cValuePtr = @intFromPtr(cValue.ptr);
            defer c.free(@as(*anyopaque, @ptrFromInt(cValuePtr)));

            setItem(
                @as([*c]const u8, @ptrCast(cKey)),
                @as([*c]const u8, @ptrCast(cValue)),
            );
        },
        //desktop
        else => {
            const cwd = std.fs.cwd();
            const data = cwd.readFileAlloc(allocator, "localStorage.json", 2 * 1024 * 1024) catch c: {
                break :c try std.fmt.allocPrint(allocator, "{{}}", .{});
            };
            defer allocator.free(data);

            var map = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
            defer map.deinit();

            // FIXME: possible memory leak?
            try map.value.object.put(key, .{ .string = value });

            var file = try cwd.createFile("localStorage.json", .{});
            defer file.close();

            const writer = std.io.Writer(std.fs.File, std.fs.File.WriteError, std.fs.File.write){
                .context = file,
            };

            // try map.value. jsonStringify(.{}, writer);
            try std.json.stringify(map.value, .{}, writer);

            std.debug.print("safed data", .{});
        },
    };
}
