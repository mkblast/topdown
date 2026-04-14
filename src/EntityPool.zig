const std = @import("std");
const Allocator = std.mem.Allocator;

const ArrayList = std.ArrayList;

const Entity = @import("Entity.zig");
const Kind = Entity.Kind;

pool: ArrayList(Entity),
empty_slots: ArrayList(Entity.Index),

const EntityPool = @This();

const max_capacity = 1000;
var pool_array: [max_capacity]Entity = undefined;
var empty_slots_array: [max_capacity]Entity.Index = undefined;

pub fn init() EntityPool {
    return .{
        .pool = .initBuffer(&pool_array),
        .empty_slots = .initBuffer(&empty_slots_array),
    };
}

pub fn reserve(self: *EntityPool, kind: Kind) !Entity.Index {
    const e: Entity = .{ .kind = kind };

    if (self.empty_slots.getLastOrNull()) |slot| {
        self.pool.items[slot.get()] = e;
        return slot;
    }

    try self.pool.appendBounded(e);
    return .new(self.pool.items.len - 1);
}

pub fn appened(self: *EntityPool, e: Entity) !Entity.Index {
    if (self.empty_slots.pop()) |slot| {
        self.pool.items[slot.get()] = e;
        return slot;
    }

    try self.pool.appendBounded(e);
    return .new(self.pool.items.len - 1);
}

pub fn get(self: EntityPool, idx: Entity.Index) *Entity {
    return &self.pool.items[idx.get()];
}

pub fn remove(self: *EntityPool, idx: Entity.Index) !void {
    try self.empty_slots.appendBounded(idx);
}

pub fn findMany(self: EntityPool, arena: Allocator, kind: Kind) ![]Entity.Index {
    var arr: ArrayList(Entity.Index) = try .initCapacity(arena, self.pool.items.len);
    for (self.pool.items, 0..) |e, i| {
        if (e.kind == kind) try arr.append(arena, .new(i));
    }

    return arr.toOwnedSlice(arena);
}
