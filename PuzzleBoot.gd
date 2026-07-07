# PuzzleBoot.gd
# Headless smoke test: boots a real puzzle match (pz1) so the GameTable
# puzzle path runs — stacked deal, objective banner, per-seat AI. Stalls
# at the human's turn (the player leads with 3C), which is fine; we only
# check it runs error-free.
# Run: godot --headless --fixed-fps 60 res://PuzzleBoot.tscn --quit-after 700
extends Node

func _ready() -> void:
	ContentManager.load_all()
	PuzzleManager.save_path = "user://puzzle_boot_test.cfg"
	PuzzleManager.reset_all()
	GameSession.mode = GameSession.Mode.PUZZLE
	GameSession.puzzle_id = "pz1_warmup"
	print("PuzzleBoot: entering pz1_warmup match")
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://GameTable.tscn")
