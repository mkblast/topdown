const std = @import("std");
const Io = std.Io;

const math = std.math;
const log = std.log;
const heap = std.heap;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

const Kind = enum {
    default,
    guy,
    enemy,
    bullet,
};

const State = enum {
    menu,
    playing,
};

const speed = 1000;
const bullet_speed = 5000.0;
const screen_width = 1280;
const screen_hieght = 720;

const Timer = struct {
    duration: f32,
    remaining: f32,

    fn init(duration: f32) Timer {
        return .{
            .duration = duration,
            .remaining = 0,
        };
    }

    fn update(self: *Timer, dt: f32) void {
        if (self.remaining > 0) {
            self.remaining -= dt;
            if (self.remaining < 0) self.remaining = 0;
        }
    }

    fn start(self: *Timer) void {
        self.remaining = self.duration;
    }

    fn isDone(self: Timer) bool {
        return self.remaining <= 0;
    }

    fn progress(self: Timer) f32 {
        if (self.duration == 0) return 1.0;
        return 1.0 - (self.remaining / self.duration);
    }
};

const Entity = struct {
    kind: Kind = .default,
    pos: Vector2 = .zero(),
    vel: Vector2 = .zero(),
    dir: Vector2 = .zero(),
    rot: f32 = 0,
    health: u32 = 100,
    life_time: Timer = .init(0),
    active: bool = true,

    fn update(self: *Entity) void {
        const dt = rl.getFrameTime();

        switch (self.kind) {
            .guy => {
                self.dir = .normalize(self.dir);
                self.vel = .scale(self.dir, speed);
                self.pos = .add(self.pos, .scale(self.vel, dt));

                self.dir = .zero();
            },

            .bullet => {
                self.pos = .add(self.pos, .scale(self.vel, dt));
                self.rot = math.atan2(self.vel.y, self.vel.x) * (180.0 * math.pi);
                self.life_time.update(dt);
            },

            else => {},
        }
    }

    fn clean(self: *Entity, entity_pool: *EntityPool, i: EntityIndex) !void {
        switch (self.kind) {
            .bullet => {
                if (self.life_time.isDone()) {
                    self.active = false;
                    try entity_pool.remove(i);
                }
            },
            else => {},
        }
    }

    fn draw(self: *Entity, camera: rl.Camera2D) void {
        switch (self.kind) {
            .guy => {
                const mouse_pos = rl.getMousePosition();
                const mouse_world_pos = rl.getScreenToWorld2D(mouse_pos, camera);
                const angle = math.atan2(mouse_world_pos.y - self.pos.y, mouse_world_pos.x - self.pos.x);
                self.rot = angle * (180.0 / math.pi);

                const rect: rl.Rectangle = .init(self.pos.x, self.pos.y, 50, 50);
                rl.drawRectanglePro(rect, .init(25, 25), self.rot, .blue);

                // refrence
                rl.drawRectangle(10, 10, 20, 50, .white);
            },

            .bullet => {
                rl.drawCircleV(self.pos, 2, .red);
            },

            else => {},
        }
    }
};

const EntityIndex = enum(usize) {
    _,

    fn new(idx: usize) EntityIndex {
        return @enumFromInt(idx);
    }

    fn get(self: EntityIndex) usize {
        return @intFromEnum(self);
    }
};

const max_capacity = 1000;

const EntityPool = struct {
    pool: ArrayList(Entity),
    empty_slots: ArrayList(EntityIndex),

    var pool_array: [max_capacity]Entity = undefined;
    var empty_slots_array: [max_capacity]EntityIndex = undefined;

    fn init() EntityPool {
        return .{
            .pool = .initBuffer(&pool_array),
            .empty_slots = .initBuffer(&empty_slots_array),
        };
    }

    fn reserve(self: *EntityPool, kind: Kind) !EntityIndex {
        const e: Entity = .{ .kind = kind };

        if (self.empty_slots.getLastOrNull()) |slot| {
            self.pool.items[slot.get()] = e;
            return slot;
        }

        try self.pool.appendBounded(e);
        return .new(self.pool.items.len - 1);
    }

    fn appened(self: *EntityPool, e: Entity) !EntityIndex {
        if (self.empty_slots.pop()) |slot| {
            self.pool.items[slot.get()] = e;
            return slot;
        }

        try self.pool.appendBounded(e);
        return .new(self.pool.items.len - 1);
    }

    fn get(self: EntityPool, idx: EntityIndex) *Entity {
        return &self.pool.items[idx.get()];
    }

    fn remove(self: *EntityPool, idx: EntityIndex) !void {
        try self.empty_slots.appendBounded(idx);
    }

    fn findMany(self: EntityPool, arena: Allocator, kind: Kind) ![]EntityIndex {
        var arr: ArrayList(EntityIndex) = try .initCapacity(arena, self.pool.items.len);
        for (self.pool.items, 0..) |e, i| {
            if (e.kind == kind) try arr.append(arena, .new(i));
        }

        return arr.toOwnedSlice(arena);
    }
};

