extends Node
class_name TurnOrderManager

var turn_queue: Array[Character] = []
var current_character: Character = null

signal turn_changed(character)
signal round_ended

func build_queue(player_characters: Array[Character], enemy_characters: Array[Character]) -> void:
	turn_queue.clear()
	
	# 收集所有存活角色
	var all_characters: Array[Character] = []
	for player in player_characters:
		if player.is_alive:
			all_characters.append(player)
			
	for enemy in enemy_characters:
		if enemy.is_alive:
			all_characters.append(enemy)
	
	# 按速度排序
	all_characters.sort_custom(func(a, b): return a.speed > b.speed)
	turn_queue = all_characters
	
	print("回合顺序已生成: %d 个角色" % turn_queue.size())

func get_next_character() -> Character:
	if turn_queue.is_empty():
		round_ended.emit()
		return null
		
	current_character = turn_queue.pop_front()
	turn_changed.emit(current_character)
	return current_character

func is_player_character(character: Character, player_characters: Array[Character]) -> bool:
	return player_characters.has(character)

func get_remaining_turn_count() -> int:
	return turn_queue.size()
	
func get_character_position_in_queue(character: Character) -> int:
	return turn_queue.find(character)
	
func insert_character_at_position(character: Character, position: int = 0) -> void:
	if position < 0 or position > turn_queue.size():
		turn_queue.append(character)
	else:
		turn_queue.insert(position, character)
	
	print("%s 已被插入到回合队列位置 %d" % [character.character_name, position])
	
func remove_character_from_queue(character: Character) -> bool:
	if turn_queue.has(character):
		turn_queue.erase(character)
		print("%s 已从回合队列中移除" % character.character_name)
		return true
	return false
	
func clear_queue() -> void:
	turn_queue.clear()
	current_character = null
