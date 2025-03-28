const std = @import("std");
const rl = @import("raylib");
const rlm = @import("raylib").math;
const math = std.math;
const Vector2 = rl.Vector2;

const Ship = struct {
    pos: Vector2,
    vel: Vector2,
    rot: f32,
    death_time: f32 = 0.0,
    fn isDead(self: @This()) bool {
        return self.death_time != 0.0;
    }
};

const Asteroid = struct {
    pos: Vector2,
    vel: Vector2,
    size: ASTEROID_SIZE,
    seed: u64,
    remove: bool = false,
};

const State = struct {
    delta: f32 = 0.0,
    now: f32 = 0.0,
    stageStart: f32 = 0,
    ship: Ship,
    asteroids: std.ArrayList(Asteroid),
    asteroids_queue: std.ArrayList(Asteroid),
    particles: std.ArrayList(Particle),
    projectiles: std.ArrayList(Projectile),
    rand: std.rand.Random,
    lives: u32 = 0,
    score: u32 = 0,
    reset: bool = false,
    bloop: usize = 0,
    lastBloop: usize = 0,
    frame: usize = 0,
    bloopIntensity: usize = 0,
};

const Sound = struct {
    bloopHi: rl.Sound,
    bloopLow: rl.Sound,
    shoot: rl.Sound,
    thrust: rl.Sound,
    explode: rl.Sound,
};
var sound: Sound = undefined;

const Projectile = struct {
    pos: Vector2,
    vel: Vector2,
    ttl: f32,
    remove: bool = false,
};

const Particle = struct {
    pos: Vector2,
    vel: Vector2,
    ttl: f32,
    values: union(enum) {
        Line: struct {
            rot: f32,
            len: f32,
        },
        Dot: struct {
            radius: f32,
        },
    },
};

const THICKNESS = 2.0;
const SCALE = 40;
const SIZE = Vector2.init(640 * 2, 480 * 2);

var state: State = undefined;

fn drawNumber(num: usize, pos: Vector2) !void {
    //can just use 7 segment Display
    const NUMBER_LINES = [10][]const [2]f32{
        &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 } }, //zero
        &.{ .{ 0.5, 0 }, .{ 0.5, 1 } }, //one
        &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 0, 0 }, .{ 1, 0 } }, //two
        &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 0 }, .{ 0, 0 } }, //three
        &.{ .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 1 }, .{ 1, 0 } }, //four
        &.{ .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 0 }, .{ 0, 0 } }, //five
        &.{ .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 }, .{ 1, 0 }, .{ 1, 0.5 }, .{ 0, 0.5 } }, //six
        &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 } }, //seven
        &.{ .{ 0, 0 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 }, .{ 1, 0 }, .{ 1, 0.5 } }, //eight
        &.{ .{ 1, 0 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0.5 } }, //nine
    };
    //get the number of digits
    var digits: usize = 0;
    var val = num;
    while (val >= 0) {
        digits += 1;
        val /= 10;
        if (val == 0) {
            break;
        }
    }
    var pos2 = pos;
    val = num;
    while (val > 0) {
        var points = try std.BoundedArray(Vector2, 16).init(0);
        for (NUMBER_LINES[val % 10]) |p| {
            try points.append(Vector2.init(p[0] - 0.5, 1.0 - p[1] - 0.5));
        }
        drawLines(pos2, SCALE * 0.8, 0, points.slice(), false);
        pos2.x -= SCALE;
        val /= 10;
    }
}
fn drawLines(origin: Vector2, scale: f32, rot: f32, points: []const Vector2, connect: bool) void {
    const Transformer = struct {
        origin: Vector2,
        scale: f32,
        rot: f32,
        fn apply(self: @This(), p: Vector2) Vector2 {
            return rlm.vector2Add(
                rlm.vector2Scale(rlm.vector2Rotate(p, self.rot), self.scale),
                self.origin,
            );
        }
    };
    const t = Transformer{ .origin = origin, .scale = scale, .rot = rot };
    const bound = if (connect) points.len else (points.len - 1);
    for (0..bound) |i| {
        rl.drawLineEx(
            t.apply(points[i]),
            t.apply(points[(i + 1) % points.len]),
            THICKNESS,
            rl.Color.white,
        );
    }
}

const ASTEROID_SIZE = enum(u8) {
    BIG,
    MEDIUM,
    SMALL,
    fn size(self: @This()) f32 {
        return switch (self) {
            .BIG => SCALE * 3.0,
            .MEDIUM => SCALE * 1.4,
            .SMALL => SCALE * 0.8,
        };
    }
    fn velocityScale(self: @This()) f32 {
        return switch (self) {
            .BIG => 0.75,
            .MEDIUM => 1.0,
            .SMALL => 1.6,
        };
    }
    fn score(self: @This()) u32 {
        return switch (self) {
            .BIG => 25,
            .MEDIUM => 50,
            .SMALL => 100,
        };
    }
};

