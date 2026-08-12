# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Pusoy Dos (Filipino Big Two variant) — a Godot 4.6 game, pure GDScript, no external dependencies. All UI is built programmatically in code (the `.tscn` files are tiny roots); content (characters, stories, puzzles, achievements) is data-driven from JSON.

## Commands

Godot is **not on PATH**. Use the console exe (captures stdout, needed to see test results):

```bash
GODOT="C:/Users/paolo/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe"
```

- Run the game: `"$GODOT" --path .` (main scene is `MainMenu.tscn`)
- Run the test suite: `"$GODOT" --headless --path . res://HeadlessTest.tscn --quit-after 2000`
  - Logic + rules, stats/rating, story, puzzles/achievements, and 30 AI-vs-AI games (10 × 3 difficulties).
  - **Always run tests as a scene, never via `--script`** — `--script` serves stale bytecode for freshly-edited `class_name` scripts.
  - Prints `HEADLESS TEST PASSED` on success; exits 0 on pass, 1 on failure.
- Hand fan UI test: `"$GODOT" --headless --path . res://FanTest.tscn`
- Headless smoke tests that boot the real GameTable path (stall at the human's turn by design):
  - Story: `"$GODOT" --headless --fixed-fps 60 res://StoryBoot.tscn --quit-after 900`
  - Puzzle: `"$GODOT" --headless --fixed-fps 60 res://PuzzleBoot.tscn --quit-after 700`

## Architecture

**Core rule logic lives in static `class_name` scripts, not autoloads**, so the headless tests (which run without autoloads) can drive them directly. This is a deliberate, repeated design rule ("Static like the rest so headless tests work").

- `Card.gd`, `Deck.gd`, `HandEvaluator.gd` — card model, deck, play-type validation/comparison.
- `GameManager.gd` — game-flow state machine: turn order, play/pass, table clearing, win detection. Its `setup_game(preset_hands)` accepts a stacked deal for story/puzzle/tutorial.
- `RulesManager.gd` — configurable suit hierarchy: `SuitRanking.FILIPINO` (2♦ boss) vs `BIG_TWO` (2♠ boss). `Card.beats()` goes through it. `Settings` pushes the persisted choice at boot; `GameTable` re-applies it at game start.
- `AIPlayer.gd` — EASY/MEDIUM/HARD via a priority system. Story roles keyed by player id: `ALLY` protects the human (passes over their plays, blocks the rival), `RIVAL2` targets the human. Puzzles force `deterministic = true` so solved lines replay (EASY otherwise misplays at random).
- `GameSession.gd` — static carrier for the chosen mode (`CASUAL, RANKED, STORY, PUZZLE, TUTORIAL`) and per-mode ids from menu into `GameTable`.

**Persistence managers** (all static, all write `ConfigFile` to `user://*.cfg` synchronously — a ranked forfeit must be on disk before the process exits):
- `StatsManager` (rating/rank/streak, records, match history), `StoryManager` (chapter completion/rewards), `PuzzleManager` (solved + best-play par), `AchievementManager` (data-driven, evaluates conditions against the other managers + a transient event context).

**Autoloads** (order matters — see `project.godot`): `Settings` (user settings, first so others can read it) → `FeatureFlags` → `ThemeManager` → `SoundManager` → `TransitionManager` → `PixelFilter`.

- `FeatureFlags` gates staged launches: `story` and `puzzles` are **off by default**. Enable locally via `user://dev_flags.cfg` (`[flags] story=true`), which overrides the hardcoded `FLAGS`.
- `ThemeManager` — color themes; `TransitionManager` — the one motion system: dip-to-dark scene changes, modal open/close, toasts, achievement banners, staggering. `UIFactory` — shared styleboxes/labels/buttons.

**Screens**: each is a `.gd` with a static `.open(parent)` entry point that builds its whole UI (`MainMenu`, `ModeSelect`, `StoryScreen`, `PuzzleScreen`, `StatsScreen`, `SettingsMenu`, `AchievementsScreen`, `DialogueScreen`, `HelpModal`, `WinScreen`). `GameTable.gd` (~1600 lines) is the entire game screen — layout, input, animations, win screen — with `HandFan` owning all hand input via a small press/click/drag state machine and `AvatarSlot`/`CardUI` as the visual seats/cards.

**Content system**: JSON in `res://content/{characters,stories,puzzles,achievements,tutorial}` loaded/validated by `ContentManager`. Design rule: a malformed file is logged with a clear reason and **skipped** — it never crashes the game and never silently drops content. Card codes are like `"3C"` / `"10H"`; a stacked `deal` must be exactly 52 unique cards across `player/rival/seat3/seat4`. New content is added as JSON — see `content/` samples; `ContentManager` fills optional blocks so consumers don't key-check.

## Conventions

- Keep new stateful logic in static `class_name` scripts so tests run headless; use autoloads only for Node-scoped singletons (settings, audio, UI transitions).
- When writing tests, isolate each manager by swapping its `save_path` to a `user://*_test.cfg`, calling `reset_all()`, and restoring both afterward (see `HeadlessTest.gd`).
- The suit-ranking variant is a first-class feature: tests and AI exercise both `FILIPINO` and `BIG_TWO`.
- Story/puzzle features ship behind `FeatureFlags`; don't assume they're reachable from the menu without the dev override.
