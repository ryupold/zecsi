const std = @import("std");

const r = @cImport({
    @cInclude("raylib_marshall.h");
});
const t = @import("types.zig");
