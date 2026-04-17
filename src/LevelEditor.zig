const LevelEditor = @This();

const std = @import("std");
const rl = @import("raylib");

const Vector2 = rl.Vector2;

world_map: [map_width * map_height]Tile = @splat(.{}),
tile_set: TileSet,
tile_set_showen: bool = true,
selected_texture: u32 = 0,

pub const map_width = 18;
pub const map_height = 18;

const tile_set_path = "./assets/wall_sheet.png";

pub const Kind = enum {
    empty,
    floor,
    wall,
};

pub const Tile = struct {
    texture_id: u32 = 0,
    kind: Kind = .empty,
};

const TileSet = struct {
    texture: rl.Texture2D,
    tile_size: u32,
    width: u32,
    height: u32,

    pub fn init(path: [:0]const u8, size: u32) !TileSet {
        const tex: rl.Texture2D = try .init(path);
        const width: u32 = @intCast(tex.width);
        const height: u32 = @intCast(tex.height);
        return .{
            .texture = tex,
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

pub fn init() !LevelEditor {
    return .{
        .tile_set = try .init(tile_set_path, 64),
    };
}

pub fn draw(self: LevelEditor) void {
    const tile_size = self.tile_set.tile_size;

    for (self.world_map, 0..) |tile, i| {
        if (tile.kind == .empty) continue;
        const pos: Vector2 = .init(@floatFromInt((i % map_width) * tile_size), @floatFromInt((i / map_width) * self.tile_set.tile_size));
        const texture = self.tile_set.texture;
        const texture_rectid = self.tile_set.getSourceRect(tile.texture_id);
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
        const rect = self.tile_set.getSourceRect(self.selected_texture);
        rl.drawTexture(self.tile_set.texture, 0, 0, .white);
        rl.drawRectangleLinesEx(rect, 3, .blue);
    }
}
