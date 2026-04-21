const LevelEditor = @This();

const std = @import("std");
const Io = std.Io;

const log = std.log;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const rl = @import("raylib");
const Game = @import("Game.zig");

const Level = @import("Level.zig");
const TileSet = Level.TileSet;
const TileId = Level.TileId;

const Vector2 = rl.Vector2;

level: ?Level,
tile_set_showen: bool,
selected_tile_id: TileId,
selected_tile_map: usize,
camera_target: Vector2,

pub const default: LevelEditor = .{
    .level = null,
    .tile_set_showen = true,
    .selected_tile_id = .new(1),
    .camera_target = .zero(),
    .selected_tile_map = 0,
};

pub fn initLevelWithTileMap(self: *LevelEditor, gpa: Allocator, save_path: [:0]const u8, width: u32, height: u32) !void {
    self.level = try .init(gpa, save_path, width, height);
}

pub fn loadLevelFromFile(self: *LevelEditor, io: Io, gpa: Allocator, save_path: [:0]const u8) !void {
    self.level = try .initFromFile(io, gpa, save_path);
}

pub fn addTileMapLayer(self: *LevelEditor, width: u32, height: u32) !void {
    if (self.level) |*level| {
        const arena = level.arena.allocator();

        const tiles = try arena.alloc(TileId, width * height);
        @memset(tiles, .new(0));

        const old_len = level.tile_map_layers.len;
        const new_tile_map_layers = try arena.realloc(level.tile_map_layers, old_len + 1);
        new_tile_map_layers[old_len] = .{
            .width = width,
            .height = height,
            .tile_sets = &.{},
            .tiles = tiles,
        };
        level.tile_map_layers = new_tile_map_layers;
    }
}

pub fn addTileSet(self: *LevelEditor, tile_set_path: [:0]const u8, tile_size: u32) !void {
    if (self.level) |*level| {
        const arena = level.arena.allocator();

        const tile_map = &level.tile_map_layers[self.selected_tile_map];

        const texture: rl.Texture2D = try .init(tile_set_path);
        try level.textures.put(arena, tile_set_path, texture);

        const first_tile_id: TileId = blk: {
            if (tile_map.tile_sets.len == 0) break :blk .new(1);

            const last_tile_set = tile_map.tile_sets[tile_map.tile_sets.len - 1];
            break :blk .new(last_tile_set.tile_count + 1);
        };
        const old_len = tile_map.tile_sets.len;
        tile_map.tile_sets = try arena.realloc(tile_map.tile_sets, old_len + 1);
        tile_map.tile_sets[old_len] = .init(texture, tile_set_path, tile_size, first_tile_id);
    }
}

pub fn saveLevel(self: LevelEditor, io: Io) !void {
    if (self.level) |level| {
        var buf: [2048]u8 = undefined;
        var save_file = try Io.Dir.cwd().createFile(io, level.path, .{});
        var file_writer = save_file.writer(io, &buf);
        const fmt = std.json.fmt(level.tile_map_layers, .{});
        try file_writer.interface.print("{f}", .{fmt});
        try file_writer.flush();
        log.info("Map Saved", .{});
    }
}

pub fn reload(self: *LevelEditor, io: Io) !void {
    if (self.level) |*level| {
        try level.reload(io);
    }
}

pub fn deinit(self: *LevelEditor) void {
    if (self.level) |*level| {
        level.deinit();
    }
}

pub fn draw(self: LevelEditor, camera: rl.Camera2D) void {
    if (self.level) |level| {
        const tile_map = level.tile_map_layers[self.selected_tile_map];
        if (tile_map.tile_sets.len != 0) {
            {
                camera.begin();
                defer camera.end();

                level.draw();

                const tile_set = tile_map.getTileSetFromTileId(self.selected_tile_id);
                const tile_size = tile_set.tile_size;
                const mouse_pos = rl.getScreenToWorld2D(rl.getMousePosition(), camera);
                if (mouse_pos.x >= 0 and mouse_pos.y >= 0) {
                    const mouse_x: u32 = @trunc(mouse_pos.x);
                    const mouse_y: u32 = @trunc(mouse_pos.y);
                    const hovered: rl.Rectangle = .{
                        .x = @floatFromInt(mouse_x / tile_size * tile_size),
                        .y = @floatFromInt(mouse_y / tile_size * tile_size),
                        .width = @floatFromInt(tile_size),
                        .height = @floatFromInt(tile_size),
                    };

                    rl.drawRectangleLinesEx(hovered, 3, .sky_blue);
                }
            }

            if (self.tile_set_showen) {
                const tile_set = tile_map.getTileSetFromTileId(self.selected_tile_id);
                const texture = level.textures.get(tile_set.path).?;
                const rect = tile_set.getSourceRect(self.selected_tile_id);
                rl.drawTexture(texture, 0, 0, .white);
                rl.drawRectangleLinesEx(rect, 3, .blue);
            }
        }
    }
}
