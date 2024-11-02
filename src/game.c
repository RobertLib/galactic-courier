#include "game.h"

#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "audio.h"
#include "gfx.h"

#define LEVEL_WIDTH 1600.0f
#define LEVEL_HEIGHT 1200.0f
#define GRID_SIZE 20
#define MAX_LEVEL 3

#define INIT_ENEMIES 10
#define INIT_COLLECTABLES 10

#define MAX_ENEMIES 64
#define MAX_COLLECTABLES 64
#define MAX_BULLETS 256
#define MAX_PARTICLES 2048
#define MAX_TIMEOUTS 16
#define NUM_STARS 200

#define CHAIN_LENGTH 10
#define CHAIN_SEGMENT_LENGTH 20.0f
#define CHAIN_LINK_RADIUS 5.0f
#define CHAIN_SOLVER_ITERATIONS 8

#define TWO_PI (2.0f * SDL_PI_F)

/* Remove element i from a plain array, keeping order. */
#define REMOVE_AT(array, count, i)                                             \
  do {                                                                         \
    memmove(&(array)[(i)], &(array)[(i) + 1],                                  \
            sizeof((array)[0]) * (size_t)((count) - (i) - 1));                 \
    (count)--;                                                                 \
  } while (0)

typedef enum {
  STATE_MAIN_MENU,
  STATE_PLAYING,
  STATE_GAME_OVER,
  STATE_WIN
} GameState;

typedef struct {
  float x, y;
  float radius;
} Collectable;

typedef struct {
  Collectable items[MAX_COLLECTABLES];
  int count;
} CollectableList;

typedef struct {
  float x, y;
  float angle;
  float radius;
} Enemy;

typedef struct {
  float x, y;
  float xvel, yvel;
  float angle;
  float radius;
} Bullet;

typedef struct {
  float x, y;
  float xvel, yvel;
  float radius;
  float life;
  float r, g, b;
} Particle;

typedef struct {
  void (*callback)(void);
  double time;
} Timeout;

typedef struct {
  float x, y;
  float intensity;
  float speed;
} Star;

typedef struct {
  float x, y;     /* current position */
  float px, py;   /* position at the start of the step */
  float vx, vy;   /* velocity */
} ChainLink;

typedef struct {
  ChainLink links[CHAIN_LENGTH];
  bool joined; /* false once the ship exploded and the joints were "destroyed" */
  CollectableList attached;
} Chain;

typedef struct {
  float x, y;
  float xvel, yvel;
  float angle;
  float radius;
  float speed;
  bool dead;
  float opacity;
  Bullet bullets[MAX_BULLETS];
  int bullet_count;
  double last_shot_time;
  Chain chain;
} Spaceship;

typedef struct {
  float x, y;
  float radius;
  float angle;
  CollectableList attached;
} Unloading;

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static int win_w = WINDOW_WIDTH;
static int win_h = WINDOW_HEIGHT;

static GameState game_state = STATE_MAIN_MENU;
static int lives = 0;
static int level = 0;
static bool paused = false;
static struct { float x, y; } camera = { 0.0f, 0.0f };

static Timeout timeouts[MAX_TIMEOUTS];
static int timeout_count = 0;

static Particle particles[MAX_PARTICLES];
static int particle_count = 0;

static Star stars[NUM_STARS];

static Enemy enemies[MAX_ENEMIES];
static int enemy_count = 0;

static CollectableList collectables;

static Unloading unloading = {
  .x = LEVEL_WIDTH / 4.0f,
  .y = LEVEL_HEIGHT / 4.0f,
  .radius = 50.0f,
  .angle = 0.0f,
};

static Spaceship ship = {
  .x = LEVEL_WIDTH / 2.0f,
  .y = LEVEL_HEIGHT / 2.0f,
  .angle = -SDL_PI_F / 2.0f,
  .radius = 10.0f,
  .speed = 100.0f,
  .opacity = 1.0f,
};