const Game = struct {
    io: Io,
    gpa: Allocator,
    arena: *heap.ArenaAllocator,
    entity_pool: EntityPool,
    guy_index: EntityIndex,
    camera: rl.Camera2D,
    state: State,

    fn init(io: Io, gpa: Allocator, arena: *heap.ArenaAllocator) !Game {
        rl.initWindow(1280, 720, "topdown");
        rl.setExitKey(.null);
        rl.setTargetFPS(60);

        var pool: EntityPool = .init();
        const guy = try pool.reserve(.guy);

        return .{
            .camera = .{
                .offset = .init(screen_width / 2, screen_hieght / 2),
                .target = .init(0, 0),
                .zoom = 1,
                .rotation = 0,
            },
            .io = io,
            .gpa = gpa,
            .arena = arena,
            .entity_pool = pool,
            .guy_index = guy,
            .state = .playing,
        };
    }

    fn deinit(self: *Game) void {
        _ = self;
        rl.closeWindow();
    }

    fn run(self: *Game) !void {
        while (!rl.windowShouldClose()) {

            // Input:
            {
                const guy = self.entity_pool.get(self.guy_index);

                // -- Guy --
                if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) {
                    guy.dir.x = 1;
                }
                if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) {
                    guy.dir.x = -1;
                }
                if (rl.isKeyDown(.up) or rl.isKeyDown(.w)) {
                    guy.dir.y = -1;
                }
                if (rl.isKeyDown(.down) or rl.isKeyDown(.s)) {
                    guy.dir.y = 1;
                }

                // --- bullet ---
                if (rl.isMouseButtonPressed(.left)) {
                    const mouse_world = rl.getScreenToWorld2D(rl.getMousePosition(), self.camera);
                    const dir: Vector2 = .subtract(mouse_world, guy.pos);

                    var bullet: Entity = .{
                        .kind = .bullet,
                        .vel = .scale(.normalize(dir), bullet_speed),
                        .pos = guy.pos,
                        .life_time = .init(1),
                    };
                    bullet.life_time.start();

                    _ = try self.entity_pool.appened(bullet);
                }
            }

            // Update:
            {
                // --- Entities ---
                for (self.entity_pool.pool.items, 0..) |*e, i| {
                    if (e.active) {
                        e.update();
                        try e.clean(&self.entity_pool, .new(i));
                    }
                }

                // --- Camera ---
                {
                    const guy = self.entity_pool.get(self.guy_index);
                    const dt = rl.getFrameTime();
                    const smoothness: f32 = 20.0;

                    self.camera.target.x = math.lerp(
                        self.camera.target.x,
                        guy.pos.x + 25,
                        1.0 - @exp(-smoothness * dt),
                    );
                    self.camera.target.y = math.lerp(self.camera.target.y, guy.pos.y + 25, 1.0 - @exp(-smoothness * dt));
                }
            }

            // Draw:
            {
                rl.beginDrawing();
                defer rl.endDrawing();
                rl.clearBackground(.black);

                // --- Worldspace ---
                {
                    self.camera.begin();
                    defer self.camera.end();

                    for (self.entity_pool.pool.items) |*e| {
                        if (e.active) e.draw(self.camera);
                    }
                }

                // --- Screen Space (UI) ---
                rl.drawFPS(10, 10);
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var game: Game = try .init(init.io, init.gpa, init.arena);
    defer game.deinit();
    try game.run();
}
