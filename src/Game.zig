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
const Level = @import("Level.zig");
const LevelEditor = @import("LevelEditor.zig");

io: Io,
gpa: Allocator,
arena: *heap.ArenaAllocator,
entity_manager: EntityManager,
guy_index: Entity.Index,
camera: rl.Camera2D,
state: State,
level_editor: LevelEditor,
level: ?Level,

pub const State = enum {
    level_editor,
    tile_editor,
    game,
};

const speed = 1000;
const bullet_speed = 2500.0;
var screen_width: i32 = 1280;
var screen_height: i32 = 720;
const scale_size = 300;

pub fn init(io: Io, gpa: Allocator, arena: *heap.ArenaAllocator) !Game {
    rl.initWindow(1280, 720, "topdown");
    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    var manager: EntityManager = try .init(gpa);
    const guy = try manager.appendKind(.guy);

    return .{
        .camera = .{
            .offset = .init(@floatFromInt(@divTrunc(screen_width, 2)), @floatFromInt(@divTrunc(screen_height, 2))),
            .target = manager.get(guy).pos,
            .zoom = 1,
            .rotation = 0,
        },
        .io = io,
        .gpa = gpa,
        .arena = arena,
        .entity_manager = manager,
        .guy_index = guy,
        .state = .game,
        .level_editor = .default,
        .level = null,
    };
}

pub fn deinit(self: *Game) void {
    self.entity_manager.deinit(self.gpa);
    self.level_editor.deinit();
    if (self.level) |*level| {
        level.deinit();
    }
    rl.closeWindow();
}