static const float ship_vertices[] = { 20, 0, -10, -10, -10, 10 };
static const float enemy_vertices[] = { 0, 10, 10, 0, 0, -10, -10, 0 };
static const float bullet_vertices[] = { 0, 0, 5, 0 };

static SDL_FPoint *grid_points = NULL;
static int grid_capacity = 0;

static void playing_load(void);
static void spaceship_load(bool init);
static void stars_load(void);

/* ---------------------------------------------------------------- utils */

static double now_seconds(void)
{
  return (double)SDL_GetTicksNS() / 1e9;
}

static float randf(void)
{
  return SDL_randf();
}

/* Random integer in the inclusive range [lo, hi]. */
static int rand_range(int lo, int hi)
{
  return lo + (int)SDL_rand((Sint32)(hi - lo + 1));
}

static bool circles_collide(float x1, float y1, float r1, float x2, float y2, float r2)
{
  float dx = x1 - x2;
  float dy = y1 - y2;
  float r = r1 + r2;
  return dx * dx + dy * dy <= r * r;
}

static void list_push(CollectableList *list, Collectable item)
{
  if (list->count < MAX_COLLECTABLES) {
    list->items[list->count++] = item;
  }
}

static void collectable_draw(const Collectable *c)
{
  gfx_set_color(0.8f, 1.0f, 0.8f, 1.0f);
  gfx_circle_line(c->x, c->y, c->radius);
}

/* Move a collectable toward a target with constant speed, snapping when close. */
static void collectable_seek(Collectable *c, float target_x, float target_y,
                             float snap_distance, float dt)
{
  const float speed = 150.0f;
  float dx = target_x - c->x;
  float dy = target_y - c->y;
  float distance = sqrtf(dx * dx + dy * dy);

  if (distance > snap_distance) {
    c->x += (dx / distance) * speed * dt;
    c->y += (dy / distance) * speed * dt;
  } else {
    c->x = target_x;
    c->y = target_y;
  }
}

/* ------------------------------------------------------------- timeouts */

static void set_timeout(void (*callback)(void), double delay)
{
  for (int i = 0; i < timeout_count; i++) {
    if (timeouts[i].callback == callback) {
      return;
    }
  }

  if (timeout_count < MAX_TIMEOUTS) {
    timeouts[timeout_count].callback = callback;
    timeouts[timeout_count].time = now_seconds() + delay;
    timeout_count++;
  }
}

static void timeouts_clear(void)
{
  timeout_count = 0;
}

static void timeouts_update(void)
{
  double t = now_seconds();

  for (int i = 0; i < timeout_count;) {
    if (t >= timeouts[i].time) {
      void (*callback)(void) = timeouts[i].callback;
      REMOVE_AT(timeouts, timeout_count, i);
      callback();
    } else {
      i++;
    }
  }
}

/* ------------------------------------------------------------ particles */

static void particles_clear(void)
{
  particle_count = 0;
}

static void particles_create(float x, float y, int num, float speed, float radius,
                             float life, float r, float g, float b)
{
  for (int i = 0; i < num && particle_count < MAX_PARTICLES; i++) {
    float angle = TWO_PI * randf();
    float random_speed = speed * randf();
    Particle *p = &particles[particle_count++];

    p->x = x;
    p->y = y;
    p->xvel = cosf(angle) * random_speed;
    p->yvel = sinf(angle) * random_speed;
    p->radius = radius;
    p->life = life;
    p->r = r;
    p->g = g;
    p->b = b;
  }
}

static void particles_update(float dt)
{
  for (int i = 0; i < particle_count;) {
    Particle *p = &particles[i];

    p->x += p->xvel * dt;
    p->y += p->yvel * dt;
    p->life -= dt;

    if (p->life <= 0.0f) {
      REMOVE_AT(particles, particle_count, i);
    } else {
      i++;
    }
  }
}

static void particles_draw(void)
{
  for (int i = 0; i < particle_count; i++) {
    const Particle *p = &particles[i];
    gfx_set_color(p->r, p->g, p->b, p->life);
    gfx_circle_fill(p->x, p->y, p->radius);
  }
}

