#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <stdio.h>

#include "audio.h"
#include "game.h"
#include "gfx.h"

int main(int argc, char **argv)
{
  (void)argc;
  (void)argv;

  if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO)) {
    fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
    return 1;
  }

  SDL_Window *window = NULL;
  SDL_Renderer *renderer = NULL;

  if (!SDL_CreateWindowAndRenderer("Galactic Courier", WINDOW_WIDTH, WINDOW_HEIGHT,
                                   0, &window, &renderer)) {
    fprintf(stderr, "SDL_CreateWindowAndRenderer failed: %s\n", SDL_GetError());
    SDL_Quit();
    return 1;
  }

  SDL_SetRenderVSync(renderer, 1);
  SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);

  gfx_init(renderer);

  if (!audio_init()) {
    fprintf(stderr, "Audio unavailable: %s\n", SDL_GetError());
  }

  game_init(window, renderer);

  Uint64 last = SDL_GetPerformanceCounter();
  const double freq = (double)SDL_GetPerformanceFrequency();
  bool running = true;

  while (running) {
    SDL_Event event;

    while (SDL_PollEvent(&event)) {
      switch (event.type) {
      case SDL_EVENT_QUIT:
        running = false;
        break;
      case SDL_EVENT_KEY_DOWN:
        if (!event.key.repeat) {
          game_key_pressed(event.key.key);
        }
        break;
      default:
        break;
      }
    }

    Uint64 now = SDL_GetPerformanceCounter();
    float dt = (float)((double)(now - last) / freq);
    last = now;

    /* Avoid huge steps after the window was blocked (e.g. dragging). */
    if (dt > 0.1f) {
      dt = 0.1f;
    }

    game_update(dt);

    SDL_SetRenderDrawColorFloat(renderer, 0.0f, 0.0f, 0.0f, 1.0f);
    SDL_RenderClear(renderer);
    game_draw();
    SDL_RenderPresent(renderer);
  }

  audio_quit();
  gfx_quit();
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  SDL_Quit();

  return 0;
}
