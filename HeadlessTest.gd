# HeadlessTest.gd
# Logic + rules tests plus AI-vs-AI games, no UI. Run as a SCENE (not
# --script) so freshly-edited class_name scripts compile clean:
#   godot --headless --path . res://HeadlessTest.tscn --quit-after 2000
# (Running via --script can serve stale bytecode for edited globals.)
extends Node

const GAMES_PER_DIFFICULTY = 10
const MAX_TURNS = 500  # safety net against infinite loops

func _ready() -> void:
	var failures = _test_suit_ranking_rules()
	failures += _test_stats_and_rating()
	failures += _test_story_logic()
	failures += _test_puzzles_and_achievements()
	var games_failed = 0
	for difficulty in [AIPlayer.Difficulty.EASY, AIPlayer.Difficulty.MEDIUM, AIPlayer.Difficulty.HARD]:
		for game_num in GAMES_PER_DIFFICULTY:
			# Exercise both suit hierarchies across the batch
			RulesManager.set_ranking(game_num % 2)
			if not _play_one_game(game_num, difficulty):
				games_failed += 1
	RulesManager.set_ranking(RulesManager.SuitRanking.FILIPINO)
	failures += games_failed

	var total = GAMES_PER_DIFFICULTY * 3
	if failures == 0:
		print("HEADLESS TEST PASSED — %d/%d games completed, all logic checks OK" % [total, total])
	else:
		print("HEADLESS TEST FAILED — %d failing checks (%d games unfinished)" % [failures, games_failed])
	get_tree().quit(0 if failures == 0 else 1)


# Ranked rating rules, rank thresholds, forfeit, casual isolation,
# and persistence — run against an isolated test save file
func _test_stats_and_rating() -> int:
	var fails = 0
	StatsManager.save_path = "user://stats_test.cfg"
	StatsManager.reset_all()

	# Fresh profile: 0 rating → Rookie → EASY AI
	if StatsManager.get_rank_name() != "Rookie" \
			or StatsManager.ranked_difficulty() != AIPlayer.Difficulty.EASY:
		fails += 1
		print("FAIL stats: fresh profile should be Rookie with EASY AI")

	# Plain win +20, streak starts
	StatsManager.record_ranked_win(false, false, 10)
	if StatsManager.rating != 20 or StatsManager.streak != 1:
		fails += 1
		print("FAIL stats: first win should give rating 20, streak 1")

	# Win with everything: 20 + 15 flawless + 5 streak + 10 SF = 50 → 70
	StatsManager.record_ranked_win(true, true, 8)
	if StatsManager.rating != 70:
		fails += 1
		print("FAIL stats: bonus win should reach rating 70, got %d" % StatsManager.rating)
	if StatsManager.fastest_win_turns != 8 or StatsManager.flawless_wins != 1:
		fails += 1
		print("FAIL stats: global records not updated on win")

	# Loss -10, streak resets
	var loss_delta = StatsManager.record_ranked_loss()
	if loss_delta != -10 or StatsManager.rating != 60 or StatsManager.streak != 0:
		fails += 1
		print("FAIL stats: loss should be -10 and reset streak")

	# Rating floor at 0
	StatsManager.reset_all()
	StatsManager.record_ranked_loss()
	if StatsManager.rating != 0:
		fails += 1
		print("FAIL stats: rating must floor at 0, got %d" % StatsManager.rating)

	# Streak bonus caps at +25
	StatsManager.reset_all()
	var last_breakdown: Array = []
	for i in 8:
		last_breakdown = StatsManager.record_ranked_win(false, false, 0)
	var cap_ok = false
	for entry in last_breakdown:
		if entry["label"].begins_with("streak") and entry["delta"] == 25:
			cap_ok = true
	if not cap_ok:
		fails += 1
		print("FAIL stats: streak bonus should cap at +25")

	# Rank thresholds → AI difficulty
	StatsManager.rating = 250
	if StatsManager.get_rank_name() != "Street King" \
			or StatsManager.ranked_difficulty() != AIPlayer.Difficulty.MEDIUM:
		fails += 1
		print("FAIL stats: 250 rating should be Street King / MEDIUM")
	StatsManager.rating = 600
	var pro_difficulty = StatsManager.ranked_difficulty()
	if pro_difficulty != AIPlayer.Difficulty.MEDIUM and pro_difficulty != AIPlayer.Difficulty.HARD:
		fails += 1
		print("FAIL stats: Card Shark difficulty must be MEDIUM or HARD")
	StatsManager.rating = 2200
	if StatsManager.get_rank_index() != 4 \
			or StatsManager.ranked_difficulty() != AIPlayer.Difficulty.HARD:
		fails += 1
		print("FAIL stats: 2200 rating should be The Legend / HARD")

	# Forfeit: -10, streak gone, history entry tagged
	StatsManager.rating = 100
	StatsManager.streak = 3
	StatsManager.record_forfeit()
	if StatsManager.rating != 90 or StatsManager.streak != 0 \
			or StatsManager.match_history[0]["result"] != "forfeit" \
			or StatsManager.match_history[0]["mode"] != "ranked":
		fails += 1
		print("FAIL stats: forfeit should cost 10 rating, reset streak, tag history")

	# Casual never touches rating or streak
	var rating_before = StatsManager.rating
	StatsManager.record_casual(true, false, 12)
	if StatsManager.rating != rating_before or StatsManager.casual_wins != 1 \
			or StatsManager.casual_games != 1 \
			or StatsManager.match_history[0]["mode"] != "casual":
		fails += 1
		print("FAIL stats: casual game leaked into rating or wasn't tallied")

	# Persistence round-trip
	StatsManager.save()
	var saved_rating = StatsManager.rating
	StatsManager.rating = -999
	StatsManager.reload_from_disk()
	if StatsManager.rating != saved_rating:
		fails += 1
		print("FAIL stats: persistence round-trip lost the rating")

	# Clean up the test file and return to the real profile
	DirAccess.remove_absolute(StatsManager.save_path)
	StatsManager.save_path = "user://stats.cfg"
	StatsManager.reload_from_disk()

	if fails == 0:
		print("STATS & RATING RULES OK")
	return fails