/* ----------------------------------------------------------- game state */

static void change_state(GameState state)
{
  game_state = state;

  if (state == STATE_PLAYING) {
    playing_load();
  }

  timeouts_clear();
  particles_clear();
}

/* ---------------------------------------------------------------- stars */

static void stars_load(void)
{
  for (int i = 0; i < NUM_STARS; i++) {
    stars[i].x = (float)rand_range(0, win_w);
    stars[i].y = (float)rand_range(0, win_h);
    stars[i].intensity = randf();
    stars[i].speed = randf() * 0.5f + 0.5f;
  }
}

static void stars_update(float dt)
{
  for (int i = 0; i < NUM_STARS; i++) {
    Star *s = &stars[i];
    s->intensity += s->speed * dt;

    if (s->intensity > 1.0f) {
      s->intensity = 1.0f;
      s->speed = -s->speed;
    } else if (s->intensity < 0.0f) {
      s->intensity = 0.0f;
      s->speed = -s->speed;
    }
  }
}

static void stars_draw(void)
{
  for (int i = 0; i < NUM_STARS; i++) {
    SDL_FPoint p = { stars[i].x, stars[i].y };
    gfx_set_color(1.0f, 1.0f, 1.0f, stars[i].intensity);
    gfx_points(&p, 1);
  }
}

/* ----------------------------------------------------------------- grid */

static void draw_grid(void)
{
  gfx_set_color(1.0f, 1.0f, 1.0f, 0.7f);

  float half_w = (float)win_w / 2.0f;
  float half_h = (float)win_h / 2.0f;

  float min_x = fmaxf(0.0f, camera.x - half_w);
  float max_x = fminf(LEVEL_WIDTH, camera.x + half_w);
  float min_y = fmaxf(0.0f, camera.y - half_h);
  float max_y = fminf(LEVEL_HEIGHT, camera.y + half_h);

  int gx0 = (int)floorf(min_x / GRID_SIZE) * GRID_SIZE;
  int gx1 = (int)ceilf(max_x / GRID_SIZE) * GRID_SIZE;
  int gy0 = (int)floorf(min_y / GRID_SIZE) * GRID_SIZE;
  int gy1 = (int)ceilf(max_y / GRID_SIZE) * GRID_SIZE;

  int cols = (gx1 - gx0) / GRID_SIZE + 1;
  int rows = (gy1 - gy0) / GRID_SIZE + 1;
  int needed = cols * rows;

  if (needed > grid_capacity) {
    SDL_FPoint *grown = (SDL_FPoint *)SDL_realloc(grid_points,
                                                  sizeof(SDL_FPoint) * (size_t)needed);
    if (!grown) {
      return;
    }
    grid_points = grown;
    grid_capacity = needed;
  }

  int count = 0;

  for (int x = gx0; x <= gx1; x += GRID_SIZE) {
    for (int y = gy0; y <= gy1; y += GRID_SIZE) {
      /* The ship bends the grid toward itself. */
      float dx = (float)x - ship.x;
      float dy = (float)y - ship.y;
      float distance = sqrtf(dx * dx + dy * dy);
      float influence = expf(-distance / 100.0f);

      grid_points[count].x = (float)x + influence * (ship.x - (float)x) * 0.5f;
      grid_points[count].y = (float)y + influence * (ship.y - (float)y) * 0.5f;
      count++;
    }
  }

  gfx_points(grid_points, count);
}

/* ------------------------------------------------------------ unloading */

static void unloading_load(void)
{
  unloading.attached.count = 0;
}

static void unloading_update(float dt)
{
  unloading.angle += SDL_PI_F * dt;

  int count = unloading.attached.count;
  float angle_step = count > 0 ? TWO_PI / (float)count : 0.0f;
  float radius = unloading.radius / 2.0f;

  for (int i = 0; i < count; i++) {
    Collectable *c = &unloading.attached.items[i];
    float angle = (float)(i + 1) * angle_step + unloading.angle;
    collectable_seek(c, unloading.x + radius * cosf(angle),
                     unloading.y + radius * sinf(angle), c->radius, dt);
  }
}

