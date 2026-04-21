const Level = @This();

const std = @import("std");
const Io = std.Io;

const log = std.log;

const Allocator = std.mem.Allocator;

const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMapUnmanaged;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

arena: std.heap.ArenaAllocator,
textures: StringHashMap(rl.Texture2D),
tile_map_layers: []TileMap,
path: [:0]const u8,

pub const TileId = enum(u32) {
    _,

    pub fn new(idx: usize) TileId {
        return @enumFromInt(idx);
    }

    pub fn get(self: TileId) u32 {
        return @intFromEnum(self);
    }
};

pub const TileMap = struct {
    width: u32,
    height: u32,
    tile_sets: []TileSet,
    // We count from 1. 0 is empty tile.
    tiles: []TileId,

    pub fn getTileSetFromTileId(self: TileMap, tile_id: TileId) TileSet {
        for (self.tile_sets) |tile_set| {
            if (tile_id.get() >= tile_set.first_tile_id.get() and tile_id.get() < tile_set.first_tile_id.get() + tile_set.tile_count) return tile_set;
        }
        unreachable;
    }
};

pub const TileSet = struct {
    path: [:0]const u8,
    tile_size: u32,
    width: u32,
    height: u32,
    first_tile_id: TileId,
    tile_count: u32,

    pub fn init(texture: rl.Texture2D, path: [:0]const u8, tile_size: u32, first_tile_id: TileId) TileSet {
        const width: u32 = @intCast(texture.width);
        const height: u32 = @intCast(texture.height);
        return .{
            .path = path,
            .tile_size = tile_size,
            .width = width / tile_size,
            .height = height / tile_size,
            .first_tile_id = first_tile_id,
            .tile_count = (width / tile_size) * (height / tile_size),
        };
    }

    pub fn getSourceRect(self: TileSet, id: TileId) rl.Rectangle {
        const tile_id = id.get() - self.first_tile_id.get();
        const col = tile_id % self.width;
        const row = tile_id / self.width;

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

    const tiles = try arena.allocator().alloc(TileId, width * height);
    @memset(tiles, .new(0));

    const tile_map_layers = try arena.allocator().alloc(TileMap, 1);
    tile_map_layers[0] = .{
        .width = width,
        .height = height,
        .tile_sets = &.{},
        .tiles = tiles,
    };

    return .{
        .arena = arena,
        .tile_map_layers = tile_map_layers,
        .textures = .empty,
        .path = save_path,
    };
}

pub fn initFromFile(io: Io, gpa: Allocator, save_path: [:0]const u8) !Level {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    errdefer arena.deinit();

    const content = try Io.Dir.cwd().readFileAllocOptions(io, save_path, arena.allocator(), .unlimited, .of(u8), 0);
    const tile_map_layers = try std.json.parseFromSliceLeaky([]TileMap, arena.allocator(), content, .{});

    var textures: StringHashMap(rl.Texture2D) = .empty;
    for (tile_map_layers) |tile_map| {
        for (tile_map.tile_sets) |tile_set| {
            const texture: rl.Texture2D = try .init(tile_set.path);
            _ = try textures.getOrPutValue(arena.allocator(), tile_set.path, texture);
        }
    }

    return .{
        .arena = arena,
        .path = save_path,
        .tile_map_layers = tile_map_layers,
        .textures = textures,
    };
}

pub fn reload(self: *Level, io: Io) !void {
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| texture.unload();
    _ = self.arena.reset(.retain_capacity);
    errdefer self.arena.deinit();

    const content = try Io.Dir.cwd().readFileAllocOptions(io, self.path, self.arena.allocator(), .unlimited, .of(u8), 0);
    const tile_map_layers = try std.json.parseFromSliceLeaky([]TileMap, self.arena.allocator(), content, .{});

    var textures: StringHashMap(rl.Texture2D) = .empty;
    for (tile_map_layers) |tile_map| {
        for (tile_map.tile_sets) |tile_set| {
            const texture: rl.Texture2D = try .init(tile_set.path);
            _ = try textures.getOrPutValue(self.arena.allocator(), tile_set.path, texture);
        }
    }

    self.tile_map_layers = tile_map_layers;
    self.textures = textures;
}

pub fn deinit(self: *Level) void {
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| texture.unload();
    self.arena.deinit();
}

pub fn draw(self: Level) void {
    for (self.tile_map_layers) |tile_map| {
        for (tile_map.tiles, 0..) |tile_id, i| {
            if (tile_id.get() == 0) continue;
            const tile_set = tile_map.getTileSetFromTileId(tile_id);

            const texture = self.textures.get(tile_set.path).?;
            const tile_size = tile_set.tile_size;

            const pos: Vector2 = .init(@floatFromInt((i % tile_map.width) * tile_size), @floatFromInt((i / tile_map.width) * tile_set.tile_size));
            const texture_rectid = tile_set.getSourceRect(tile_id);
            texture.drawRec(texture_rectid, pos, .white);
        }
    }
}