# Puzzle content + objective checks, and data-driven achievements
func _test_puzzles_and_achievements() -> int:
	var fails = 0
	# Load the script fresh: in headless runs the global class name can
	# serve stale bytecode for a recently-edited script, but its static
	# state is shared, so this populates what the managers read.
	var CM = load("res://ContentManager.gd")
	CM.reload()

	if CM.puzzles.size() != 4:
		fails += 1
		print("FAIL puzzle: expected 4 puzzles, got %d" % CM.puzzles.size())
	if CM.achievements.size() != 8:
		fails += 1
		print("FAIL ach: expected 8 achievements, got %d" % CM.achievements.size())

	# Objective evaluation
	if not PuzzleManager.objective_met({"type": "win"}, true, 5, "SINGLE"):
		fails += 1
		print("FAIL objective: plain win should pass")
	if PuzzleManager.objective_met({"type": "win"}, false, 5, "SINGLE"):
		fails += 1
		print("FAIL objective: losing should never meet a win objective")
	if not PuzzleManager.objective_met({"type": "win_in", "value": 8}, true, 8, "PAIR"):
		fails += 1
		print("FAIL objective: win in exactly par should pass")
	if PuzzleManager.objective_met({"type": "win_in", "value": 8}, true, 9, "PAIR"):
		fails += 1
		print("FAIL objective: over par should fail")
	if not PuzzleManager.objective_met({"type": "win_with", "value": "STRAIGHT_FLUSH"}, true, 5, "STRAIGHT_FLUSH"):
		fails += 1
		print("FAIL objective: matching final play should pass")
	if PuzzleManager.objective_met({"type": "win_with", "value": "STRAIGHT_FLUSH"}, true, 5, "FLUSH"):
		fails += 1
		print("FAIL objective: wrong final play should fail")

	# Puzzle progression
	PuzzleManager.save_path = "user://puzzles_test.cfg"
	PuzzleManager.reset_all()
	if not PuzzleManager.is_unlocked("pz1_warmup"):
		fails += 1
		print("FAIL puzzle: pz1 should be unlocked fresh")
	if PuzzleManager.is_unlocked("pz2_efficiency"):
		fails += 1
		print("FAIL puzzle: pz2 should be locked before pz1")
	PuzzleManager.mark_solved("pz1_warmup", 7)
	if not PuzzleManager.mark_solved("pz1_warmup", 5):
		fails += 1
		print("FAIL puzzle: 5 plays should be a new best over 7")
	if PuzzleManager.best_for("pz1_warmup") != 5:
		fails += 1
		print("FAIL puzzle: best should be 5, got %d" % PuzzleManager.best_for("pz1_warmup"))
	if not PuzzleManager.is_unlocked("pz2_efficiency"):
		fails += 1
		print("FAIL puzzle: pz2 should unlock after pz1 solved")
	PuzzleManager.reload_from_disk()
	if not PuzzleManager.is_solved("pz1_warmup"):
		fails += 1
		print("FAIL puzzle: solve lost across reload")

	# Achievements — isolate every manager they read
	StatsManager.save_path = "user://stats_ach_test.cfg"
	StatsManager.reset_all()
	StoryManager.save_path = "user://story_ach_test.cfg"
	StoryManager.reset_all()
	AchievementManager.save_path = "user://ach_test.cfg"
	AchievementManager.reset_all()

	if not AchievementManager.evaluate({}).is_empty():
		fails += 1
		print("FAIL ach: fresh profile should unlock nothing")
	StatsManager.record_casual(true, false, 10)
	if not _has_ach(AchievementManager.evaluate({}), "first_win"):
		fails += 1
		print("FAIL ach: first_win should unlock after a win")
	if not AchievementManager.evaluate({}).is_empty():
		fails += 1
		print("FAIL ach: already-unlocked achievements must not re-fire")
	if not _has_ach(AchievementManager.evaluate({"straight_flush_finish": true}), "grand_finale"):
		fails += 1
		print("FAIL ach: grand_finale should unlock on the SF-finish event")
	PuzzleManager.mark_solved("pz2_efficiency", 6)
	PuzzleManager.mark_solved("pz3_signature", 6)
	PuzzleManager.mark_solved("pz4_finalboss", 6)
	if not _has_ach(AchievementManager.evaluate({}), "puzzle_solver"):
		fails += 1
		print("FAIL ach: puzzle_solver should unlock at 4 solved")
	AchievementManager.reload_from_disk()
	if not AchievementManager.is_unlocked("first_win"):
		fails += 1
		print("FAIL ach: unlock lost across reload")

	# Clean up test files and restore the real profiles
	for path in ["user://puzzles_test.cfg", "user://stats_ach_test.cfg",
			"user://story_ach_test.cfg", "user://ach_test.cfg"]:
		DirAccess.remove_absolute(path)
	PuzzleManager.save_path = "user://puzzles.cfg"
	PuzzleManager.reload_from_disk()
	StatsManager.save_path = "user://stats.cfg"
	StatsManager.reload_from_disk()
	StoryManager.save_path = "user://story.cfg"
	StoryManager.reload_from_disk()
	AchievementManager.save_path = "user://achievements.cfg"
	AchievementManager.reload_from_disk()

	if fails == 0:
		print("PUZZLES & ACHIEVEMENTS OK")
	return fails