static void unloading_draw(void)
{
  gfx_set_color(0.8f, 0.8f, 1.0f, 1.0f);
  gfx_circle_line(unloading.x, unloading.y, unloading.radius);

  for (int i = 0; i < unloading.attached.count; i++) {
    collectable_draw(&unloading.attached.items[i]);
  }
}

/* -------------------------------------------------------------- enemies */

static void enemy_explode(const Enemy *e)
{
  particles_create(e->x, e->y, 10, 100.0f, 2.5f, 1.0f, 1.0f, 0.8f, 0.8f);
  audio_play_explosion();
}

static bool enemy_position_occupied(float x, float y, float radius)
{
  for (int i = 0; i < enemy_count; i++) {
    if (circles_collide(x, y, radius, enemies[i].x, enemies[i].y, enemies[i].radius)) {
      return true;
    }
  }

  if (circles_collide(x, y, radius, ship.x, ship.y, ship.radius) ||
      circles_collide(x, y, radius, unloading.x, unloading.y, unloading.radius)) {
    return true;
  }

  return false;
}

static void spawn_enemy(void)
{
  if (enemy_count >= MAX_ENEMIES) {
    return;
  }

  Enemy e = { .angle = 0.0f, .radius = 10.0f };

  do {
    e.x = 20.0f + (float)rand_range(1, (int)LEVEL_WIDTH - 40);
    e.y = 20.0f + (float)rand_range(1, (int)LEVEL_HEIGHT - 40);
  } while (enemy_position_occupied(e.x, e.y, e.radius));

  enemies[enemy_count++] = e;
}

static void enemies_load(void)
{
  enemy_count = 0;

  for (int i = 0; i < INIT_ENEMIES; i++) {
    spawn_enemy();
  }
}

static void enemies_draw(void)
{
  gfx_set_color(1.0f, 0.8f, 0.8f, 1.0f);

  for (int i = 0; i < enemy_count; i++) {
    gfx_polygon_line(enemy_vertices, 4, enemies[i].x, enemies[i].y, enemies[i].angle);
  }
}

/* --------------------------------------------------------- collectables */

static bool collectable_position_occupied(float x, float y, float radius)
{
  for (int i = 0; i < collectables.count; i++) {
    const Collectable *c = &collectables.items[i];
    if (circles_collide(x, y, radius, c->x, c->y, c->radius)) {
      return true;
    }
  }

  if (circles_collide(x, y, radius, ship.x, ship.y, ship.radius) ||
      circles_collide(x, y, radius, unloading.x, unloading.y, unloading.radius)) {
    return true;
  }

  for (int i = 0; i < enemy_count; i++) {
    if (circles_collide(x, y, radius, enemies[i].x, enemies[i].y, enemies[i].radius)) {
      return true;
    }
  }

  return false;
}

static void spawn_collectable(void)
{
  if (collectables.count >= MAX_COLLECTABLES) {
    return;
  }

  Collectable c = { .radius = 5.0f };

  do {
    c.x = 10.0f + (float)rand_range(1, (int)LEVEL_WIDTH - 20);
    c.y = 10.0f + (float)rand_range(1, (int)LEVEL_HEIGHT - 20);
  } while (collectable_position_occupied(c.x, c.y, c.radius));

  list_push(&collectables, c);
}

static void collectables_load(void)
{
  collectables.count = 0;

  for (int i = 0; i < INIT_COLLECTABLES; i++) {
    spawn_collectable();
  }
}

static void collectables_update(void)
{
  for (int i = 0; i < collectables.count; i++) {
    Collectable *c = &collectables.items[i];
    c->x = fmodf(c->x + LEVEL_WIDTH, LEVEL_WIDTH);
    c->y = fmodf(c->y + LEVEL_HEIGHT, LEVEL_HEIGHT);
  }
}

