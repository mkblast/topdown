const rl = @import("raylib");

world_map: [map_width * map_height]Tile = @splat(.{}),
tile_set: TileSet,

const LevelEditor = @This();

const map_width = 64;
const map_height = 64;
const tile_size = 32.0;

const tile_set_path = "./assets/wall_sheet.png";

pub const Kind = enum {
    empty,
    floor,
    wall,
};

pub const Tile = struct {
    texture_id: usize = 0,
    kind: Kind = .empty,
};

const TileSet = struct {
    texture: rl.Texture2D,
    tile_size: f32,
    columns: u32,
    rows: u32,

    pub fn init(path: [:0]const u8, size: f32) !TileSet {
        const tex: rl.Texture2D = try .init(path);
        return .{
            .texture = tex,
            .tile_size = size,
            .columns = @intCast(@divTrunc(tex.width, @as(i32, @intFromFloat(size)))),
            .rows = @intCast(@divTrunc(tex.height, @as(i32, @intFromFloat(size)))),
        };
    }

    pub fn getSourceRect(self: TileSet, id: usize) rl.Rectangle {
        const col: f32 = @floatFromInt(id % self.columns);
        const row: f32 = @floatFromInt(id / self.columns);

        return .{
            .x = col * self.tile_size,
            .y = row * self.tile_size,
            .width = self.tile_size,
            .height = self.tile_size,
        };
    }
};

pub fn init() !LevelEditor {
    return .{
        .tile_set = try .init(tile_set_path, tile_size),
    };
}
