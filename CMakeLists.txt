cmake_minimum_required(VERSION 3.16)
project(galactic_courier C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(SDL3 REQUIRED CONFIG)

add_executable(galactic-courier
  src/main.c
  src/game.c
  src/gfx.c
  src/audio.c
)

target_compile_options(galactic-courier PRIVATE -Wall -Wextra)
target_link_libraries(galactic-courier PRIVATE SDL3::SDL3)

if(NOT APPLE AND NOT WIN32)
  target_link_libraries(galactic-courier PRIVATE m)
endif()
