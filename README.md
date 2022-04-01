# zecsi

small framework with raylib bindings and own ECS.

> This project is in an very early experimental state.
> See [https://github.com/ryupold/zecsi-example](https://github.com/ryupold/zecsi-example) to see how to use it

## run locally

```sh
zig build run
```

## build for host os and architecture

```sh
zig build -Drelease-small
```

The output files will be in `./zig-out/bin`

## html5 / emscripten

```sh
EMSDK=../emsdk #path to emscripten sdk

zig build -Drelease-small -Dtarget=wasm32-wasi --sysroot $EMSDK/upstream/emscripten/
```

The output files will be in `./zig-out/web/`

- game.html
- game.js
- game.wasm
- game.data

The game data needs to be served with a webserver. Just opening the game.html in a browser won't work


# TODOs

- [x] Build System
  - [ ] Build as package
  - [x] Windows/Macos
  - [x] WebAssembly
- [-] Raylib
  - [x] Link with game
  - [x] Some bindings
  - [ ] Full API bindings
- [x] ECS
  - [x] Simple ECS
  - [x] Managing Entities, Components & Systems
  - [x] Archetype queries (slow)
- [-] 2D
  - [-] Windows scaling
    - [x] Fullscreen
    - [ ] Aspect Ratio
    - [x] Resizeable window
  - [-] Grid
    - [x] Quad grid
    - [ ] Hexa grid
  - [-] Draw textures
    - [x] Texture atlas (animated)
    - [ ] Tile Map (slow)
    - [ ] Tile Map (fast)
  - [x] Camera 2D
  - [ ] Particle Effects
- [x] Asset ReLoader
- [ ] Sound system
- [ ] Input system
- [ ] Physics system
- [ ] UI system
- [ ] Scene switch
- [ ] Menu
- [ ] Netcode
- [ ] Window Icon