func _has_ach(unlocked: Array, id: String) -> bool:
	for achievement in unlocked:
		if String(achievement.get("id", "")) == id:
			return true
	return false


# Story content, stacked deals, ally/rival2 AI roles, progression
func _test_story_logic() -> int:
	var fails = 0
	RulesManager.set_ranking(RulesManager.SuitRanking.FILIPINO)
	ContentManager.reload()

	# Content loaded cleanly, no validation errors on the samples
	if not ContentManager.load_errors.is_empty():
		fails += 1
		print("FAIL story: content load errors: %s" % str(ContentManager.load_errors))
	for id in ["lolo_carding", "ate_marites", "generic_1"]:
		if not ContentManager.has_character(id):
			fails += 1
			print("FAIL story: character '%s' not loaded" % id)

	# A deliberately broken deal must be rejected with a clear reason
	var bad = {"player": ["3C", "3C"], "rival": [], "seat3": [], "seat4": []}
	if ContentManager._validate_deal(bad).is_empty():
		fails += 1
		print("FAIL story: duplicate/short deal should be rejected")

	# Stacked deal: exactly 52 cards, player holds 3♣ and therefore leads
	var ch2 = ContentManager.get_chapter("ch2_kalsada")
	var hands = ContentManager.deal_to_hands(ch2)
	var gm = GameManager.new()
	gm.setup_game(hands)
	for i in 4:
		if gm.players[i].hand.size() != 13:
			fails += 1
			print("FAIL story: stacked hand %d has %d cards" % [i, gm.players[i].hand.size()])
	if gm.current_player_index != 0:
		fails += 1
		print("FAIL story: player holding 3♣ should lead, got seat %d" % gm.current_player_index)

	# ALLY must NOT beat the human's table-winning play (passing is legal)
	var three_d = Card.new("3", Card.Suit.DIAMONDS)
	var ally_gm = GameManager.new()
	ally_gm.setup_game()
	var ai = AIPlayer.new(ally_gm)
	ai.role_by_id[2] = AIPlayer.Role.ALLY
	ai.rival_id = 1
	ally_gm.table_cards = [three_d]
	ally_gm.last_player_index = 0            # the human's play is on top
	ally_gm.current_player_index = 2
	ally_gm.players[2].hand = _typed_hand([Card.new("K", Card.Suit.SPADES), Card.new("Q", Card.Suit.SPADES)])
	if ai.take_turn(ally_gm.players[2]):
		fails += 1
		print("FAIL story: ally beat the player's play instead of passing")
	if ally_gm.table_cards.size() != 1 or ally_gm.table_cards[0] != three_d:
		fails += 1
		print("FAIL story: ally changed the table while protecting the player")

	# ...but an ally SHOULD take a winning play (go out) over the player
	var win_gm = GameManager.new()
	win_gm.setup_game()
	var ai2 = AIPlayer.new(win_gm)
	ai2.role_by_id[2] = AIPlayer.Role.ALLY
	ai2.rival_id = 1
	win_gm.table_cards = [three_d]
	win_gm.last_player_index = 0
	win_gm.current_player_index = 2
	win_gm.players[2].hand = _typed_hand([Card.new("K", Card.Suit.SPADES)])
	if not ai2.take_turn(win_gm.players[2]) or not win_gm.game_over:
		fails += 1
		print("FAIL story: ally should take the winning play to go out")

	# RIVAL2 targets the human — beats their play when it can
	var r2_gm = GameManager.new()
	r2_gm.setup_game()
	var ai3 = AIPlayer.new(r2_gm)
	ai3.role_by_id[3] = AIPlayer.Role.RIVAL2
	r2_gm.table_cards = [three_d]
	r2_gm.last_player_index = 0
	r2_gm.current_player_index = 3
	r2_gm.players[3].hand = _typed_hand([Card.new("K", Card.Suit.SPADES), Card.new("Q", Card.Suit.SPADES)])
	if not ai3.take_turn(r2_gm.players[3]):
		fails += 1
		print("FAIL story: rival2 should beat the player's play")

	# Progression: fresh profile → ch1 open, ch2 locked; finishing ch1 unlocks ch2
	StoryManager.save_path = "user://story_test.cfg"
	StoryManager.reset_all()
	if not StoryManager.is_unlocked("ch1_bahay"):
		fails += 1
		print("FAIL story: ch1 should be unlocked on a fresh profile")
	if StoryManager.is_unlocked("ch2_kalsada"):
		fails += 1
		print("FAIL story: ch2 should be locked before ch1 is done")
	StoryManager.complete_chapter("ch1_bahay")
	StoryManager.complete_chapter("ch1_bahay")  # replay — rewards must not re-grant
	if StoryManager.unlocked.count("ch2_kalsada") != 1:
		fails += 1
		print("FAIL story: ch2 should be unlocked exactly once after replaying ch1")
	if not StoryManager.is_unlocked("ch2_kalsada"):
		fails += 1
		print("FAIL story: ch2 should be unlocked after finishing ch1")

	# Persistence round-trip
	StoryManager.reload_from_disk()
	if not StoryManager.is_completed("ch1_bahay"):
		fails += 1
		print("FAIL story: completion lost across reload")
	DirAccess.remove_absolute(StoryManager.save_path)
	StoryManager.save_path = "user://story.cfg"
	StoryManager.reload_from_disk()

	if fails == 0:
		print("STORY LOGIC OK")
	return fails


