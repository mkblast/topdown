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

pub fn update(timer: *Timer, dt: f32) void {
    if (timer.remaining > 0) {
        timer.remaining -= dt;
        if (timer.remaining < 0) timer.remaining = 0;
    }
}

pub fn start(timer: *Timer) void {
    timer.remaining = timer.duration;
}

pub fn isDone(timer: Timer) bool {
    return timer.remaining <= 0;
}

pub fn progress(timer: Timer) f32 {
    if (timer.duration == 0) return 1.0;
    const p = 1.0 - (timer.remaining / timer.duration);
    return @max(0.0, @min(1.0, p));
}
