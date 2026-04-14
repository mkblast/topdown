const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;

const math = std.math;
const log = std.log;
const heap = std.heap;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

const EntityPool = @import("EntityPool.zig");
const Entity = @import("Entity.zig");
const LevelEditor = @import("LevelEditor.zig");

io: Io,
gpa: Allocator,
arena: *heap.ArenaAllocator,
entity_pool: EntityPool,
guy_index: Entity.Index,
camera: rl.Camera2D,
state: State,
level_editor: LevelEditor,

const Game = @This();

pub const State = enum {
    editor,
    game,
};

const speed = 1000;
const bullet_speed = 2500.0;
const screen_width = 1280;
const screen_hieght = 720;

pub fn init(io: Io, gpa: Allocator, arena: *heap.ArenaAllocator) !Game {
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
        .state = .game,
        .level_editor =  try .init(),
    };
}

pub fn deinit(self: *Game) void {
    _ = self;
    rl.closeWindow();
}

pub fn run(self: *Game) !void {
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

                const bullet: Entity = .{
                    .kind = .bullet,
                    .vel = .scale(.normalize(dir), bullet_speed),
                    .pos = guy.pos,
                    .life_time = .initStart(1),
                };

                _ = try self.entity_pool.appened(bullet);
            }

            // -- Editor --
            if (rl.isKeyPressed(.tab)) {
                self.state = if (self.state == .editor) .game else .editor;
            }
        }

        // Update:
        {
            const dt = rl.getFrameTime();

            switch (self.state) {
                .game => {
                    // --- Entities ---
                    for (self.entity_pool.pool.items) |*e| {
                        if (e.status != .alive) continue;
                        switch (e.kind) {
                            .guy => {
                                e.vel = .scale(.normalize(e.dir), speed);
                                e.applyPhysics(dt);
                                e.dir = .zero();
                            },

                            .bullet => {
                                e.applyPhysics(dt);
                                e.rot = math.atan2(e.vel.y, e.vel.x) * (180.0 / math.pi);
                                e.life_time.update(dt);
                                if (e.life_time.isDone()) e.status = .dead;
                            },

                            else => {},
                        }
                    }

                    // --- Camera ---
                    {
                        const guy = self.entity_pool.get(self.guy_index);
                        const smoothness: f32 = 20.0;

                        self.camera.target.x = math.lerp(self.camera.target.x, guy.pos.x + 25, 1.0 - @exp(-smoothness * dt));
                        self.camera.target.y = math.lerp(self.camera.target.y, guy.pos.y + 25, 1.0 - @exp(-smoothness * dt));

                        // rotation
                        const mouse_pos = rl.getMousePosition();
                        const mouse_world_pos = rl.getScreenToWorld2D(mouse_pos, self.camera);
                        const angle = math.atan2(mouse_world_pos.y - guy.pos.y, mouse_world_pos.x - guy.pos.x);
                        guy.rot = angle * (180.0 / math.pi);

                    }

                },

                .editor => {

                },
            }
        }

        // Clean:
        {
            for (self.entity_pool.pool.items, 0..) |*e, i| {
                if (e.status != .dead) continue;
                e.kind = .default;
                e.status = .empty;
                try self.entity_pool.remove(.new(i));
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

                // refrence
                rl.drawRectangle(10, 10, 20, 50, .white);

                for (self.entity_pool.pool.items) |*e| {
                    if (e.status != .alive) continue;
                    e.draw();
                }
            }

            {
                // --- Screen Space (UI) ---
                rl.drawFPS(10, 10);
            }
        }
    }
}
