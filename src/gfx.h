#ifndef GFX_H
#define GFX_H

#include <SDL3/SDL.h>
#include <stdbool.h>

/* Thin drawing layer over SDL_Renderer: current color, a translation
 * offset, line/fill circles, transformed polygons, points, and bitmap text. */

void gfx_init(SDL_Renderer *renderer);
void gfx_quit(void);

void gfx_set_color(float r, float g, float b, float a);

/* Absolute translation applied to all world-space primitives. */
void gfx_set_translate(float x, float y);
void gfx_reset_translate(void);

void gfx_circle_line(float x, float y, float radius);
void gfx_circle_fill(float x, float y, float radius);

/* verts holds n (x, y) pairs in local space; they are rotated by angle
 * and moved to (x, y) before drawing. */
void gfx_polygon_line(const float *verts, int n, float x, float y, float angle);
void gfx_line(const float *verts, int n, float x, float y, float angle);

void gfx_points(const SDL_FPoint *points, int n);
void gfx_rect_line(float x, float y, float w, float h);

/* Built-in 5x7 bitmap font scaled up; text is drawn in screen space. */
float gfx_text_height(void);
float gfx_text_width(const char *text);
void gfx_text(const char *text, float x, float y);
void gfx_text_centered(const char *text, float y, float width);

#endif
