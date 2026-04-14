const std = @import("std");

const Game = @import("Game.zig");

pub fn main(init: std.process.Init) !void {
    var game: Game = try .init(init.io, init.gpa, init.arena);
    defer game.deinit();
    try game.run();
}