static void collectables_draw(void)
{
  for (int i = 0; i < collectables.count; i++) {
    collectable_draw(&collectables.items[i]);
  }
}

/* ---------------------------------------------------------------- chain */

/* The chain is a rope of links solved with position constraints, the
 * first link pinned to the ship. */
static void chain_load(bool init)
{
  Chain *chain = &ship.chain;

  /* Collectables still hanging on the chain fall back into the level. */
  if (!init) {
    for (int i = 0; i < chain->attached.count; i++) {
      list_push(&collectables, chain->attached.items[i]);
    }
  }

  chain->attached.count = 0;
  chain->joined = true;

  for (int i = 0; i < CHAIN_LENGTH; i++) {
    ChainLink *link = &chain->links[i];
    link->x = link->px = ship.x;
    link->y = link->py = ship.y + (float)i * CHAIN_SEGMENT_LENGTH;
    link->vx = 0.0f;
    link->vy = 0.0f;
  }
}

static void chain_detach(void)
{
  ship.chain.joined = false;
}

static void chain_simulate(float dt)
{
  Chain *chain = &ship.chain;
  float damping = expf(-1.5f * dt);

  for (int i = 0; i < CHAIN_LENGTH; i++) {
    ChainLink *link = &chain->links[i];
    link->vx *= damping;
    link->vy *= damping;
    link->px = link->x;
    link->py = link->y;
    link->x += link->vx * dt;
    link->y += link->vy * dt;
  }

  if (chain->joined) {
    chain->links[0].x = ship.x;
    chain->links[0].y = ship.y;

    for (int iter = 0; iter < CHAIN_SOLVER_ITERATIONS; iter++) {
      for (int i = 0; i < CHAIN_LENGTH - 1; i++) {
        ChainLink *a = &chain->links[i];
        ChainLink *b = &chain->links[i + 1];
        float dx = b->x - a->x;
        float dy = b->y - a->y;
        float distance = sqrtf(dx * dx + dy * dy);

        /* Rope joint: only a maximum distance is enforced. */
        if (distance > CHAIN_SEGMENT_LENGTH && distance > 0.0f) {
          float correction = (distance - CHAIN_SEGMENT_LENGTH) / distance;

          if (i == 0) {
            b->x -= dx * correction;
            b->y -= dy * correction;
          } else {
            a->x += dx * correction * 0.5f;
            a->y += dy * correction * 0.5f;
            b->x -= dx * correction * 0.5f;
            b->y -= dy * correction * 0.5f;
          }
        }
      }
    }
  }

  if (dt > 0.0f) {
    for (int i = 0; i < CHAIN_LENGTH; i++) {
      ChainLink *link = &chain->links[i];
      link->vx = (link->x - link->px) / dt;
      link->vy = (link->y - link->py) / dt;
    }
  }
}

static void spaceship_handle_collision(void);

static void chain_update(float dt)
{
  Chain *chain = &ship.chain;

  chain_simulate(dt);

  for (int s = 0; s < CHAIN_LENGTH; s++) {
    const ChainLink *link = &chain->links[s];

    for (int i = 0; i < enemy_count; i++) {
      if (circles_collide(link->x, link->y, CHAIN_LINK_RADIUS,
                          enemies[i].x, enemies[i].y, enemies[i].radius)) {
        REMOVE_AT(enemies, enemy_count, i);
        spaceship_handle_collision();
        break;
      }
    }
  }

  ChainLink *last = &chain->links[CHAIN_LENGTH - 1];

  /* Pick up a collectable that comes within reach of the last link. */
  for (int i = 0; i < collectables.count; i++) {
    Collectable *c = &collectables.items[i];

    if (circles_collide(last->x, last->y, CHAIN_LINK_RADIUS * 10.0f,
                        c->x, c->y, c->radius * 10.0f)) {
      list_push(&chain->attached, *c);
      REMOVE_AT(collectables.items, collectables.count, i);
      break;
    }
  }

  int count = chain->attached.count;
  float angle_step = count > 0 ? TWO_PI / (float)count : 0.0f;
  float radius = CHAIN_LINK_RADIUS + 10.0f;

  for (int i = 0; i < count; i++) {
    Collectable *c = &chain->attached.items[i];
    float angle = (float)(i + 1) * angle_step;
    collectable_seek(c, last->x + radius * cosf(angle), last->y + radius * sinf(angle),
                     CHAIN_LINK_RADIUS + c->radius, dt);
  }

  /* Deliver everything on the chain to the unloading station. */
  if (circles_collide(last->x, last->y, CHAIN_LINK_RADIUS * 2.0f,
                      unloading.x, unloading.y, unloading.radius * 2.0f)) {
    for (int i = 0; i < chain->attached.count; i++) {
      list_push(&unloading.attached, chain->attached.items[i]);
    }

    chain->attached.count = 0;
  }
}

