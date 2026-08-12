# TutorialManager.gd
# Data for the guided first match taught by Lolo Carding. Pure content +
# tiny accessors (static, like the other managers) — GameTable is what
# actually drives the board, highlights, and input locks per step.
#
# Each step:
#   id        — short key
#   text      — Lolo's persistent instruction
#   correction— gentle nudge shown when the player does the wrong thing
#   require   — what completes the step:
#                 play_exact    (cards): play exactly this set
#                 play_pair     (cards): select+play these two as a pair
#                 play_straight (cards): select+play these five as a straight
#                 pass                 : press Pass
#                 help                 : open then close the Help modal
#                 free                 : locks removed, finish the match
#   highlight — which area to spotlight: "hand" | "pass" | "help" | "none"
#
# The stacked deal (content/tutorial/tutorial_match.json) is built so the
# player holds exactly the cards each step needs; the rival (Lolo) holds
# 2 of diamonds so he can out-top the player's 2 of spades for the
# "pass" lesson.

class_name TutorialManager

const SPEAKER := "lolo_carding"

const STEPS := [
	{
		"id": "lead3c",
		"text": "Hi there, apo! I'm Lolo Carding, and I'll teach you the ropes. The goal is simple: run out of cards before we do. You go first. Tap the three of clubs (3 of C), then press PLAY.",
		"correction": "Not that one, apo. Tap the three of clubs (3 of C) first.",
		"require": {"type": "play_exact", "cards": ["3C"]},
		"highlight": "hand",
	},
	{
		"id": "beat",
		"text": "Nice work. Now there's a card on the table. To win a round you need something stronger, a higher rank or a stronger suit. Play your best card, the two of spades (2 of S). Tap it, then press PLAY.",
		"correction": "Not that one, apo. The two of spades (2 of S) is your strongest card right now.",
		"require": {"type": "play_exact", "cards": ["2S"]},
		"highlight": "hand",
	},
	{
		"id": "pass",
		"text": "See that? I dropped a stronger card and you can't top it. When that happens, you step back. Press PASS. There's no shame in a smart retreat, apo.",
		"correction": "You can't win that one right now. Just press PASS, apo.",
		"require": {"type": "pass"},
		"highlight": "pass",
	},
	{
		"id": "pair",
		"text": "The table's clear, so you lead again. You can also play a PAIR: two cards of the same number. Pick the two fours (4 of D and 4 of H), then press PLAY.",
		"correction": "Two cards of the same number, apo. The two fours.",
		"require": {"type": "play_pair", "cards": ["4D", "4H"]},
		"highlight": "hand",
	},
	{
		"id": "straight",
		"text": "Good one. Now for a bigger hand, a STRAIGHT: five cards in a row. Pick the 6, 7, 8, 9, and 10, then press PLAY.",
		"correction": "Five in a row, apo. The 6, 7, 8, 9, and 10.",
		"require": {"type": "play_straight", "cards": ["6C", "7D", "8H", "9S", "10D"]},
		"highlight": "hand",
	},
	{
		"id": "help",
		"text": "If you ever forget the combinations, we have a cheat sheet. Press the '?' button to see every valid hand. Take a look, then close it.",
		"correction": "Press the '?' button, apo. It's down at the bottom.",
		"require": {"type": "help"},
		"highlight": "help",
	},
	{
		"id": "free",
		"text": "You're ready now, apo! Go on, the table's yours. Use up all your cards. I'm right here if you need me.",
		"require": {"type": "free"},
		"highlight": "none",
	},
]

const END_WIN := "You won?! Wow, apo, you learned fast. Lolo's proud of you."
const END_LOSE := "You lost this one, but that's alright. What matters is you learned. We'll run it back another day, okay?"


static func count() -> int:
	return STEPS.size()


static func step(i: int) -> Dictionary:
	return STEPS[i] if i >= 0 and i < STEPS.size() else {}
