const LevelEditor = @This();

const std = @import("std");
const Io = std.Io;

const Allocator = std.mem.Allocator;

const rl = @import("raylib");
const Game = @import("Game.zig");

const Vector2 = rl.Vector2;

arena: std.heap.ArenaAllocator,
tile_map: ?TileMap = null,
tile_set_showen: bool = true,
selected_texture: u32 = 0,
camera_target: Vector2 = .zero(),

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

pub const TileMap = struct {
    tile_set: TileSet,
    width: u32,
    height: u32,
    tiles: []Tile,

    fn init(gpa: Allocator, path: [:0]const u8, tile_size: u32, width: u32, height: u32) !TileMap {
        const tiles = try gpa.alloc(Tile, width * height);
        @memset(tiles, .default);
        return .{
            .tile_set = try .init(path, tile_size),
            .width = width,
            .height = height,
            .tiles = tiles,
        };
    }

    pub fn initFromFile(io: Io, gpa: Allocator, arena: Allocator, path: []const u8) !TileMap {
        const content = try Io.Dir.cwd().readFileAllocOptions(io, path, arena, .unlimited, .of(u8), 0);
        const zon = try std.zon.parse.fromSliceAlloc(TileMap, gpa, content, null, .{});
        return zon;
    }

    pub fn deinit(self: *TileMap, gpa: Allocator) void {
        gpa.free(self.tiles);
    }

    pub fn draw(self: TileMap) void {
        const texture = Game.textures.get(self.tile_set.path).?;
        const tile_size = self.tile_set.tile_size;

        for (self.tiles, 0..) |tile, i| {
            if (tile.kind == .empty) continue;
            const pos: Vector2 = .init(@floatFromInt((i % self.width) * tile_size), @floatFromInt((i / self.width) * self.tile_set.tile_size));
            const texture_rectid = self.tile_set.getSourceRect(tile.texture_id);
            texture.drawRec(texture_rectid, pos, .white);
        }
    }
};

pub const TileSet = struct {
    path: []const u8,
    tile_size: u32,
    width: u32,
    height: u32,

    pub fn init(path: [:0]const u8, size: u32) !TileSet {
        const tex: rl.Texture2D = try .init(path);
        try Game.textures.put(path, tex);

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
    var leve_editor: LevelEditor = .{
        .arena = .init(gpa),
    };
    leve_editor.tile_map = try .init(leve_editor.arena.allocator(), path, tile_size, width, height);
    return leve_editor;
}

pub fn initFromFile(io: Io, gpa: Allocator, path: []const u8) !LevelEditor {
    var leve_editor: LevelEditor = .{
        .arena = .init(gpa),
    };
    const arena = leve_editor.arena.allocator();
    leve_editor.tile_map = try .initFromFile(io, arena, arena, path);
    return leve_editor;
}

pub fn reload(self: *LevelEditor, io: Io, path: []const u8) !void {
    _ = self.arena.reset(.retain_capacity);
    const arena = self.arena.allocator();
    self.tile_map = try .initFromFile(io, arena, arena, path);
}

pub fn deinit(self: *LevelEditor) void {
    self.arena.deinit();
}

pub fn draw(self: LevelEditor, camera: rl.Camera2D) void {
    if (self.tile_map) |tile_map| {
        {
            camera.begin();
            defer camera.end();

            tile_map.draw();

            const tile_size = tile_map.tile_set.tile_size;
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
            const texture = Game.textures.get(tile_map.tile_set.path).?;
            const rect = tile_map.tile_set.getSourceRect(self.selected_texture);
            rl.drawTexture(texture, 0, 0, .white);
            rl.drawRectangleLinesEx(rect, 3, .blue);
        }
    }
}
