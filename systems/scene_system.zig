const std = @import("std");
const builtin = @import("builtin");
const zecsi = @import("../zecsi.zig");
const log = zecsi.log;
const raylib = zecsi.raylib;
const base = zecsi.baseSystems;

pub const Scene = struct {
    init: *const fn (ecs: *zecsi.ECS) anyerror!void,
    deinit: *const fn (ecs: *zecsi.ECS) anyerror!void,
};

pub const SceneSystem = struct {
    ecs: *zecsi.ECS,
    currentScene: ?Scene = null,
    nextLoadScene: ?Scene = null,

    pub fn init(ecs: *zecsi.ECS) !@This() {
        return @This(){
            .ecs = ecs,
        };
    }

    pub fn deinit(this: *@This()) void {
        if (this.currentScene) |current| {
            this.currentScene = null;
            current.deinit.*(this.ecs) catch unreachable;
        }
    }

    pub fn loadScene(this: *@This(), scene: Scene) !void {
        if (this.currentScene) |current| {
            if (std.meta.eql(current, scene)) return;
            log.info("========= unload scene =========\n", .{});
            this.currentScene = null;
            try current.deinit.*(this.ecs);
        }
        this.nextLoadScene = scene;
    }

    pub fn ui(this: *@This(), _: f32) !void {
        if (this.nextLoadScene) |next| {
            log.info("========= load scene =========\n", .{});
            try next.init.*(this.ecs);
            this.currentScene = next;
            this.nextLoadScene = null;
        }
    }
};
