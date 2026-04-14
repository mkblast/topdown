const Timer = @This();

duration: f32,
remaining: f32,

pub fn init(duration: f32) Timer {
    return .{
        .duration = duration,
        .remaining = 0,
    };
}

pub fn initStart(duration: f32) Timer {
    return .{
        .duration = duration,
        .remaining = duration,
    };
}

pub fn update(self: *Timer, dt: f32) void {
    if (self.remaining > 0) {
        self.remaining -= dt;
        if (self.remaining < 0) self.remaining = 0;
    }
}

pub fn start(self: *Timer) void {
    self.remaining = self.duration;
}

pub fn isDone(self: Timer) bool {
    return self.remaining <= 0;
}

pub fn progress(self: Timer) f32 {
    if (self.duration == 0) return 1.0;
    return 1.0 - (self.remaining / self.duration);
}
