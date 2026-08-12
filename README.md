# Pusoy Dos

A full-featured **Pusoy Dos (Filipino Big Two)** card game built with **Godot 4.6** (GDScript, Forward Plus renderer) - no external dependencies, no plugins.

Play against AI opponents at three difficulties, or dive into the **Story Campaign**, **Puzzle Challenges**, and **Achievement** collection.

## Features

- Cards: Classic Pusoy Dos gameplay with Filipino ranking rules, plus a BIG_TWO rules variant
- AI: 3 difficulty levels (EASY / MEDIUM / HARD) with distinct play styles
- Story: 9-chapter campaign (ch1-ch9) with themed Filipino characters and dialogue
- Puzzles: 6 curated boards (pz1_warmup, pz2_efficiency, pz3_signature, pz4_finalboss, pz_2trap, pz_bullets)
- Achievements: 8 unlockable achievements tracked by a persistent stats system
- Tutorial: in-game onboarding (TutorialManager) plus a help overlay (HelpModal)
- Theming: ThemeManager / UIFactory styling with smooth TransitionManager transitions
- Responsive UI: canvas_items stretch scaling; the fan layout handles full hands

## Getting Started

### Requirements

- Godot 4.6 or newer (4.x) - https://godotengine.org/download

### Run from the editor

1. Clone or download: git clone https://github.com/plansigan/pusoy-dos.git
2. Open the Godot Project Manager -> Import -> select project.godot
3. Press F5 (or Play) - the main scene (Main.tscn) opens to the main menu

## Testing

No test framework needed - the suite runs headless from a scene. Use the console build of Godot so stdout is visible.

| Scene | What it verifies |
|---|
| res://HeadlessTest.tscn | Full suite: suit rankings (FILIPINO and BIG_TWO), stats/rating, story logic, puzzles and achievements, 30 AI-vs-AI games (10 x EASY/MEDIUM/HARD) |
| res://FanTest.tscn | Fan layout and hand-spacing logic |
| res://StoryBoot.tscn | Story mode boots into a real match |
| res://PuzzleBoot.tscn | Puzzle mode boots into a real match |

Full test suite:

    "path/to/Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://HeadlessTest.tscn --quit-after 2000

Expected: HEADLESS TEST PASSED - 30/30 games completed, all logic checks OK (exit code 0).

Smoke boots (per CLAUDE.md):

    "$GODOT" --headless --fixed-fps 60 res://StoryBoot.tscn --quit-after 900
    "$GODOT" --headless --fixed-fps 60 res://PuzzleBoot.tscn --quit-after 700

> Note: boot scenes exit with benign "ObjectDB instances leaked" / "resources still in use" warnings because --quit-after force-stops the process mid-match. Expected - not failures.

## Project Structure

    pusoy-dos/
    |-- project.godot             # Godot project config (main scene, autoloads, stretch)
    |-- Main.tscn / MainMenu.gd   # Entry point and main menu
    |-- GameTable.gd              # Core game screen (turns, moves, UI)
    |-- AIPlayer.gd               # AI: EASY / MEDIUM / HARD + story-role personalities
    |-- HandEvaluator.gd          # Static rule logic: hand combos + rank variants
    |-- HandFan.gd                # Responsive hand fan layout
    |-- ContentManager.gd         # Loads all content JSON (stories, puzzles, characters)
    |-- StoryManager.gd           # Story campaign state machine
    |-- PuzzleManager.gd          # Puzzle challenge logic
    |-- AchievementManager.gd     # Achievement definitions and checks
    |-- GameSession.gd            # Session state
    |-- StatsManager.gd           # Persistent stats and ratings (isolated test saves)
    |-- Settings.gd               # User settings persistence (autoload)
    |-- FeatureFlags.gd           # Feature toggles (autoload)
    |-- ThemeManager.gd           # UI theming (autoload)
    |-- SoundManager.gd           # Audio (autoload)
    |-- TransitionManager.gd      # Screen transitions (autoload)
    |-- PixelFilter.gd            # Pixel-art filter (autoload)
    |-- TutorialManager.gd        # Onboarding flow
    |-- HelpModal.gd              # In-game help overlay
    |-- UIFactory.gd              # Shared UI builders
    |-- content/
    |   |-- achievements/         # 8 achievement definitions (JSON)
    |   |-- characters/           # 9 story characters (JSON)
    |   |-- puzzles/              # 6 puzzle boards (JSON)
    |   |-- stories/              # 9 story chapters ch1-ch9 (JSON)
    |   `-- tutorial/             # Tutorial section content
    `-- *Test.tscn / *Boot.tscn   # Headless test and smoke scenes

## Game Modes

- Classic - standard Pusoy Dos vs AI; pick difficulty (EASY / MEDIUM / HARD)
- Story - 9-chapter campaign; characters have distinct personalities and dialogue
- Puzzles - solve specific hand situations with the best play
- Achievements - persistent unlocks tracked across sessions

## Authoring Content

All story chapters, puzzles, characters, and achievements are plain JSON under content/. Add a new file (e.g. content/stories/ch10.json) and hook it into ContentManager to extend the game - no engine recompile needed.

## Architecture Notes

- Pure GDScript; no external dependencies or plugins.
- Core rule logic lives in static class_name scripts (not autoloads) so headless tests can drive them directly - a deliberate design rule, see CLAUDE.md.
- Tests isolate each manager by swapping its save_path to user://*_test.cfg and restoring afterward.
- Suit-ranking variant (FILIPINO / BIG_TWO) is a first-class feature exercised by both tests and AI.
- All commands, conventions, and the Godot console path are documented in CLAUDE.md.
