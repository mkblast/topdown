const std = @import("std");
const math = std.math;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

const Timer = @import("Timer.zig");

kind: Kind = .default,
pos: Vector2 = .zero(),
vel: Vector2 = .zero(),
dir: Vector2 = .zero(),
rot: f32 = 0,
health: u32 = 100,
life_time: Timer = .init(0),
status: enum { active, cleanup, unactive } = .active,

const Entity = @This();

pub const Index = enum(usize) {
    _,

    pub fn new(idx: usize) Index {
        return @enumFromInt(idx);
    }

    pub fn get(self: Index) usize {
        return @intFromEnum(self);
    }
};

pub const Kind = enum {
    default,
    guy,
    enemy,
    bullet,
};

pub fn applyPhysics(self: *Entity, dt: f32) void {
    self.pos = .add(self.pos, .scale(self.vel, dt));
}

pub fn draw(self: *Entity, camera: rl.Camera2D) void {
    switch (self.kind) {
        .guy => {
            const mouse_pos = rl.getMousePosition();
            const mouse_world_pos = rl.getScreenToWorld2D(mouse_pos, camera);
            const angle = math.atan2(mouse_world_pos.y - self.pos.y, mouse_world_pos.x - self.pos.x);
            self.rot = angle * (180.0 / math.pi);

            const rect: rl.Rectangle = .init(self.pos.x, self.pos.y, 50, 50);
            rl.drawRectanglePro(rect, .init(25, 25), self.rot, .blue);
        },

        .bullet => {
            rl.drawCircleV(self.pos, 5, .red);
        },

        else => {},
    }
}
