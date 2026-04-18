const Game = @This();

const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;

const math = std.math;
const log = std.log;
const heap = std.heap;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMapUnmanaged;

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

pub var textures: StringHashMap(rl.Texture2D) = .empty;

const speed = 1000;
const bullet_speed = 2500.0;
var screen_width: i32 = 1280;
var screen_height: i32 = 720;

pub fn init(io: Io, gpa: Allocator, arena: *heap.ArenaAllocator) !Game {
    rl.initWindow(1280, 720, "topdown");
    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    var manager: EntityManager = try .init(gpa);
    const guy = try manager.reserve(.guy);

    return .{
        .camera = .{
            .offset = .init(@floatFromInt(@divTrunc(screen_width, 2)), @floatFromInt(@divTrunc(screen_height, 2))),
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
        .level_editor = try .init(gpa, "./assets/wall_sheet.png", 64, 16, 16),
    };
}

pub fn deinit(self: *Game) void {
    self.entity_manager.deinit(self.gpa);
    self.level_editor.deinit(self.gpa);
    textures.deinit(self.gpa);
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
                    if (level_editor.tile_map) |tile_map| {
                        const map_width = tile_map.width;
                        const map_height = tile_map.height;

                        const tile_size = tile_map.tile_set.tile_size;
                        const tile_set_width = tile_map.tile_set.width;
                        const tile_set_height = tile_map.tile_set.height;
                        const tiles = tile_set_width * tile_set_height;

                        if (rl.isKeyPressed(.right)) {
                            level_editor.selected_texture = (level_editor.selected_texture + 1) % tiles;
                        }

                        if (rl.isKeyPressed(.left)) {
                            if (level_editor.selected_texture == 0)
                                level_editor.selected_texture = tiles - 1
                            else
                                level_editor.selected_texture = (level_editor.selected_texture - 1) % tiles;
                        }

                        if (rl.isKeyPressed(.down)) {
                            level_editor.selected_texture = (level_editor.selected_texture + tile_set_width) % tiles;
                        }

                        if (rl.isKeyPressed(.up)) {
                            if (level_editor.selected_texture < tiles)
                                level_editor.selected_texture = (tiles - tile_set_width) + level_editor.selected_texture
                            else
                                level_editor.selected_texture = (level_editor.selected_texture - tile_set_width) % tiles;
                        }

                        if (rl.isMouseButtonDown(.left)) {
                            const mouse_pos = rl.getMousePosition();
                            const mouse_x: u32 = @trunc(mouse_pos.x);
                            const mouse_y: u32 = @trunc(mouse_pos.y);
                            const x: usize = mouse_x / tile_size;
                            const cord_y: usize = mouse_y / tile_size;
                            if (x < map_width and cord_y < map_height) {
                                const y = mouse_y / tile_size * map_height;
                                tile_map.tiles[x + y] = .{ .texture_id = level_editor.selected_texture, .kind = .wall };
                            }
                        }

                        if (rl.isKeyPressed(.s)) {
                            var buf: [2048]u8 = undefined;
                            var save_file = try Io.Dir.cwd().createFile(self.io, "map.zon", .{});
                            var file_writer = save_file.writer(self.io, &buf);
                            try std.zon.stringify.serialize(tile_map, .{}, &file_writer.interface);
                            try file_writer.flush();
                        }
                    }
                },
            }
        }

        // Update:
        {

            // --Screen--
            screen_width = rl.getScreenWidth();
            screen_height = rl.getScreenHeight();

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
                                if (e.pos.x < 0) e.pos.x = 0;
                                if (e.pos.y < 0) e.pos.y = 0;
                                log.info("{any}", .{e.pos});
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
                        self.camera.offset = .init(@floatFromInt(@divTrunc(screen_width, 2)), @floatFromInt(@divTrunc(screen_height, 2)));
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

                        rl.drawRectangleLinesEx(.init(0, 0, 1280, 720), 3, .white);
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
