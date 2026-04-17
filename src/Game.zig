const Game = @This();

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

const EntityManager = @import("EntityManager.zig");
const Entity = @import("Entity.zig");
const LevelEditor = @import("LevelEditor.zig");

io: Io,
gpa: Allocator,
arena: *heap.ArenaAllocator,
entity_manager: EntityManager,
guy_index: Entity.Index,
camera: rl.Camera2D,
state: State,
level_editor: LevelEditor,

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

    var manager: EntityManager = try .init(gpa);
    const guy = try manager.reserve(.guy);

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
        .entity_manager = manager,
        .guy_index = guy,
        .state = .game,
        .level_editor = try .init(),
    };
}

pub fn deinit(self: *Game) void {
    self.entity_manager.deinit(self.gpa);
    rl.closeWindow();
}

pub fn run(self: *Game) !void {
    while (!rl.windowShouldClose()) {
        defer _ = self.arena.reset(.retain_capacity);

        // Input:
        {
            const dt = rl.getFrameTime();
            // -- Global --
            if (rl.isKeyPressed(.tab)) {
                self.state = if (self.state == .editor) .game else .editor;
            }

            switch (self.state) {
                .game => {
                    const guy = self.entity_manager.get(self.guy_index);

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

                    guy.shot_cooldown.update(dt);

                    // --- bullet ---
                    if (rl.isMouseButtonDown(.left) and guy.shot_cooldown.isDone()) {
                        const mouse_world = rl.getScreenToWorld2D(rl.getMousePosition(), self.camera);
                        const dir: Vector2 = .subtract(mouse_world, guy.pos);

                        const bullet: Entity = .{
                            .kind = .bullet,
                            .vel = .scale(.normalize(dir), bullet_speed),
                            .pos = guy.pos,
                            .life_time = .initStart(1),
                        };

                        _ = try self.entity_manager.appened(bullet);
                        guy.shot_cooldown.start();
                    }
                },

                .editor => {
                    const level_editor = &self.level_editor;
                    const map_width = LevelEditor.map_width;
                    const map_height = LevelEditor.map_height;
                    const tile_size = level_editor.tile_set.tile_size;
                    const tile_surface = tile_size * tile_size;
                    const tile_set_surface: u32 = @intCast(level_editor.tile_set.width * level_editor.tile_set.height);
                    const tile_set_size = tile_set_surface / tile_surface;
                    const tile_set_width = level_editor.tile_set.width;

                    if (rl.isKeyPressed(.h)) {
                        level_editor.tile_set_showen = !level_editor.tile_set_showen;
                    }

                    if (rl.isKeyPressed(.right)) {
                        level_editor.selected_texture = (level_editor.selected_texture + 1) % tile_set_size;
                    }

                    if (rl.isKeyPressed(.left)) {
                        if (level_editor.selected_texture == 0) level_editor.selected_texture = tile_set_size - 1 //
                        else level_editor.selected_texture = (level_editor.selected_texture - 1) % tile_set_size;
                    }

                    if (rl.isKeyPressed(.down)) {
                        level_editor.selected_texture = (level_editor.selected_texture + tile_set_width) % tile_set_size;
                    }

                    if (rl.isKeyPressed(.up)) {
                        if (level_editor.selected_texture < tile_set_width) level_editor.selected_texture = (tile_set_size - tile_set_width) +  level_editor.selected_texture //
                        else level_editor.selected_texture = (level_editor.selected_texture - tile_set_width) % tile_set_size;
                    }

                    if (rl.isMouseButtonDown(.left)) {
                        const mouse_pos = rl.getMousePosition();
                        const mouse_x: u32 = @trunc(mouse_pos.x);
                        const mouse_y: u32 = @trunc(mouse_pos.y);
                        const x: usize = mouse_x / tile_size;
                        const cord_y: usize = mouse_y / tile_size;
                        if (x < map_width and cord_y < map_height) {
                            const y =  mouse_y / tile_size * map_height;
                            level_editor.world_map[x + y] = .{ .texture_id = level_editor.selected_texture, .kind = .wall };
                        }
                    }

                    if (rl.isKeyPressed(.s)) {
                        var allocating: Io.Writer.Allocating = .init(self.arena.allocator());
                        try std.zon.stringify.serialize(self.level_editor.world_map, .{}, &allocating.writer);
                        std.debug.print("{s}", .{allocating.written()});
                    }
                },
            }
        }

        // Update:
        {
            const dt = rl.getFrameTime();

            switch (self.state) {
                .game => {
                    // --- Entities ---
                    for (self.entity_manager.entities.items) |*e| {
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
                        const guy = self.entity_manager.get(self.guy_index);
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

                .editor => {},
            }
        }

        // Clean:
        {
            for (self.entity_manager.entities.items, 0..) |*e, i| {
                if (e.status != .dead) continue;
                e.kind = .default;
                e.status = .empty;
                try self.entity_manager.remove(.new(i));
            }
        }

        // Draw:
        {
            rl.beginDrawing();
            defer rl.endDrawing();
            rl.clearBackground(.black);

            switch (self.state) {
                .game => {
                    {
                        self.camera.begin();
                        defer self.camera.end();

                        // refrence
                        rl.drawRectangle(10, 10, 20, 50, .white);

                        for (self.entity_manager.entities.items) |*e| {
                            if (e.status != .alive) continue;
                            e.draw();
                        }
                    }

                    // --- Worldspace ---
                    {
                        // --- Screen Space (UI) ---
                        rl.drawFPS(10, 10);
                    }
                },

                .editor => {
                    self.level_editor.draw();
                },
            }
        }
    }
}
