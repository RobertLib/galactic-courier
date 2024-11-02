# Simple alternative to CMake: `make` builds ./galactic-courier using pkg-config.
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11
CFLAGS  += $(shell pkg-config --cflags sdl3)
LDFLAGS += $(shell pkg-config --libs sdl3) -lm

SRC = src/main.c src/game.c src/gfx.c src/audio.c
OBJDIR = build
OBJ = $(patsubst src/%.c,$(OBJDIR)/%.o,$(SRC))

galactic-courier: $(OBJ)
	$(CC) $(OBJ) -o $@ $(LDFLAGS)

$(OBJDIR)/%.o: src/%.c src/game.h src/gfx.h src/audio.h | $(OBJDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR):
	mkdir -p $(OBJDIR)

run: galactic-courier
	./galactic-courier

clean:
	rm -rf $(OBJDIR) galactic-courier

.PHONY: run clean
