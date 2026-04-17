const Entity = @This();

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
shot_cooldown: Timer = .init(0.01),
status: enum { alive, dead, empty } = .alive,

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

pub fn draw(self: *Entity) void {
    switch (self.kind) {
        .guy => {
            const rect: rl.Rectangle = .init(self.pos.x, self.pos.y, 50, 50);
            rl.drawRectanglePro(rect, .init(25, 25), self.rot, .blue);
        },

        .bullet => {
            rl.drawCircleV(self.pos, 5, .red);
        },

        else => {},
    }
}