static void chain_draw(void)
{
  const Chain *chain = &ship.chain;

  gfx_set_color(1.0f, 1.0f, 1.0f, ship.opacity);

  for (int i = 0; i < CHAIN_LENGTH; i++) {
    gfx_circle_line(chain->links[i].x, chain->links[i].y, CHAIN_LINK_RADIUS);
  }

  for (int i = 0; i < chain->attached.count; i++) {
    collectable_draw(&chain->attached.items[i]);
  }
}

/* ------------------------------------------------------------ spaceship */

static void spaceship_explode(void)
{
  particles_create(ship.x, ship.y, 50, 100.0f, 5.0f, 1.0f, 1.0f, 1.0f, 1.0f);
  audio_play_explosion();
  chain_detach();
}

static void spaceship_respawn(void)
{
  spaceship_load(false);
}

static void spaceship_handle_collision(void)
{
  if (ship.dead) {
    return;
  }

  lives--;

  if (lives <= 0) {
    change_state(STATE_GAME_OVER);
  }

  ship.dead = true;
  spaceship_explode();

  set_timeout(spaceship_respawn, 1.0);
}

static void bullets_create(void)
{
  const float SPEED = 300.0f;

  if (ship.bullet_count >= MAX_BULLETS) {
    return;
  }

  Bullet b;
  b.x = ship.x + 15.0f * cosf(ship.angle);
  b.y = ship.y + 15.0f * sinf(ship.angle);
  b.xvel = ship.xvel + cosf(ship.angle) * SPEED;
  b.yvel = ship.yvel + sinf(ship.angle) * SPEED;
  b.angle = ship.angle;
  b.radius = 2.5f;

  float length = sqrtf(b.xvel * b.xvel + b.yvel * b.yvel);
  b.xvel = b.xvel / length * SPEED;
  b.yvel = b.yvel / length * SPEED;

  ship.bullets[ship.bullet_count++] = b;
}

static void bullets_update(float dt)
{
  float half_w = (float)win_w / 2.0f;
  float half_h = (float)win_h / 2.0f;

  for (int i = 0; i < ship.bullet_count;) {
    Bullet *b = &ship.bullets[i];

    b->x += b->xvel * dt;
    b->y += b->yvel * dt;

    for (int e = 0; e < enemy_count; e++) {
      if (circles_collide(b->x, b->y, b->radius, enemies[e].x, enemies[e].y, enemies[e].radius)) {
        enemy_explode(&enemies[e]);
        REMOVE_AT(enemies, enemy_count, e);
        break;
      }
    }

    bool outside = b->x < 0.0f || b->x > LEVEL_WIDTH ||
                   b->y < 0.0f || b->y > LEVEL_HEIGHT ||
                   b->x < camera.x - half_w || b->x > camera.x + half_w ||
                   b->y < camera.y - half_h || b->y > camera.y + half_h;

    if (outside) {
      REMOVE_AT(ship.bullets, ship.bullet_count, i);
    } else {
      i++;
    }
  }
}

