const std = @import("std");

const Game = @import("Game.zig");

pub fn main(init: std.process.Init) !void {
    var game: Game = try .init(init.io, init.gpa);
    try game.run();
    game.deinit();
}