pub fn run(self: *Game) !void {
    while (!rl.windowShouldClose()) {
        defer _ = self.arena.reset(.retain_capacity);

        // Input:
        {
            const dt = rl.getFrameTime();

            // -- Global --
            // Dirty piece of code... The state switching should be cleaner.
            if (rl.isKeyPressed(.tab)) {
                switch (self.state) {
                    // From game to editor.
                    .game => {
                        if (self.level) |level| {
                            if (self.level_editor.level == null) {
                                try self.level_editor.loadLevelFromFile(self.io, self.gpa, level.path);
                            }
                        }
                        const guy = self.entity_manager.get(self.guy_index);
                        self.level_editor.camera_target = guy.pos;
                        self.state = .level_editor;
                    },
                    // From editor to game.
                    .level_editor => {
                        if (self.level) |*level| {
                            try level.reload(self.io);
                        }
                        self.state = .game;
                    },
                    else => {},
                }
            }

            if (self.state == .tile_editor or self.state == .level_editor) {
                if (rl.isKeyPressed(.e)) {
                    switch (self.state) {
                        .level_editor => {
                            const selected_tile_map = self.level_editor.getSelectedTileMap();
                            const level = self.level_editor.level.?;
                            const current_tile_set = selected_tile_map.getTileSetFromTileId(level.tile_set_map ,self.level_editor.selected_tile_id);
                            self.level_editor.tile_editor = try .init(current_tile_set);
                            self.level_editor.tile_editor.?.selected_tile = self.level_editor.selected_tile_id;
                            self.state = .tile_editor;
                        },
                        .tile_editor => {
                            self.level_editor.tile_editor.?.deinit();
                            self.state = .level_editor;
                        },
                        else => unreachable,
                    }
                }
            }

            switch (self.state) {
                .game => {
                    if (rl.isKeyPressed(.l)) {
                        if (self.level == null) {
                            self.level = Level.initFromFile(self.io, self.gpa, "map.json") catch |e| blk: {
                                log.err("{t}", .{e});
                                break :blk null;
                            };
                            log.info("Level loaded", .{});
                        }
                    }

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

                        _ = try self.entity_manager.append(bullet);
                        guy.shot_cooldown.start();
                    }
                },

                .level_editor => {
                    const level_editor = &self.level_editor;
                    if (rl.isKeyPressed(.n)) {
                        level_editor.deinit();
                        try level_editor.initLevelWithTileMap(self.gpa, "map.json", 100, 100);
                        try level_editor.addTileSet("wall_sheet.json", "./assets/wall_sheet.png", 64);
                        try level_editor.addTileSet("tileset_gray.json", "./assets/tileset_gray.png", 64);
                    }

                    if (rl.isKeyPressed(.t)) {
                        try level_editor.addTileMapLayer(100, 100);
                        log.info("TileMap created", .{});
                    }

                    //TODO: Clearly stupid. However, we roll for now...
                    if (rl.isKeyPressed(.x)) {
                        level_editor.selected_tile_map += 1;
                        try level_editor.addTileSet("TX_Tileset_Grass.json","./assets/TX_Tileset_Grass.png", 32);
                        level_editor.selected_tile_id = .new(1);
                    }

                    if (rl.isKeyPressed(.z)) {
                        level_editor.selected_tile_map -= 1;
                        level_editor.selected_tile_id = .new(1);
                    }

                    var dir: Vector2 = .zero();
                    if (rl.isKeyDown(.d)) {
                        dir.x = 1;
                    }
                    if (rl.isKeyDown(.a)) {
                        dir.x = -1;
                    }
                    if (rl.isKeyDown(.w)) {
                        dir.y = -1;
                    }
                    if (rl.isKeyDown(.s)) {
                        dir.y = 1;
                    }

                    level_editor.camera_target = .add(level_editor.camera_target, .scale(.normalize(dir), speed * dt));

                    if (level_editor.level) |level| {
                        const tile_map = level_editor.getSelectedTileMap();

                        // We do nothing if we have no tile_sets...
                        // GO ADD ONE FIRST!!1!
                        if (tile_map.tile_sets.len != 0) {
                            const selected_tile_set = tile_map.getTileSetFromTileId(level.tile_set_map, self.level_editor.selected_tile_id);
                            const first_tile_id = selected_tile_set.first_tile_id;
                            const map_width = tile_map.width;
                            const map_height = tile_map.height;

                            const tile_size = selected_tile_set.tile_size;
                            const tile_set_width = selected_tile_set.width;
                            const tile_count = selected_tile_set.tile_count;

                            //TODO: this doesn't work like it should. fix it!!!
                            if (rl.isKeyPressed(.j)) {
                                level_editor.selected_tile_id = .new(selected_tile_set.tile_count + 1);
                            }
                            if (rl.isKeyPressed(.k)) {
                                level_editor.selected_tile_id = .new(selected_tile_set.tile_count - 1);
                            }

                            const last_tile_id_in_tile_set: Level.TileId = .new(first_tile_id.get() + selected_tile_set.tile_count - 1);

                            if (rl.isKeyPressed(.right)) {
                                level_editor.selected_tile_id = .new(level_editor.selected_tile_id.get() + 1);
                                if (level_editor.selected_tile_id.get() > last_tile_id_in_tile_set.get()) level_editor.selected_tile_id = first_tile_id;
                            }

                            if (rl.isKeyPressed(.left)) {
                                level_editor.selected_tile_id = .new(level_editor.selected_tile_id.get() - 1);
                                if (level_editor.selected_tile_id.get() == first_tile_id.get() - 1) level_editor.selected_tile_id = last_tile_id_in_tile_set;
                            }

                            if (rl.isKeyPressed(.down)) {
                                level_editor.selected_tile_id = .new(level_editor.selected_tile_id.get() + tile_set_width);
                                if (level_editor.selected_tile_id.get() > last_tile_id_in_tile_set.get()) level_editor.selected_tile_id = .new(level_editor.selected_tile_id.get() - tile_count);
                            }

                            //TODO: Figure out a better way to handle it...
                            if (rl.isKeyPressed(.up)) {
                                if (level_editor.selected_tile_id.get() <= tile_set_width + first_tile_id.get() - 1)
                                    level_editor.selected_tile_id = .new(last_tile_id_in_tile_set.get() - (tile_set_width + first_tile_id.get() - 1 - level_editor.selected_tile_id.get()))
                                else
                                    level_editor.selected_tile_id = .new(level_editor.selected_tile_id.get() - tile_set_width);
                            }

                            //TODO: Investigate how to stop spamming in the same grid.
                            if (rl.isMouseButtonDown(.left)) {
                                const world_pos = rl.getScreenToWorld2D(rl.getMousePosition(), self.camera);
                                if (world_pos.x >= 0 and world_pos.y >= 0) {
                                    const mouse_x: u32 = @trunc(world_pos.x);
                                    const mouse_y: u32 = @trunc(world_pos.y);
                                    const gx = mouse_x / tile_size;
                                    const gy = mouse_y / tile_size;
                                    if (gx < map_width and gy < map_height) {
                                        const y = gy * map_width;
                                        tile_map.tiles[gx + y] = level_editor.selected_tile_id;
                                    }
                                }
                            }

                            if (rl.isKeyPressed(.enter)) {
                                try self.level_editor.saveLevel(self.io);
                            }
                        }
                    }
                },

                .tile_editor => {
                    if (self.level_editor.tile_editor) |*tile_editor| {
                        const pos = rl.getMousePosition();
                        const x: f32 = @floatFromInt(@divExact(screen_width, 2) - scale_size / 2);
                        const y: f32 = @floatFromInt(@divExact(screen_height, 2) - scale_size / 2);
                        const condition = (pos.x >= x and pos.x < x + scale_size) and (pos.y >= y and pos.y < y + scale_size);

                        if (rl.isMouseButtonPressed(.left)) {
                            if (condition) tile_editor.point = pos;
                        }

                        if (rl.isMouseButtonDown(.left)) {
                            tile_editor.release = pos;
                            if (pos.x < x) tile_editor.release.x = x;
                            if (pos.y < y) tile_editor.release.y = y;

                            if (pos.x > x + scale_size) tile_editor.release.x = x + scale_size;
                            if (pos.y > y + scale_size) tile_editor.release.y = y + scale_size;

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

                .level_editor => {
                    self.camera.target = self.level_editor.camera_target;
                },
                .tile_editor => {},
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

            if (self.state == .tile_editor) {
                if (self.level_editor.tile_editor) |tile_editor| {
                    {
                        const rect = tile_editor.tile_set.getSourceRect(tile_editor.selected_tile);

                        const dest: rl.Rectangle = .{
                            .width = scale_size,
                            .height = scale_size,
                            .x = @floatFromInt(@divExact(screen_width, 2) - scale_size / 2),
                            .y = @floatFromInt(@divExact(screen_height, 2) - scale_size / 2),
                        };

                        rl.drawTexturePro(tile_editor.texture, rect, dest, .zero(), 0, .white);
                        rl.drawCircleV(.init(@floatFromInt(@divExact(screen_width, 2)), @floatFromInt(@divExact(screen_height, 2))), 3, .white);
                    }

                    {
                        const rect_x = @min(tile_editor.point.x, tile_editor.release.x);
                        const rect_y = @min(tile_editor.point.y, tile_editor.release.y);

                        const rect_width = @abs(tile_editor.point.x - tile_editor.release.x);
                        const rect_height = @abs(tile_editor.point.y - tile_editor.release.y);

                        const rect = rl.Rectangle{
                            .x = rect_x,
                            .y = rect_y,
                            .width = rect_width,
                            .height = rect_height,
                        };

                        rl.drawCircleV(tile_editor.point, 5, .white);
                        rl.drawCircleV(tile_editor.release, 5, .white);

                        rl.drawRectangleLinesEx(rect, 3, .red);
                    }
                }
            } else {
                self.camera.begin();
                defer self.camera.end();
                if (self.level_editor.level) |level| {
                    const tile_map = self.level_editor.getSelectedTileMap();

                    //TODO: We might want to store tile_size on the tile_map and remove multiple tile sizes in a layer.
                    if (tile_map.tile_sets.len != 0) {
                        const tile_set = level.tile_set_map.get(tile_map.tile_sets[0].tile_set_path).?;
                        const rect: rl.Rectangle = .{
                            .x = 0,
                            .y = 0,
                            .width = @floatFromInt(tile_map.width * tile_set.tile_size),
                            .height = @floatFromInt(tile_map.height * tile_set.tile_size),
                        };
                        rl.drawRectangleLinesEx(rect, 3, .white);
                    }
                }

                if (self.state == .level_editor) {
                    self.level_editor.draw(self.camera);
                }

                {
                    self.camera.begin();
                    defer self.camera.end();

                    if (self.state == .game) {
                        if (self.level) |level| {
                            level.draw();
                        }
                    }

                    // -- entities --
                    for (self.entity_manager.entities.items) |*e| {
                        if (e.status != .alive) continue;
                        e.draw();
                    }
                }
            }

            // --- Worldspace ---
            {
                // --- Screen Space (UI) ---
                rl.drawFPS(10, 10);
            }
        }
    }
}
