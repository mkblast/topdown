const EntityManager = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const ArrayList = std.ArrayList;

const Entity = @import("Entity.zig");
const Index = Entity.Index;
const Kind = Entity.Kind;

entities: ArrayList(Entity),
empty_slots: ArrayList(Entity.Index),

const max_capacity = 1000;

pub fn init(gpa: Allocator) !EntityManager {
    return .{
        .entities = try .initCapacity(gpa, max_capacity),
        .empty_slots = try .initCapacity(gpa, max_capacity),
    };
}

pub fn deinit(manager: *EntityManager, gpa: Allocator) void {
    manager.entities.deinit(gpa);
    manager.empty_slots.deinit(gpa);
}

pub fn reserve(manager: *EntityManager, kind: Kind) Index {
    const e: Entity = .{ .kind = kind };

    if (manager.empty_slots.getLastOrNull()) |slot| {
        manager.entities.items[slot.get()] = e;
        return slot;
    }

    manager.entities.appendBounded(e) catch @panic("OOM");
    return .new(manager.entities.items.len - 1);
}

pub fn appened(manager: *EntityManager, e: Entity) Index {
    if (manager.empty_slots.pop()) |slot| {
        manager.entities.items[slot.get()] = e;
        return slot;
    }

    manager.entities.appendBounded(e) catch @panic("OOM");
    return .new(manager.entities.items.len - 1);
}

pub fn get(manager: EntityManager, idx: Entity.Index) Entity {
    return manager.entities.items[idx.get()];
}

pub fn getPtr(manager: EntityManager, idx: Entity.Index) *Entity {
    return &manager.entities.items[idx.get()];
}

pub fn remove(manager: *EntityManager, idx: Entity.Index) void {
    manager.empty_slots.appendBounded(idx) catch @panic("OOM");
}

pub fn findMany(manager: EntityManager, arena: Allocator, kind: Kind) ![]Index {
    var arr: ArrayList(Entity.Index) = .empty;
    for (manager.entities.items, 0..) |e, i| {
        if (e.kind == kind) try arr.append(arena, .new(i));
    }

    return arr.toOwnedSlice(arena);
}