static void bullets_draw(void)
{
  gfx_set_color(1.0f, 1.0f, 1.0f, 1.0f);

  for (int i = 0; i < ship.bullet_count; i++) {
    const Bullet *b = &ship.bullets[i];
    gfx_line(bullet_vertices, 2, b->x, b->y, b->angle);
  }
}

static void spaceship_load(bool init)
{
  ship.x = LEVEL_WIDTH / 2.0f;
  ship.y = LEVEL_HEIGHT / 2.0f;
  ship.xvel = 0.0f;
  ship.yvel = 0.0f;
  ship.angle = -SDL_PI_F / 2.0f;
  ship.dead = false;
  ship.opacity = 1.0f;

  camera.x = ship.x;
  camera.y = ship.y;

  ship.bullet_count = 0;
  chain_load(init);
}

static void spaceship_accelerate(float dt)
{
  ship.xvel += cosf(ship.angle) * ship.speed * dt;
  ship.yvel += sinf(ship.angle) * ship.speed * dt;

  float speed = sqrtf(ship.xvel * ship.xvel + ship.yvel * ship.yvel);

  if (speed > ship.speed) {
    ship.xvel = ship.xvel / speed * ship.speed;
    ship.yvel = ship.yvel / speed * ship.speed;
  }
}

static void spaceship_shoot(void)
{
  double t = now_seconds();

  if (t - ship.last_shot_time < 0.2) {
    return;
  }

  bullets_create();
  audio_play_shoot();
  ship.last_shot_time = t;
}

static void spaceship_update(float dt)
{
  const bool *keys = SDL_GetKeyboardState(NULL);

  if (!ship.dead) {
    if (keys[SDL_SCANCODE_RIGHT]) {
      ship.angle += TWO_PI * dt;
    }
    if (keys[SDL_SCANCODE_LEFT]) {
      ship.angle -= TWO_PI * dt;
    }
    if (keys[SDL_SCANCODE_UP]) {
      spaceship_accelerate(dt);
    }
    if (keys[SDL_SCANCODE_SPACE]) {
      spaceship_shoot();
    }
  }

  ship.x += ship.xvel * dt;
  ship.y += ship.yvel * dt;

  if (ship.x < 0.0f || ship.x > LEVEL_WIDTH || ship.y < 0.0f || ship.y > LEVEL_HEIGHT) {
    spaceship_handle_collision();
  }

  camera.x = ship.x;
  camera.y = ship.y;

  bullets_update(dt);
  chain_update(dt);

  for (int i = 0; i < enemy_count; i++) {
    if (circles_collide(ship.x, ship.y, ship.radius, enemies[i].x, enemies[i].y, enemies[i].radius)) {
      enemy_explode(&enemies[i]);
      REMOVE_AT(enemies, enemy_count, i);
      spaceship_handle_collision();
      break;
    }
  }

  if (ship.dead && ship.opacity > 0.0f) {
    ship.opacity -= dt;
  }
}

static void spaceship_draw_thruster(void)
{
  float verts[] = { -30.0f * randf() - 5.0f, 0.0f, -10.0f, -5.0f, -10.0f, 5.0f };
  gfx_set_color(0.8f, 0.8f, 1.0f, ship.opacity);
  gfx_polygon_line(verts, 3, ship.x, ship.y, ship.angle);
}

static void spaceship_draw(void)
{
  const bool *keys = SDL_GetKeyboardState(NULL);

  gfx_set_color(1.0f, 1.0f, 1.0f, ship.opacity);
  gfx_polygon_line(ship_vertices, 3, ship.x, ship.y, ship.angle);

  if (keys[SDL_SCANCODE_UP] && !paused) {
    spaceship_draw_thruster();
  }

  bullets_draw();
  chain_draw();
}

/* ---------------------------------------------------------------- level */

static void load_level(bool init)
{
  stars_load();
  spaceship_load(init);
  unloading_load();
  enemies_load();
  collectables_load();
}

static void next_level(void)
{
  level++;

  if (level > MAX_LEVEL) {
    change_state(STATE_WIN);
  }

  load_level(false);
}

