const Level = @This();

const std = @import("std");
const Io = std.Io;

const log = std.log;

const Allocator = std.mem.Allocator;

const StringHashMap = std.StringHashMapUnmanaged;

const rl = @import("raylib");
const Vector2 = rl.Vector2;

arena: std.heap.ArenaAllocator,
textures: StringHashMap(rl.Texture2D),
tile_set_map: StringHashMap(TileSet),
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
    tile_sets: []LevelTileSet,
    // We count from 1. 0 is empty tile.
    tiles: []TileId,

    pub fn getTileSetFromTileId(self: TileMap, tile_set_map: StringHashMap(TileSet), tile_id: TileId) LevelTileSet {
        for (self.tile_sets) |tile_set| {
            const level_tile_set = tile_set_map.get(tile_set.tile_set_path).?;
            if (tile_id.get() >= tile_set.first_tile_id.get() and tile_id.get() < tile_set.first_tile_id.get() + level_tile_set.tile_count) return tile_set;
        }
        unreachable;
    }
};

pub const LevelTileSet = struct {
    first_tile_id: TileId,
    tile_set_path: []const u8,
};

pub const TileSet = struct {
    texture_path: [:0]const u8,
    tile_size: u32,
    width: u32,
    height: u32,
    tile_count: u32,

    pub fn init(texture: rl.Texture2D, texture_path: [:0]const u8, tile_size: u32) TileSet {
        const width: u32 = @intCast(texture.width);
        const height: u32 = @intCast(texture.height);
        return .{
            .texture_path = texture_path,
            .tile_size = tile_size,
            .width = width / tile_size,
            .height = height / tile_size,
            .tile_count = (width / tile_size) * (height / tile_size),
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
        .tile_set_map = .empty,
        .path = save_path,
    };
}

pub fn initFromFile(io: Io, gpa: Allocator, save_path: [:0]const u8) !Level {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    errdefer arena.deinit();

    const content = try Io.Dir.cwd().readFileAllocOptions(io, save_path, arena.allocator(), .unlimited, .of(u8), 0);
    const tile_map_layers = try std.json.parseFromSliceLeaky([]TileMap, arena.allocator(), content, .{});

    var textures: StringHashMap(rl.Texture2D) = .empty;
    var tile_set_map: StringHashMap(TileSet) = .empty;
    for (tile_map_layers) |tile_map| {
        for (tile_map.tile_sets) |tile_set| {
            const tile_set_file = try Io.Dir.cwd().readFileAllocOptions(io, tile_set.tile_set_path, arena.allocator(), .unlimited, .of(u8), 0);
            const tile_set_json = try std.json.parseFromSliceLeaky(TileSet, arena.allocator(), tile_set_file, .{});
            _ = try tile_set_map.getOrPutValue(arena.allocator(), tile_set.tile_set_path, tile_set_json);

            const texture: rl.Texture2D = try .init(tile_set_json.texture_path);
            _ = try textures.getOrPutValue(arena.allocator(), tile_set_json.texture_path, texture);
        }
    }

    return .{
        .arena = arena,
        .path = save_path,
        .tile_map_layers = tile_map_layers,
        .textures = textures,
        .tile_set_map = tile_set_map,
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
    var tile_set_map: StringHashMap(TileSet) = .empty;
    for (tile_map_layers) |tile_map| {
        for (tile_map.tile_sets) |tile_set| {
            const tile_set_file = try Io.Dir.cwd().readFileAllocOptions(io, tile_set.tile_set_path, self.arena.allocator(), .unlimited, .of(u8), 0);
            const tile_set_json = try std.json.parseFromSliceLeaky(TileSet, self.arena.allocator(), tile_set_file, .{});
            _ = try tile_set_map.getOrPutValue(self.arena.allocator(), tile_set.tile_set_path, tile_set_json);

            const texture: rl.Texture2D = try .init(tile_set_json.texture_path);
            _ = try textures.getOrPutValue(self.arena.allocator(), tile_set.tile_set_path, texture);
        }
    }

    self.tile_map_layers = tile_map_layers;
    self.textures = textures;
    self.tile_set_map = tile_set_map;
}

pub fn deinit(self: *Level) void {
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| texture.unload();
    self.arena.deinit();
}

pub fn getRelativeTileIdToLevelTileSet(level_tile_set: LevelTileSet, id: TileId) TileId {
    const first_tile_id = level_tile_set.first_tile_id;
    return .new(id.get() - first_tile_id.get());
}

pub fn getSourceRect(tile_set: TileSet, tile_id: TileId) rl.Rectangle {
    const col = tile_id.get() % tile_set.width;
    const row = tile_id.get() / tile_set.width;

    return .{
        .x = @floatFromInt(col * tile_set.tile_size),
        .y = @floatFromInt(row * tile_set.tile_size),
        .width = @floatFromInt(tile_set.tile_size),
        .height = @floatFromInt(tile_set.tile_size),
    };
}

pub fn draw(self: Level) void {
    for (self.tile_map_layers) |tile_map| {
        for (tile_map.tiles, 0..) |tile_id, i| {
            if (tile_id.get() == 0) continue;
            const level_tile_set = tile_map.getTileSetFromTileId(self.tile_set_map, tile_id);
            const tile_set = self.tile_set_map.get(level_tile_set.tile_set_path).?;

            const texture = self.textures.get(tile_set.texture_path).?;
            const tile_size = tile_set.tile_size;

            const pos: Vector2 = .init(@floatFromInt((i % tile_map.width) * tile_size), @floatFromInt((i / tile_map.width) * tile_set.tile_size));


            const relative_tile_id = Level.getRelativeTileIdToLevelTileSet(level_tile_set, tile_id);
            const texture_rectid = Level.getSourceRect(tile_set, relative_tile_id);
            texture.drawRec(texture_rectid, pos, .white);
        }
    }
}
