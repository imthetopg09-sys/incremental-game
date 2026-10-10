# Midnight, Again

A time-looped lamplighter holds a dying city through one endless night. Every death comes back as an Echo that replays your run and fights beside you.

## Play

**[Download MidnightAgain.exe](https://github.com/imthetopg09-sys/incremental-game/releases/latest/download/MidnightAgain.exe)** and double-click it. The link always serves the newest build.

Windows may say it protected your PC because the game isn't signed yet. Click **More info**, then **Run anyway**.

## How to play

- Steer the lantern with the mouse, or WASD. Your light burns shadows; their touch drains your flame.
- When the flame goes out, the night starts again, and your last run walks beside you as an Echo with a far hotter light. Lead the shadows into your Echoes.
- Burning shadows fills the embers line: each level offers three Boons. Your Echoes take the same Boons at the same moments.
- Between nights, spend Tallow on the Lamp Tree and braid Echoes into a Chorus to free a Sconce.
- Hold the night until 6:00 AM to see the first Dawn. While the game is closed, your Echoes keep watch and earn Tallow.
- Esc pauses. P on the end screen saves a postcard of your routes to your Pictures folder.

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
