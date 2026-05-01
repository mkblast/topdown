const EntityManager = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const ArrayList = std.ArrayList;

const Entity = @import("Entity.zig");
const Index = Entity.Index;
const Kind = Entity.Kind;

entities: ArrayList(Entity),
empty_slots: ArrayList(Index),

const max_capacity = 1000;

pub fn init(gpa: Allocator) !EntityManager {
    return .{
        .entities = try .initCapacity(gpa, max_capacity),
        .empty_slots = try .initCapacity(gpa, max_capacity),
    };
}

pub fn deinit(self: *EntityManager, gpa: Allocator) void {
    self.entities.deinit(gpa);
    self.empty_slots.deinit(gpa);
}

pub fn appendKind(self: *EntityManager, kind: Kind) !Index {
    const e: Entity = .{ .kind = kind };

    if (self.empty_slots.pop()) |slot| {
        self.entities.items[slot.get()] = e;
        return slot;
    }

    try self.entities.appendBounded(e);
    return .new(self.entities.items.len - 1);
}

pub fn append(self: *EntityManager, e: Entity) !Index {
    if (self.empty_slots.pop()) |slot| {
        self.entities.items[slot.get()] = e;
        return slot;
    }

    try self.entities.appendBounded(e);
    return .new(self.entities.items.len - 1);
}

pub fn get(self: EntityManager, idx: Index) *Entity {
    return &self.entities.items[idx.get()];
}

pub fn remove(self: *EntityManager, idx: Index) !void {
    try self.empty_slots.appendBounded(idx);
}

pub fn findMany(self: EntityManager, arena: Allocator, kind: Kind) ![]Index {
    var arr: ArrayList(Index) = try .initCapacity(arena, self.entities.items.len);
    for (self.entities.items, 0..) |e, i| {
        if (e.kind == kind) try arr.append(arena, .new(i));
    }

    return arr.toOwnedSlice(arena);
}
