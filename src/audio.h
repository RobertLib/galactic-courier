#ifndef AUDIO_H
#define AUDIO_H

#include <stdbool.h>

/* Procedurally generated sound effects played through SDL3 audio streams. */

bool audio_init(void);
void audio_quit(void);

void audio_play_shoot(void);
void audio_play_explosion(void);

#endif
