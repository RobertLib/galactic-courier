# Galactic Courier

A small 2D arcade game written in C with SDL3. You fly a ship that tows a
chain, collect containers with it and deliver them to the unloading station.
Avoid the enemies or shoot them down.

There are no dependencies other than SDL3: the chain physics, the sound
effects and the font are all built in.

## Controls

| Key           | Action                        |
| ------------- | ----------------------------- |
| Left / Right  | rotate the ship               |
| Up            | thrust                        |
| Space         | shoot                         |
| P             | pause                         |
| F             | toggle fullscreen             |
| Enter         | start / restart               |
| Esc           | back to the main menu         |

## Building

Requires a C11 compiler and SDL3 (`brew install sdl3`, `apt install libsdl3-dev`, ...).

### CMake

```sh
cmake -S . -B build
cmake --build build
./build/galactic-courier
```

### Makefile (pkg-config)

```sh
make        # build
make run    # build and run
```

## Layout

- `src/main.c` – SDL setup, main loop, event handling
- `src/game.c` – all gameplay logic (states, ship, chain, enemies, pickups, HUD)
- `src/gfx.c` – drawing layer over `SDL_Renderer` (circles, polygons, bitmap font)
- `src/audio.c` – procedurally generated sounds played through SDL audio streams
