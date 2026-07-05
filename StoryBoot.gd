# StoryBoot.gd
# Headless smoke test: boots a real story match (ch1) so the whole
# GameTable story path runs — chapter load, seat setup, avatars, deal,
# and AI story turns (with bark/match-event evaluation). It will stall
# at the human's turn, which is fine; we're checking it runs error-free.
# Run:  godot --headless --fixed-fps 60 res://StoryBoot.tscn --quit-after 900
extends Node

func _ready() -> void:
	ContentManager.load_all()
	StoryManager.save_path = "user://story_boot_test.cfg"
	StoryManager.reset_all()
	GameSession.mode = GameSession.Mode.STORY
	GameSession.story_chapter_id = "ch1_bahay"
	GameSession.story_skip_intro = true
	print("StoryBoot: entering ch1_bahay match")
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://GameTable.tscn")
