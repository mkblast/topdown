const Level = @This();

const std = @import("std");
const Io = std.Io;

const Allocator = std.mem.Allocator;

const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMapUnmanaged;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

arena: std.heap.ArenaAllocator,
textures: StringHashMap(rl.Texture2D),
tile_map: TileMap,
path: [:0]const u8,

pub const Kind = enum {
    empty,
    floor,
    wall,
};

pub const Tile = struct {
    texture_id: u32,
    tile_set_id: u32,
    kind: Kind,

    const default: Tile = .{ .kind = .empty, .texture_id = 0, .tile_set_id = 0 };
};

pub const TileMap = struct {
    width: u32,
    height: u32,
    tile_sets: []TileSet,
    tiles: []Tile,
};

pub const TileSet = struct {
    path: [:0]const u8,
    tile_size: u32,
    width: u32,
    height: u32,

    pub fn init(texture: rl.Texture2D, path: [:0]const u8, tile_size: u32) TileSet {
        const width: u32 = @intCast(texture.width);
        const height: u32 = @intCast(texture.height);
        return .{
            .path = path,
            .tile_size = tile_size,
            .width = width / tile_size,
            .height = height / tile_size,
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

pub fn init(gpa: Allocator, save_path: [:0]const u8, width: u32, height: u32) !Level {
    var arena: std.heap.ArenaAllocator = .init(gpa);

    const tiles = try arena.allocator().alloc(Tile, width * height);
    @memset(tiles, .default);

    const tile_map: TileMap = .{
        .width = width,
        .height = height,
        .tile_sets = &.{},
        .tiles = tiles,
    };

    return .{
        .arena = arena,
        .tile_map = tile_map,
        .textures = .empty,
        .path = save_path,
    };
}

pub fn initFromFile(io: Io, gpa: Allocator, save_path: [:0]const u8) !Level {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    errdefer arena.deinit();

    const content = try Io.Dir.cwd().readFileAllocOptions(io, save_path, arena.allocator(), .unlimited, .of(u8), 0);
    const tile_map = try std.zon.parse.fromSliceAlloc(TileMap, arena.allocator(), content, null, .{});

    var textures: StringHashMap(rl.Texture2D) = .empty;
    for (tile_map.tile_sets) |tile_set| {
        const texture: rl.Texture2D = try .init(tile_set.path);
        _ = try textures.getOrPutValue(arena.allocator(), tile_set.path, texture);
    }

    return .{
        .arena = arena,
        .path = save_path,
        .tile_map = tile_map,
        .textures = textures,
    };
}

pub fn reload(self: *Level, io: Io) !void {
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| texture.unload();
    _ = self.arena.reset(.retain_capacity);
    errdefer self.arena.deinit();

    const content = try Io.Dir.cwd().readFileAllocOptions(io, self.path, self.arena.allocator(), .unlimited, .of(u8), 0);
    const tile_map = try std.zon.parse.fromSliceAlloc(TileMap, self.arena.allocator(), content, null, .{});

    var textures: StringHashMap(rl.Texture2D) = .empty;
    for (tile_map.tile_sets) |tile_set| {
        const texture: rl.Texture2D = try .init(tile_set.path);
        _ = try textures.getOrPutValue(self.arena.allocator(), tile_set.path, texture);
    }

    self.tile_map = tile_map;
    self.textures = textures;
}

pub fn deinit(self: *Level) void {
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| texture.unload();
    self.arena.deinit();
}

pub fn draw(self: Level) void {
    for (self.tile_map.tiles, 0..) |tile, i| {
        if (tile.kind == .empty) continue;
        const tile_set = self.tile_map.tile_sets[tile.tile_set_id];

        const texture = self.textures.get(tile_set.path).?;
        const tile_size = tile_set.tile_size;

        const pos: Vector2 = .init(@floatFromInt((i % self.tile_map.width) * tile_size), @floatFromInt((i / self.tile_map.width) * tile_set.tile_size));
        const texture_rectid = tile_set.getSourceRect(tile.texture_id);
        texture.drawRec(texture_rectid, pos, .white);
    }
}