func _typed_hand(cards: Array) -> Array[Card]:
	var typed: Array[Card] = []
	typed.assign(cards)
	return typed


# The configurable suit hierarchy: Filipino 2♦ high, Big Two 2♠ high
func _test_suit_ranking_rules() -> int:
	var fails = 0
	var two_diamonds = Card.new("2", Card.Suit.DIAMONDS)
	var two_spades = Card.new("2", Card.Suit.SPADES)
	var two_hearts = Card.new("2", Card.Suit.HEARTS)
	var deck = Deck.new()

	RulesManager.set_ranking(RulesManager.SuitRanking.FILIPINO)
	if not two_diamonds.beats(two_hearts):
		fails += 1
		print("FAIL Filipino: 2♦ should beat 2♥")
	if not two_hearts.beats(two_spades):
		fails += 1
		print("FAIL Filipino: 2♥ should beat 2♠")
	if deck.cards.size() != 52:
		fails += 1
		print("FAIL: deck should hold 52 cards, has %d" % deck.cards.size())
	var sorted = Card.sort_cards(deck.cards)
	if sorted[0].rank != "3" or sorted[0].suit != Card.Suit.CLUBS:
		fails += 1
		print("FAIL Filipino: lowest card should be 3♣, got " + sorted[0].card_name())
	if sorted.back().rank != "2" or sorted.back().suit != Card.Suit.DIAMONDS:
		fails += 1
		print("FAIL Filipino: highest card should be 2♦, got " + sorted.back().card_name())

	RulesManager.set_ranking(RulesManager.SuitRanking.BIG_TWO)
	if not two_spades.beats(two_diamonds):
		fails += 1
		print("FAIL Big Two: 2♠ should beat 2♦")
	if Card.sort_cards(deck.cards).back().suit != Card.Suit.SPADES:
		fails += 1
		print("FAIL Big Two: highest card should be 2♠")

	if fails == 0:
		print("SUIT RANKING RULES OK")
	return fails


func _play_one_game(game_num: int, difficulty: int) -> bool:
	var gm = GameManager.new()
	gm.setup_game()
	var ai = AIPlayer.new(gm)
	ai.difficulty = difficulty

	var turns = 0
	while not gm.game_over and turns < MAX_TURNS:
		ai.take_turn(gm.get_current_player())
		turns += 1

	var tag = "difficulty %d game %d" % [difficulty, game_num]
	if not gm.game_over:
		print("%s FAILED: no winner after %d turns" % [tag, MAX_TURNS])
		return false

	# Sanity: winner's hand must be empty, others must still hold cards
	if gm.winner.hand.size() != 0:
		print("%s FAILED: winner still holds cards" % tag)
		return false

	var remaining = 0
	for player in gm.players:
		remaining += player.hand.size()
	if remaining == 0 or remaining >= 52:
		print("%s FAILED: implausible remaining card count %d" % [tag, remaining])
		return false

	return true
