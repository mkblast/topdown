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
dash_cooldown: Timer = .init(0.02),
status: Status = .alive,

const Status = enum(u8) { alive, dead, empty };

pub const Index = enum(usize) {
    _,

    pub fn new(idx: usize) Index {
        return @enumFromInt(idx);
    }

    pub fn get(index: Index) usize {
        return @intFromEnum(index);
    }
};

pub const Kind = enum {
    default,
    guy,
    enemy,
    bullet,
};

pub fn applyPhysics(entity: *Entity, dt: f32) void {
    entity.pos = .add(entity.pos, .scale(entity.vel, dt));
}

pub fn draw(entity: *Entity) void {
    switch (entity.kind) {
        .guy => {
            const rect: rl.Rectangle = .init(entity.pos.x, entity.pos.y, 50, 50);
            rl.drawRectanglePro(rect, .init(25, 25), entity.rot, .blue);
        },

        .bullet => {
            rl.drawCircleV(entity.pos, 5, .red);
        },

        else => {},
    }
}
