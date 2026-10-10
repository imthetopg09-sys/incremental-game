# Midnight, Again

A time-looped lamplighter holds a dying city through one endless night. Every death comes back as an Echo that replays your run and fights beside you.

## Play

**[Download MidnightAgain.exe](https://github.com/imthetopg09-sys/incremental-game/releases/latest/download/MidnightAgain.exe)** and double-click it. The link always serves the newest build.

Windows may say it protected your PC because the game isn't signed yet. Click **More info**, then **Run anyway**.

## Develop

The game is a [Godot 4.7](https://godotengine.org/) project in `game/`. Open `game/project.godot` in the Godot editor, or from a terminal:

```sh
godot --path game                                   # run the game
godot --headless --path game -s res://tests/run_tests.gd   # run tests
godot --headless --path game --export-release "Windows Desktop" ../build/windows/MidnightAgain.exe
```

Every push runs the tests, builds the Windows .exe and launches it once on a Windows machine. Pushes to the default branch publish it to the download link above (see `.github/workflows/build.yml`).

```
game/
  scenes/    Godot scenes
  scripts/   gameplay scripts
  shaders/   canvas shaders (the lantern light)
  assets/    icon and art
  tests/     headless tests (test_*.gd), run by tests/run_tests.gd
```
