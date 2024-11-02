#ifndef GAME_H
#define GAME_H

#include <SDL3/SDL.h>

#define WINDOW_WIDTH 800
#define WINDOW_HEIGHT 600

void game_init(SDL_Window *window, SDL_Renderer *renderer);
void game_update(float dt);
void game_draw(void);
void game_key_pressed(SDL_Keycode key);

#endif
