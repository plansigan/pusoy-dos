# GameSession.gd
# Carries the chosen mode from the menu into the game scene.
# Static (like RulesManager) so it needs no autoload and stays
# available to headless tests.

class_name GameSession

enum Mode { CASUAL, RANKED, STORY, PUZZLE, TUTORIAL }

static var mode: int = Mode.CASUAL
static var casual_difficulty: int = AIPlayer.Difficulty.MEDIUM

# Set when mode == STORY
static var story_chapter_id: String = ""
static var story_skip_intro: bool = false   # true on a retry after losing
static var return_to_story: bool = false     # MainMenu reopens the story list

# Set when mode == PUZZLE
static var puzzle_id: String = ""
static var return_to_puzzles: bool = false   # MainMenu reopens the puzzle list
