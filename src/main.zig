const std = @import("std");
const rl = @import("raylib");
const rlm = @import("raylib").math;
const math = std.math;
const Vector2 = rl.Vector2;

const Ship = struct {
    pos: Vector2,
    vel: Vector2,
    rot: f32,
};

const Asteroid = struct {
    pos: Vector2,
    vel: Vector2,
    size: ASTEROID_SIZE,
    seed: u64,
};

const State = struct {
    delta: f32 = 0.0,
    now: f32 = 0.0,
    ship: Ship,
    asteroids: std.ArrayList(Asteroid),
    rand: std.rand.Random,
};

const THICKNESS = 2.0;
const SCALE = 40;
const SIZE = Vector2.init(640 * 2, 480 * 2);

var state: State = undefined;

fn drawLines(origin: Vector2, scale: f32, rot: f32, points: []const Vector2) void {
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
    for (0..points.len) |i| {
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
    drawLines(pos, size.size(), 0.0, points.slice());
}

fn update() void {
    const ROT_SPEED = 1;
    if (rl.isKeyDown(.a)) {
        state.ship.rot -= state.delta * math.tau * ROT_SPEED;
    }
    if (rl.isKeyDown(.d)) {
        state.ship.rot += state.delta * math.tau * ROT_SPEED;
    }
    //cos and sin are the goat!!
    //cos gives us the x component and sin gives us y component.
    const shipAngle = state.ship.rot + (math.pi * 0.5);
    const shipDir = Vector2.init(math.cos(shipAngle), math.sin(shipAngle));
    const SHIP_SPEED = 400;
    if (rl.isKeyDown(.w)) {
        state.ship.pos = rlm.vector2Add(
            state.ship.pos,
            rlm.vector2Scale(shipDir, state.delta * SHIP_SPEED),
        );
    }
    const DRAG = 0.015;
    state.ship.vel = rlm.vector2Scale(state.ship.vel, 1.0 - DRAG);
    state.ship.pos = rlm.vector2Add(state.ship.pos, state.ship.vel);
    state.ship.pos = Vector2.init(@mod(state.ship.pos.x, SIZE.x), @mod(state.ship.pos.y, SIZE.y));
    if (rl.isKeyDown(.w)) {
        drawLines(state.ship.pos, SCALE, state.ship.rot, &.{
            Vector2.init(-0.3, -0.4),
            Vector2.init(0.0, -0.8),
            Vector2.init(0.3, -0.4),
        });
    }
    for (state.asteroids.items) |*asteroid| {
        asteroid.pos = rlm.vector2Add(asteroid.pos, asteroid.vel);
    }
}

fn render() void {
    drawLines(state.ship.pos, SCALE, state.ship.rot, &.{
        Vector2.init(-0.4, -0.5),
        Vector2.init(0.0, 0.5),
        Vector2.init(0.4, -0.5),
        Vector2.init(0.3, -0.4),
        Vector2.init(-0.3, -0.4),
    });
    for (state.asteroids.items) |asteroid| {
        drawAsteroid(asteroid.pos, asteroid.size, asteroid.seed);
    }
}

fn initLevel() !void {
    for (0..10) |_| {
        const angle = math.tau * state.rand.float(f32);
        try state.asteroids.append(
            .{
                .pos = Vector2.init(
                    state.rand.float(f32) * SIZE.x,
                    state.rand.float(f32) * SIZE.y,
                ),
                .vel = rlm.vector2Scale(Vector2.init(math.cos(angle), math.sin(angle)), 3.0 * state.rand.float(f32)),
                .size = state.rand.enumValue(ASTEROID_SIZE),
                .seed = state.rand.int(u64),
            },
        );
    }
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
            .pos = rlm.vector2Scale(SIZE, 0.5),
            .vel = Vector2.init(0, 0),
            .rot = 0.0,
        },
        .asteroids = std.ArrayList(Asteroid).init(allocator),
        .rand = rand_impl.random(),
    };
    defer state.asteroids.deinit();
    try initLevel();
    //game loop
    while (!rl.windowShouldClose()) {
        state.delta = rl.getFrameTime();
        state.now += state.delta;
        update();
        rl.beginDrawing();
        defer rl.endDrawing();
        render();

        rl.clearBackground(rl.Color.black);
    }
}