fn drawAsteroid(pos: Vector2, size: ASTEROID_SIZE, seed: u64) void {
    var rand_impl = std.Random.Xoshiro256.init(seed);
    const random = rand_impl.random();
    var points = std.BoundedArray(Vector2, 16).init(0) catch unreachable;
    const n = random.intRangeLessThan(i32, 8, 15);
    for (0..@intCast(n)) |i| {
        var radius = 0.3 + (0.2 * random.float(f32));
        if (random.float(f32) < 0.2) {
            radius -= 0.2;
        }
        const angle: f32 = (@as(f32, @floatFromInt(i)) * (math.tau / @as(f32, @floatFromInt(n)))) + (math.pi * 0.125 * random.float(f32));
        points.append(rlm.vector2Scale(Vector2.init(math.cos(angle), math.sin(angle)), radius)) catch unreachable;
    }
    drawLines(pos, size.size(), 0.0, points.slice(), true);
}

fn update() !void {
    if (state.reset) {
        state.reset = false;
        try resetGame();
    }
    if (!state.ship.isDead()) {
        const ROT_SPEED = 1;
        if (rl.isKeyDown(.a)) {
            state.ship.rot -= state.delta * math.tau * ROT_SPEED;
        }
        if (rl.isKeyDown(.d)) {
            state.ship.rot += state.delta * math.tau * ROT_SPEED;
        }
        const SHIP_SPEED = 300;
        //cos and sin are the goat!!
        //cos gives us the x component and sin gives us y component.
        const shipAngle = state.ship.rot + (math.pi * 0.5);
        const shipDir = Vector2.init(math.cos(shipAngle), math.sin(shipAngle));
        if (rl.isKeyDown(.w)) {
            state.ship.pos = rlm.vector2Add(
                state.ship.pos,
                rlm.vector2Scale(shipDir, state.delta * SHIP_SPEED),
            );
            rl.playSound(sound.thrust);
        }
        if (rl.isKeyPressed(.space) or rl.isMouseButtonPressed(rl.MouseButton.left)) {
            try state.projectiles.append(
                .{
                    .pos = rlm.vector2Add(state.ship.pos, rlm.vector2Scale(shipDir, SCALE * 0.55)),
                    .vel = rlm.vector2Scale(shipDir, 10),
                    .ttl = 2.0,
                },
            );
            state.ship.vel = rlm.vector2Add(state.ship.vel, rlm.vector2Scale(shipDir, -0.45));
            rl.playSound(sound.shoot);
        }
        //collison between ship and projectiles
        for (state.projectiles.items) |*p| {
            if (!p.remove and (rlm.vector2Distance(p.pos, state.ship.pos) < SCALE * 0.5)) {
                rl.playSound(sound.explode);
                p.remove = true;
                state.ship.death_time = state.now;
            }
        }
    }
    const DRAG = 0.015;
    state.ship.vel = rlm.vector2Scale(state.ship.vel, 1.0 - DRAG);
    state.ship.pos = rlm.vector2Add(state.ship.pos, state.ship.vel);
    state.ship.pos = Vector2.init(
        @mod(state.ship.pos.x, SIZE.x),
        @mod(state.ship.pos.y, SIZE.y),
    );
    try state.asteroids.appendSlice(state.asteroids_queue.items);
    try state.asteroids_queue.resize(0);
    {
        var i: usize = 0;
        while (i < state.asteroids.items.len) {
            var asteroid = &state.asteroids.items[i];
            asteroid.pos = rlm.vector2Add(asteroid.pos, asteroid.vel);
            asteroid.pos = Vector2.init(
                @mod(asteroid.pos.x, SIZE.x),
                @mod(asteroid.pos.y, SIZE.y),
            );
            //collision between asteroids and ship
            if (!state.ship.isDead() and rlm.vector2Distance(asteroid.pos, state.ship.pos) < (asteroid.size.size() / 2)) {
                state.ship.death_time = state.now;
                rl.playSound(sound.explode);
                try hitAsteroid(asteroid, rlm.vector2Normalize(state.ship.vel));
            }
            //collision between asteroids and projectiles
            for (state.projectiles.items) |*p| {
                if (rlm.vector2Distance(p.pos, asteroid.pos) < asteroid.size.size()) {
                    p.remove = true;
                    try hitAsteroid(asteroid, rlm.vector2Normalize(p.vel));
                }
            }
            if (asteroid.remove) {
                _ = state.asteroids.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
    {
        var i: usize = 0;
        while (i < state.projectiles.items.len) {
            var projectile = &state.projectiles.items[i];
            projectile.pos = rlm.vector2Add(projectile.pos, projectile.vel);
            projectile.pos = Vector2.init(
                @mod(projectile.pos.x, SIZE.x),
                @mod(projectile.pos.y, SIZE.y),
            );
            if (!projectile.remove and projectile.ttl > state.delta) {
                projectile.ttl -= state.delta;
                i += 1;
            } else {
                _ = state.projectiles.swapRemove(i);
            }
        }
    }
    {
        var i: usize = 0;
        while (i < state.particles.items.len) {
            var particle = &state.particles.items[i];
            particle.pos = rlm.vector2Add(particle.pos, particle.vel);
            particle.pos = Vector2.init(
                @mod(particle.pos.x, SIZE.x),
                @mod(particle.pos.y, SIZE.y),
            );
            if (particle.ttl > state.delta) {
                particle.ttl -= state.delta;
                i += 1;
            } else {
                _ = state.particles.swapRemove(i);
            }
        }
    }
    if (state.ship.death_time == state.now) {
        try splatDots(state.ship.pos, 5);
        try splatLines(state.ship.pos, 5);
    }
    if (state.ship.isDead() and (state.now - state.ship.death_time) > 3.0) {
        try resetStage();
    }
    const bloopIntensity = @min(@as(usize, @intFromFloat(state.now - state.stageStart)) / 30, 4);
    var bloopMod: usize = 60;
    for (0..bloopIntensity) |_| {
        bloopMod /= 2;
    }
    if (state.frame % bloopMod == 0) {
        state.bloop += 1;
    }
    if (!state.ship.isDead() and state.bloop != state.lastBloop) {
        rl.playSound(if (state.bloop % 2 == 0) sound.bloopLow else sound.bloopHi);
    }
    state.lastBloop = state.bloop;
}

fn splatDots(pos: Vector2, count: usize) !void {
    for (0..count) |_| {
        const angle = math.tau * state.rand.float(f32);
        try state.particles.append(.{ .pos = pos, .vel = rlm.vector2Scale(Vector2.init(math.cos(angle), math.sin(angle)), state.rand.float(f32) * 3.0), .ttl = 1.0 + 0.5 * state.rand.float(f32), .values = .{ .Dot = .{ .radius = 1.0 } } });
    }
}
fn splatLines(pos: Vector2, count: usize) !void {
    for (0..count) |_| {
        const angle = math.tau * state.rand.float(f32);
        try state.particles.append(.{ .pos = rlm.vector2Add(
            pos,
            Vector2.init(state.rand.float(f32) * 3, state.rand.float(f32) * 3),
        ), .vel = rlm.vector2Scale(Vector2.init(math.cos(angle), math.sin(angle)), state.rand.float(f32) * 3.0), .ttl = 1.0 + state.rand.float(f32), .values = .{
            .Line = .{
                .rot = math.tau * state.rand.float(f32),
                .len = SCALE * (0.6 + (0.4 * state.rand.float(f32))),
            },
        } });
    }
}

fn hitAsteroid(a: *Asteroid, impact: ?Vector2) !void {
    state.score += a.size.score();
    a.remove = true;
    if (a.size == .SMALL) {
        return;
    }
    for (0..2) |_| {
        const size: ASTEROID_SIZE = switch (a.size) {
            .BIG => .MEDIUM,
            .MEDIUM => .SMALL,
            else => unreachable,
        };
        try splatDots(a.pos, 4);
        const dir = rlm.vector2Normalize(a.vel);
        try state.asteroids_queue.append(
            .{
                .pos = a.pos,
                .vel = rlm.vector2Add(
                    rlm.vector2Scale(dir, a.size.velocityScale() * 1.5 * state.rand.float(f32)),
                    if (impact) |i| rlm.vector2Scale(i, 1.5) else Vector2.init(0, 0),
                ),
                .size = size,
                .seed = state.rand.int(u64),
            },
        );
    }
}

const SHIP_LINES = [_]Vector2{
    Vector2.init(-0.4, -0.5),
    Vector2.init(0.0, 0.5),
    Vector2.init(0.4, -0.5),
    Vector2.init(0.3, -0.4),
    Vector2.init(-0.3, -0.4),
};

fn render() !void {
    for (0..state.lives) |i| {
        drawLines(Vector2.init(SCALE + (@as(f32, @floatFromInt(i)) * SCALE), SCALE), SCALE, -math.pi, &SHIP_LINES, true);
    }
    if (!state.ship.isDead()) {
        drawLines(state.ship.pos, SCALE, state.ship.rot, &.{
            Vector2.init(-0.4, -0.5),
            Vector2.init(0.0, 0.5),
            Vector2.init(0.4, -0.5),
            Vector2.init(0.3, -0.4),
            Vector2.init(-0.3, -0.4),
        }, true);
        if (rl.isKeyDown(.w) and @mod(@as(i32, @intFromFloat(state.now * 20)), 2) == 0) {
            drawLines(state.ship.pos, SCALE, state.ship.rot, &.{
                Vector2.init(-0.3, -0.4),
                Vector2.init(0.0, -0.8),
                Vector2.init(0.3, -0.4),
            }, true);
        }
    }
    for (state.asteroids.items) |asteroid| {
        drawAsteroid(asteroid.pos, asteroid.size, asteroid.seed);
    }

    for (state.projectiles.items) |projectile| {
        rl.drawCircleV(projectile.pos, SCALE * 0.05, rl.Color.white);
    }
    try drawNumber(state.score, Vector2.init(SIZE.x - SCALE, SCALE));
    for (state.particles.items) |particle| {
        switch (particle.values) {
            .Line => |line| {
                drawLines(particle.pos, line.len, line.rot, &.{
                    Vector2.init(-0.5, 0.0),
                    Vector2.init(0.5, 0.0),
                }, true);
            },
            .Dot => |dot| {
                rl.drawCircleV(particle.pos, dot.radius, rl.Color.white);
            },
        }
    }
}

fn resetAsteroids() !void {
    try state.asteroids.resize(0);
    for (0..20) |_| {
        const angle = math.tau * state.rand.float(f32);
        const size = state.rand.enumValue(ASTEROID_SIZE);
        try state.asteroids.append(
            .{
                .pos = Vector2.init(
                    state.rand.float(f32) * SIZE.x,
                    state.rand.float(f32) * SIZE.y,
                ),
                .vel = rlm.vector2Scale(Vector2.init(math.cos(angle), math.sin(angle)), size.velocityScale() * 3.0 * state.rand.float(f32)),
                .size = size,
                .seed = state.rand.int(u64),
            },
        );
    }
    state.stageStart = state.now;
}

fn resetStage() !void {
    if (state.ship.isDead()) {
        if (state.lives != 0) {
            state.lives -= 1;
        } else {
            state.reset = true;
        }
    }
    state.ship.death_time = 0.0;
    state.ship = .{
        .pos = rlm.vector2Scale(SIZE, 0.5),
        .vel = Vector2.init(0, 0),
        .rot = 0.0,
    };
}

fn resetGame() !void {
    state.lives = 3;
    state.score = 0;
    try resetStage();
    try resetAsteroids();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var rand_impl = std.Random.Xoshiro256.init(@bitCast(std.time.timestamp()));

    std.debug.print("From asteroids\n", .{});
    rl.initWindow(SIZE.x, SIZE.y, "asteroids");
    defer rl.closeWindow();
    rl.setTargetFPS(60);
    state = .{
        .ship = .{
            .pos = rlm.vector2Scale(SIZE, 0.5), //center of the screen.
            .vel = Vector2.init(0, 0),
            .rot = 0.0,
        },
        .asteroids = std.ArrayList(Asteroid).init(allocator),
        .asteroids_queue = std.ArrayList(Asteroid).init(allocator),
        .rand = rand_impl.random(),
        .particles = std.ArrayList(Particle).init(allocator),
        .projectiles = std.ArrayList(Projectile).init(allocator),
    };
    rl.initAudioDevice();
    defer rl.closeAudioDevice();
    defer state.asteroids.deinit();
    defer state.asteroids_queue.deinit();
    defer state.particles.deinit();
    defer state.projectiles.deinit();

    sound = .{
        .bloopHi = rl.loadSound("bloop_hi.wav") catch |err| {
            std.debug.print("failed {}", .{err});
            return;
        },
        .bloopLow = rl.loadSound("bloop_lo.wav") catch |err| {
            std.debug.print("failed {}", .{err});
            return;
        },

        .shoot = rl.loadSound("shoot.wav") catch |err| {
            std.debug.print("failed {}", .{err});
            return;
        },

        .thrust = rl.loadSound("thrust.wav") catch |err| {
            std.debug.print("failed {}", .{err});
            return;
        },

        .explode = rl.loadSound("explode.wav") catch |err| {
            std.debug.print("failed {}", .{err});
            return;
        },
    };
    try resetGame();
    //game loop
    while (!rl.windowShouldClose()) {
        state.delta = rl.getFrameTime();
        state.now += state.delta;
        try update();
        rl.beginDrawing();
        defer rl.endDrawing();
        try render();

        rl.clearBackground(rl.Color.black);
        state.frame += 1;
    }
}
