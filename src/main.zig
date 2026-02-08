const std = @import("std");
const rl = @import("raylib");

const screen_width = 150;
const screen_height = 150;

const scale = 4;

const fps = 60;

const sprite_width: u8 = 10;
const sprite_height: u8 = 10;

const player_start_pos_x = screen_width / 2 - sprite_width / 2;
const player_start_pos_y = screen_height - sprite_height;

const player_speed = 30;

const wave_columns: u8 = 8;
const wave_rows: u8 = 4;
const wave_size = wave_columns * wave_rows;

const freak_speed = 150;

var timer_multiplier: f32 = 33.0;

const bullet_damage = 1;

const bullet_speed = 60;

var points: u32 = 0;

const Bullet = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    direction: f32,

    pub fn collidesWith(self: Bullet, x: f32, y: f32, width: f32, height: f32) bool {
        return self.x >= x and self.x <= x + width and self.y >= y and self.y <= y + height;
    }

    pub fn blit(self: Bullet) void {
        rl.drawRectangleGradientEx(
            rl.Rectangle{ .x = self.x, .y = self.y, .width = self.width, .height = self.height },
            rl.Color.red,
            rl.Color.orange,
            rl.Color.yellow,
            rl.Color.white,
        );
    }

    pub fn tick(self: *Bullet) void {
        self.y += rl.getFrameTime() * bullet_speed * self.direction;
    }
};


const Freak = struct {
    frames: [2]*rl.Texture2D,
    x: f32,
    y: f32,
    duration: f32,
    elapsed: f32,
    can_move: bool, // idc
    direction: f16,
    frame_i: u8,
    color: rl.Color,

    pub fn init(frame_one: *rl.Texture2D, frame_two: *rl.Texture2D, x: f32, y: f32, duration: f32, rand: std.Random) Freak {
        return Freak{
            .frames = [_]*rl.Texture2D{frame_one, frame_two},
            .x = x,
            .y = y,
            .duration = duration,
            .elapsed = 0,
            .can_move = true,
            .direction = 1,
            .frame_i = 0,
            .color = rl.Color{.r = rand.uintAtMost(u8, 205) + 50, .g = rand.uintAtMost(u8, 205) + 50, .b = rand.uintAtMost(u8, 205) + 50, .a = 255.0},
        };
    }

    pub fn blit(self: Freak) void {
        rl.drawTextureRec(self.frames[self.frame_i].*, rl.Rectangle{ .x = 0, .y = 0, .width = sprite_width, .height = sprite_height }, rl.Vector2{ .x = @round(self.x), .y = @round(self.y) }, self.color);
    }

    pub fn tick(self: *Freak) void {
        if (!self.can_move) return;

        self.elapsed += rl.getFrameTime() * timer_multiplier;

        if (self.elapsed >= self.duration) {
            self.elapsed = 0;
        } else return;

        self.x += rl.getFrameTime() * freak_speed * self.direction;

        self.frame_i += 1;

        if (self.frame_i > 1) {
            self.frame_i = 0;
        }

        self.can_move = false;
    }
};

const Player = struct {
    sprite: *rl.Texture2D,
    x: f32,
    y: f32,
    hp: u8,

    pub fn init(sprite: *rl.Texture2D) Player {
        return Player{
            .sprite = sprite,
            .x = player_start_pos_x,
            .y = player_start_pos_y,
            .hp = 3
        };
    }

    pub fn blit(self: Player) void {
        rl.drawTextureRec(self.sprite.*, rl.Rectangle{ .x = 0, .y = 0, .width = sprite_width, .height = sprite_height }, rl.Vector2{ .x = @round(self.x), .y = @round(self.y) }, rl.Color.white);
    }
};

const Death = struct {
    sprite: *rl.Texture2D,
    color: rl.Color,
    x: f32,
    y: f32,
    elapsed: f32,
    duration: f32,

    pub fn init(sprite: *rl.Texture2D, x: f32, y: f32, color: rl.Color) Death {
        return Death {
            .sprite = sprite,
            .x = x,
            .y = y,
            .color = color,
            .elapsed = 0.0,
            .duration = 1.0,
        };
    }

    pub fn tick(self: *Death) void {
        self.elapsed += rl.getFrameTime();
    }

    pub fn timeOut(self: Death) bool { return self.elapsed >= self.duration; }

    pub fn blit(self: Death) void {
        rl.drawTexture(self.sprite.*, @intFromFloat(self.x), @intFromFloat(self.y), self.color);
    }
};

