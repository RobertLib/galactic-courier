#include "audio.h"

#include <SDL3/SDL.h>
#include <math.h>
#include <stdlib.h>

#define SAMPLE_RATE 44100

typedef struct {
  SDL_AudioStream *stream;
  float *samples;
  int count;
} Sound;

static Sound shoot_sound;
static Sound explosion_sound;
static bool audio_ready = false;

/* Port of generateShootSound / generateExplosionSound: a decaying sweep
 * built from three harmonics plus a little noise. Only the length differs. */
static bool generate_sound(Sound *sound, float length, float base_frequency, float volume)
{
  int count = (int)(SAMPLE_RATE * length);
  float *samples = (float *)malloc(sizeof(float) * (size_t)count);

  if (!samples) {
    return false;
  }

  for (int i = 0; i < count; i++) {
    float time = (float)i / SAMPLE_RATE;
    float frequency = base_frequency * (1.0f - time);
    float decay = 1.0f - time;
    float amplitude = decay * 0.5f * sinf(2.0f * SDL_PI_F * frequency * time);
    amplitude += 0.3f * decay * sinf(2.0f * SDL_PI_F * (frequency * 1.5f) * time);
    amplitude += 0.2f * decay * sinf(2.0f * SDL_PI_F * (frequency * 2.0f) * time);
    amplitude += 0.1f * (SDL_randf() * 2.0f - 1.0f) * decay;

    /* Clamp the sample to [-1, 1]. */
    if (amplitude > 1.0f) amplitude = 1.0f;
    if (amplitude < -1.0f) amplitude = -1.0f;

    samples[i] = amplitude * volume;
  }

  SDL_AudioSpec spec = { SDL_AUDIO_F32, 1, SAMPLE_RATE };
  SDL_AudioStream *stream =
      SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, NULL, NULL);

  if (!stream) {
    free(samples);
    return false;
  }

  SDL_ResumeAudioStreamDevice(stream);

  sound->stream = stream;
  sound->samples = samples;
  sound->count = count;

  return true;
}

static void destroy_sound(Sound *sound)
{
  if (sound->stream) {
    SDL_DestroyAudioStream(sound->stream);
    sound->stream = NULL;
  }

  free(sound->samples);
  sound->samples = NULL;
  sound->count = 0;
}

static void play_sound(Sound *sound)
{
  if (!audio_ready || !sound->stream) {
    return;
  }

  /* Restart from the beginning, like Source:play() on a static source. */
  SDL_ClearAudioStream(sound->stream);
  SDL_PutAudioStreamData(sound->stream, sound->samples,
                         sound->count * (int)sizeof(float));
}

bool audio_init(void)
{
  if (!generate_sound(&shoot_sound, 0.17f, 760.0f, 0.4f)) {
    return false;
  }

  if (!generate_sound(&explosion_sound, 0.5f, 760.0f, 0.4f)) {
    destroy_sound(&shoot_sound);
    return false;
  }

  audio_ready = true;
  return true;
}

void audio_quit(void)
{
  destroy_sound(&shoot_sound);
  destroy_sound(&explosion_sound);
  audio_ready = false;
}

void audio_play_shoot(void)
{
  play_sound(&shoot_sound);
}

void audio_play_explosion(void)
{
  play_sound(&explosion_sound);
}