/* -------------------------------------------------------------- playing */

static void playing_load(void)
{
  lives = 3;
  level = 1;
  paused = false;

  load_level(true);
}

static void playing_update(float dt)
{
  const bool *keys = SDL_GetKeyboardState(NULL);

  if (keys[SDL_SCANCODE_ESCAPE]) {
    change_state(STATE_MAIN_MENU);
    return;
  }

  if (paused) {
    return;
  }

  timeouts_update();
  stars_update(dt);
  particles_update(dt);
  collectables_update();
  unloading_update(dt);
  spaceship_update(dt);

  if (unloading.attached.count >= INIT_COLLECTABLES) {
    set_timeout(next_level, 2.0);
  }
}

static void playing_draw(void)
{
  char text[64];

  stars_draw();

  gfx_set_translate((float)win_w / 2.0f - camera.x, (float)win_h / 2.0f - camera.y);

  gfx_set_color(1.0f, 1.0f, 1.0f, 1.0f);
  gfx_rect_line(0.0f, 0.0f, LEVEL_WIDTH, LEVEL_HEIGHT);

  draw_grid();

  particles_draw();
  enemies_draw();
  collectables_draw();
  unloading_draw();
  spaceship_draw();

  gfx_reset_translate();

  gfx_set_color(1.0f, 1.0f, 1.0f, 1.0f);
  snprintf(text, sizeof text, "Collected: %d / %d", unloading.attached.count, INIT_COLLECTABLES);
  gfx_text(text, 10.0f, 10.0f);
  snprintf(text, sizeof text, "Lives: %d", lives);
  gfx_text(text, 10.0f, 40.0f);
  snprintf(text, sizeof text, "Level: %d", level);
  gfx_text(text, 10.0f, 70.0f);
}

/* ---------------------------------------------------------------- menus */

static void menu_update(void)
{
  const bool *keys = SDL_GetKeyboardState(NULL);

  if (keys[SDL_SCANCODE_RETURN]) {
    change_state(STATE_PLAYING);
  }
}

static void menu_draw(const char *title, const char *hint)
{
  float h = gfx_text_height();
  float center_y = (float)win_h / 2.0f;

  gfx_set_color(1.0f, 1.0f, 1.0f, 1.0f);
  gfx_text_centered(title, center_y - h / 1.25f, (float)win_w);
  gfx_text_centered(hint, center_y + h / 1.25f, (float)win_w);
}

/* ----------------------------------------------------------- public API */

void game_init(SDL_Window *win, SDL_Renderer *ren)
{
  window = win;
  renderer = ren;

  SDL_GetRenderOutputSize(renderer, &win_w, &win_h);

  change_state(STATE_MAIN_MENU);
}

void game_update(float dt)
{
  SDL_GetRenderOutputSize(renderer, &win_w, &win_h);

  switch (game_state) {
  case STATE_PLAYING:
    playing_update(dt);
    break;
  case STATE_MAIN_MENU:
  case STATE_GAME_OVER:
  case STATE_WIN:
    menu_update();
    break;
  }
}

void game_draw(void)
{
  switch (game_state) {
  case STATE_PLAYING:
    playing_draw();
    break;
  case STATE_MAIN_MENU:
    menu_draw("Galactic Courier", "Press Enter to start");
    break;
  case STATE_GAME_OVER:
    menu_draw("Game Over", "Press Enter to restart");
    break;
  case STATE_WIN:
    menu_draw("You win!", "Press Enter to restart");
    break;
  }
}

void game_key_pressed(SDL_Keycode key)
{
  if (key == SDLK_F) {
    bool fullscreen = (SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN) != 0;
    SDL_SetWindowFullscreen(window, !fullscreen);
    SDL_GetRenderOutputSize(renderer, &win_w, &win_h);
    stars_load();
  }

  if (key == SDLK_P && game_state == STATE_PLAYING) {
    paused = !paused;
  }
}