const GameScenes = enum { menu, playing };

const State = struct {
    scene: GameScenes = .menu,
    player: Player,
    freaks: [wave_size]?Freak,
    bullets: std.ArrayList(Bullet),
    deaths: std.ArrayList(Death),
    freak_bullets: std.ArrayList(Bullet),
    index: usize,
};

var state: State = undefined;

fn initState(allocator: std.mem.Allocator, freak_one: *rl.Texture2D, freak_two: *rl.Texture2D, space_ship: *rl.Texture2D, rand: std.Random) anyerror!void {
    var freaks: [wave_size]?Freak = undefined;

    var i: u16 = 0;
    while (i < freaks.len) : (i += 1) {
        const x: f32 = @floatFromInt((i % wave_columns) * sprite_width + (i % wave_columns));
        const y: f32 = @floatFromInt((i / wave_columns) * sprite_height);

        const duration: f32 = @floatFromInt(i + 1);

        const freak = Freak.init(freak_one, freak_two, x, y + 20, duration, rand);
        freaks[i] = freak;
    }

    points = 0;

    state = State{
        .player = Player.init(space_ship),
        .freaks = freaks,
        .bullets = try std.ArrayList(Bullet).initCapacity(allocator, 64),
        .deaths = try std.ArrayList(Death).initCapacity(allocator, wave_size),
        .freak_bullets = try std.ArrayList(Bullet).initCapacity(allocator, 64),
        .index = 0,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    rl.initWindow(screen_width * scale, screen_height * scale, "alien attack");
    defer rl.closeWindow();

    const render_texture = try rl.loadRenderTexture(screen_width, screen_height);
    defer rl.unloadRenderTexture(render_texture);

    var space_ship = try rl.loadTexture("res/SpaceShip.png");
    defer rl.unloadTexture(space_ship);

    var freak_one = try rl.loadTexture("res/Freak1.png");
    defer rl.unloadTexture(freak_one);

    var freak_two = try rl.loadTexture("res/Freak2.png");
    defer rl.unloadTexture(freak_two);

    var death_splosion = try rl.loadTexture("res/Death.png");
    defer rl.unloadTexture(death_splosion);

    try initState(allocator, &freak_one, &freak_two, &space_ship, rand);

    

    rl.setTargetFPS(fps);

    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(rl.KeyboardKey.enter) and state.scene == GameScenes.menu) {
            try initState(allocator, &freak_one, &freak_two, &space_ship, rand);

            state.scene = GameScenes.playing;
        }

        if (rl.isKeyDown(rl.KeyboardKey.a) and state.scene == GameScenes.playing) {
            state.player.x -= rl.getFrameTime() * player_speed;
        }

        if (rl.isKeyDown(rl.KeyboardKey.d) and state.scene == GameScenes.playing) {
            state.player.x += rl.getFrameTime() * player_speed;
        }

        if (rl.isKeyPressed(rl.KeyboardKey.space) and state.scene == GameScenes.playing) {
            try state.bullets.append(allocator, Bullet{ .x = state.player.x, .y = state.player.y, .width = 2, .height = 2, .direction = -1});
        }

        rl.beginTextureMode(render_texture);

        rl.clearBackground(rl.Color.black);

        rl.drawCircle(-10, -10, 10, rl.Color.red);

        switch (state.scene) {
            .menu => {
                rl.drawText("press enter to kill them", 0, 0, 10, rl.Color.red);
            },
            .playing => {
                state.player.blit();

                for (&state.freaks) |*freak| {
                    if (freak.* == null) continue;
                    freak.*.?.blit();
                    freak.*.?.tick();

                    if (rand.uintAtMost(u32, 1000) > 999) {
                        const bullet = Bullet{.x = freak.*.?.x, .y = freak.*.?.y, .width = 2, .height = 2, .direction = 1};
                        try state.freak_bullets.append(allocator, bullet);
                    }
                }

                var wave_completed_move = false;

                var windex: u8 = state.freaks.len - 1;
                while (windex > 0) : (windex -= 1) {
                    if (state.freaks[windex] == null) {
                        if (windex <= 1) {
                            var i: u16 = 0;
                            while (i < state.freaks.len) : (i += 1) {
                                const x: f32 = @floatFromInt((i % wave_columns) * sprite_width + (i % wave_columns));
                                const y: f32 = @floatFromInt((i / wave_columns) * sprite_height);

                                const duration: f32 = @floatFromInt(i + 1);

                                const freak = Freak.init(&freak_one, &freak_two, x, y + 20, duration, rand);
                                state.freaks[i] = freak;
                            }
                        }
                        continue;
                    }

                    if (!state.freaks[windex].?.can_move) {
                        wave_completed_move = true;
                        for (&state.freaks) |*freak| {
                            if (freak.* == null) continue;
                            freak.*.?.can_move = true;
                        }
                    }

                    break;
                }

                const collided_with_right = for (&state.freaks) |*freak| {
                    if (freak.* == null) continue;
                    if (freak.*.?.x + sprite_width >= screen_width) break true;
                } else false;

                if (collided_with_right and wave_completed_move) {
                    for (&state.freaks) |*freak| {
                        if (freak.* == null) continue;
                        freak.*.?.direction = -1;
                        freak.*.?.y += sprite_height;
                    }
                }

                const collided_with_left = for (&state.freaks) |*freak| {
                    if (freak.* == null) continue;
                    if (freak.*.?.x <= 0) break true;
                } else false;

                if (collided_with_left and wave_completed_move) {
                    for (&state.freaks) |*freak| {
                        if (freak.* == null) continue;
                        freak.*.?.direction = 1;
                        freak.*.?.y += sprite_height;
                    }
                }

                var dindex: u8 = 0;
                while (dindex < state.deaths.items.len) : (dindex += 1) {
                    state.deaths.items[dindex].tick();
                    state.deaths.items[dindex].blit();

                    if (state.deaths.items[dindex].timeOut()) {
                        _ = state.deaths.orderedRemove(dindex);
                    }
                }
                
                var index: u8 = 0;
                bullet_loop: while (index < state.bullets.items.len) : (index += 1) {
                    state.bullets.items[index].blit();
                    state.bullets.items[index].tick();

                    var findex: u8 = 0;
                    while (findex < state.freaks.len) : (findex += 1) {
                        if (state.freaks[findex] == null) continue;
                        if (state.bullets.items[index].collidesWith(state.freaks[findex].?.x, state.freaks[findex].?.y, sprite_width, sprite_height)) {
                            _ = state.bullets.orderedRemove(index);
                            const death = Death.init(&death_splosion, state.freaks[findex].?.x, state.freaks[findex].?.y, state.freaks[findex].?.color);
                            try state.deaths.append(allocator, death);
                            state.freaks[findex] = null;
                            points += 1;
                            continue :bullet_loop;
                        }
                    }

                    if (state.bullets.items[index].y <= 0) {
                        _ = state.bullets.orderedRemove(index);
                    }
                }

                var fbindex: u8 = 0;
                while (fbindex < state.freak_bullets.items.len) : (fbindex += 1) {
                    state.freak_bullets.items[fbindex].tick();
                    state.freak_bullets.items[fbindex].blit();

                    if (state.freak_bullets.items[fbindex].collidesWith(state.player.x, state.player.y, sprite_width, sprite_height)) {
                        _ = state.freak_bullets.orderedRemove(fbindex);
                        state.player.hp -= 1;

                        if (state.player.hp <= 0) {
                            state.scene = GameScenes.menu;
                        }

                        continue;
                    }

                    if (state.freak_bullets.items[fbindex].y >= screen_height) {
                        _ = state.freak_bullets.orderedRemove(fbindex);
                    }
                }

                rl.drawRectangleGradientEx(rl.Rectangle{.x = 0, .y = 0, .width = screen_width, .height = 20}, rl.Color.red, rl.Color.orange, rl.Color.gold, rl.Color.brown);
                const string = try std.fmt.allocPrintSentinel(allocator, "Points: {d}", .{points * 10}, 0);
                rl.drawText(string, 0, 0, 10, rl.Color.white);
                allocator.free(string);
            },
        }

        rl.endTextureMode();

        rl.beginDrawing();

        rl.clearBackground(rl.Color.white);

        rl.drawTexturePro(render_texture.texture, rl.Rectangle{ .x = 0, .y = 0, .width = screen_width, .height = -screen_height }, rl.Rectangle{ .x = 0, .y = 0, .width = screen_width * scale, .height = screen_height * scale }, rl.Vector2{ .x = 0, .y = 0 }, 0, rl.Color.white);

        rl.endDrawing();
    }
}
