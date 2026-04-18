const LevelEditor = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const rl = @import("raylib");
const Game = @import("Game.zig");

const Vector2 = rl.Vector2;

tile_map: ?TileMap = null,
tile_set_showen: bool = true,
selected_texture: u32 = 0,

pub const Kind = enum {
    empty,
    floor,
    wall,
};

pub const Tile = struct {
    texture_id: u32,
    kind: Kind,

    const default: Tile = .{ .kind = .empty, .texture_id = 0 };
};

const TileMap = struct {
    tile_set: TileSet,
    width: u32,
    height: u32,
    tiles: []Tile,

    fn init(gpa: Allocator, path: [:0]const u8, tile_size: u32, width: u32, height: u32) !TileMap {
        const tiles = try gpa.alloc(Tile, @intCast(width * height));
        @memset(tiles, .default);
        return .{
            .tile_set = try .init(gpa, path, tile_size),
            .width = width,
            .height = height,
            .tiles = tiles,
        };
    }

    fn deinit(self: *TileMap, gpa: Allocator) void {
        gpa.free(self.tiles);
    }
};

const TileSet = struct {
    path: []const u8,
    tile_size: u32,
    width: u32,
    height: u32,

    pub fn init(gpa: Allocator, path: [:0]const u8, size: u32) !TileSet {
        const tex: rl.Texture2D = try .init(path);
        try Game.textures.put(gpa, path, tex);

        const width: u32 = @intCast(tex.width);
        const height: u32 = @intCast(tex.height);
        return .{
            .path = path,
            .tile_size = size,
            .width = width / size,
            .height = height / size,
        };
    }

    pub fn getSourceRect(self: TileSet, id: u32) rl.Rectangle {
        const col = id % self.width;
        const row = id / self.width;

        return .{
            .x = @floatFromInt(col * self.tile_size),
            .y = @floatFromInt(row * self.tile_size),
            .width = @floatFromInt(self.tile_size),
            .height = @floatFromInt(self.tile_size),
        };
    }
};

pub fn init(gpa: Allocator, path: [:0]const u8, tile_size: u32, width: u32, height: u32) !LevelEditor {
    return .{
        .tile_map = try .init(gpa, path, tile_size, width, height),
    };
}

pub fn deinit(self: *LevelEditor, gpa: Allocator) void {
    if (self.tile_map) |*tile_map| {
        tile_map.deinit(gpa);
    }
}

pub fn draw(self: LevelEditor) void {
    if (self.tile_map) |tile_map| {
        const tile_size = tile_map.tile_set.tile_size;
        const texture = Game.textures.get(tile_map.tile_set.path).?;

        for (tile_map.tiles, 0..) |tile, i| {
            if (tile.kind == .empty) continue;
            const pos: Vector2 = .init(@floatFromInt((i % tile_map.width) * tile_size), @floatFromInt((i / tile_map.width) * tile_map.tile_set.tile_size));
            const texture_rectid = tile_map.tile_set.getSourceRect(tile.texture_id);
            texture.drawRec(texture_rectid, pos, .white);
        }

        const mouse_pos = rl.getMousePosition();
        const mouse_x: u32 = @trunc(mouse_pos.x);
        const mouse_y: u32 = @trunc(mouse_pos.y);
        const hovered: rl.Rectangle = .{
            .x = @floatFromInt(mouse_x / tile_size * tile_size),
            .y = @floatFromInt(mouse_y / tile_size * tile_size),
            .width = @floatFromInt(tile_size),
            .height = @floatFromInt(tile_size),
        };

        rl.drawRectangleLinesEx(hovered, 3, .sky_blue);

        if (self.tile_set_showen) {
            const rect = tile_map.tile_set.getSourceRect(self.selected_texture);
            rl.drawTexture(texture, 0, 0, .white);
            rl.drawRectangleLinesEx(rect, 3, .blue);
        }
    }
}
