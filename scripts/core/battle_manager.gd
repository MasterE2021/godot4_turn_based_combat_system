extends Node
class_name BattleManager

const DAMAGE_NUMBER_SCENE : PackedScene = preload("res://scenes/ui/damage_number.tscn")

# 战斗状态枚举
enum BattleState {
	IDLE,           				# 战斗未开始或已结束的空闲状态
	BATTLE_START,   				# 战斗初始化阶段
	ROUND_START,    				# 回合开始，处理回合初效果，决定行动者
	PLAYER_TURN,    				# 等待玩家输入并执行玩家行动
	ENEMY_TURN,     				# AI 决定并执行敌人行动
	ACTION_EXECUTION, 				# 正在执行某个角色的具体行动
	ROUND_END,      				# 回合结束，处理回合末效果，检查胜负
	VICTORY,        				# 战斗胜利
	DEFEAT          				# 战斗失败
}

# 当前战斗状态
var current_state: BattleState = BattleState.IDLE

# 战斗参与者
var player_characters: Array[Character] = []
var enemy_characters: Array[Character] = []

# 回合顺序管理
var turn_queue: Array = []
var current_turn_character: Character = null

## 当前选中的技能
var current_selected_skill : SkillData = null

var effect_processors = {}		## 效果处理器

# 信号
signal battle_state_changed(new_state)
signal turn_changed(character)
signal battle_ended(is_victory)
# 添加额外信号用于与UI交互
signal player_action_required(character) # 通知UI玩家需要行动
signal enemy_action_executed(attacker, target, damage) # 敌人执行了行动
signal character_stats_changed(character) # 角色状态变化
# 技能相关
signal skill_executed(caster, targets, skill, results)
signal effect_applied(effect_type, source, target, result)

func _ready():
	_init_effect_processors()
	_set_state(BattleState.IDLE)

# 开始战斗
func start_battle() -> void:
	print("战斗开始!")

	# 清空角色列表
	player_characters.clear()
	enemy_characters.clear()

	# 自动查找并注册战斗场景中的角色
	register_characters()
	
	if player_characters.is_empty() or enemy_characters.is_empty():
		push_error("无法开始战斗：缺少玩家或敌人!")
		return
	
	_set_state(BattleState.BATTLE_START)

# 注册战斗场景中的角色
func register_characters():
	# 查找战斗场景中的所有角色
	var player_area = get_node_or_null("../PlayerArea")
	var enemy_area = get_node_or_null("../EnemyArea")
	
	if player_area:
		for child in player_area.get_children():
			if child is Character:
				add_player_character(child)
				_subscribe_to_character_signals(child)
	
	if enemy_area:
		for child in enemy_area.get_children():
			if child is Character:
				add_enemy_character(child)
				_subscribe_to_character_signals(child)
	
	print("已注册 ", player_characters.size(), " 名玩家角色和 ", enemy_characters.size(), " 名敌人")

# 玩家选择行动 - 由BattleScene调用
func player_select_action(action_type: String, target = null):
	if current_state != BattleState.PLAYER_TURN:
		return
		
	print("玩家选择行动: ", action_type)
	
	# 设置为行动执行状态
	_set_state(BattleState.ACTION_EXECUTION)
	
	# 执行选择的行动
	match action_type:
		"attack":
			if target and target is Character:
				await execute_attack(current_turn_character, target)
			else:
				print("错误：攻击需要选择有效目标")
				_set_state(BattleState.PLAYER_TURN) # 返回选择状态
				return
		"defend":
			await execute_defend(current_turn_character)
		_:
			print("未知行动类型: ", action_type)
			_set_state(BattleState.PLAYER_TURN)
			return
	
	# 行动结束后转入回合结束
	_set_state(BattleState.ROUND_END)

# 执行敌人AI
func execute_enemy_ai() -> void:
	if current_state != BattleState.ENEMY_TURN or current_turn_character == null:
		return
		
	# 简单的AI逻辑：总是攻击第一个存活的玩家角色
	var target = null
	for player in player_characters:
		if player.current_hp > 0:
			target = player
			break
			
	if target:
		_set_state(BattleState.ACTION_EXECUTION)
		print(current_turn_character.character_name, " 选择攻击 ", target.character_name)
		await execute_attack(current_turn_character, target)
		_set_state(BattleState.ROUND_END)
	else:
		print("敌人找不到可攻击的目标")
		_set_state(BattleState.ROUND_END)

# 执行攻击
func execute_attack(attacker: Character, target: Character) -> void:
	if attacker == null or target == null:
		return
		
	print(attacker.character_name, " 攻击 ", target.character_name)
	
	# 简单的伤害计算
	var damage = target.take_damage(attacker.attack_power - target.defense_power)
	
	# 发出敌人行动执行信号
	if enemy_characters.has(attacker):
		enemy_action_executed.emit(attacker, target, damage)
		
	# 发出角色状态变化信号
	character_stats_changed.emit(target)

	# 显示伤害数字
	spawn_damage_number(target.global_position, damage, Color.RED)
	
	print_rich("[color=red]" + target.character_name + " 受到 " + str(damage) + " 点伤害![/color]")

## 执行防御
func execute_defend(character: Character):
	if character == null:
		return

	print(character.character_name, " 选择防御，受到的伤害将减少")
	character.set_defending(true)
	
	# 发出角色状态变化信号
	character_stats_changed.emit(character)

# 构建回合队列
func build_turn_queue():
	turn_queue.clear()
	
	# 简单实现：所有存活角色按速度排序
	var all_characters = []
	
	for player in player_characters:
		if player.current_hp > 0:
			all_characters.append(player)
			
	for enemy in enemy_characters:
		if enemy.current_hp > 0:
			all_characters.append(enemy)
	
	# 按速度从高到低排序
	all_characters.sort_custom(func(a, b): return a.speed > b.speed)
	
	turn_queue = all_characters
	print("回合顺序已生成: ", turn_queue.size(), " 个角色")

# 下一个回合
func next_turn():
	if turn_queue.is_empty():
		print("回合结束，重新构建回合顺序")
		build_turn_queue()
		
	if turn_queue.is_empty():
		print("没有可行动的角色")
		check_battle_end_condition()
		return
		
	current_turn_character = turn_queue.pop_front()
	print("当前行动者: ", current_turn_character.character_name)
	emit_signal("turn_changed", current_turn_character)
	
	# 根据当前行动者是玩家还是敌人，设置相应状态
	if player_characters.has(current_turn_character):
		_set_state(BattleState.PLAYER_TURN)
	else:
		_set_state(BattleState.ENEMY_TURN)

# 检查战斗结束条件
func check_battle_end_condition() -> bool:
	# 检查玩家是否全部阵亡
	var all_players_defeated = true
	for player in player_characters:
		if player.current_hp > 0:
			all_players_defeated = false
			break
			
	if all_players_defeated:
		_set_state(BattleState.DEFEAT)
		return true
		
	# 检查敌人是否全部阵亡
	var all_enemies_defeated = true
	for enemy in enemy_characters:
		if enemy.current_hp > 0:
			all_enemies_defeated = false
			break
			
	if all_enemies_defeated:
		_set_state(BattleState.VICTORY)
		return true
		
	return false

# 添加和管理角色
func add_player_character(character: Character):
	if not player_characters.has(character):
		player_characters.append(character)
		print("添加玩家角色: ", character.character_name)

func add_enemy_character(character: Character):
	if not enemy_characters.has(character):
		enemy_characters.append(character)
		print("添加敌人角色: ", character.character_name)

func remove_character(character: Character):
	if player_characters.has(character):
		player_characters.erase(character)
	if enemy_characters.has(character):
		enemy_characters.erase(character)
	if turn_queue.has(character):
		turn_queue.erase(character)
		
	print(character.character_name, " 已从战斗中移除")
	check_battle_end_condition()

## 生成伤害数字
func spawn_damage_number(position: Vector2, amount: int, color : Color) -> void:
	var damage_number = DAMAGE_NUMBER_SCENE.instantiate()
	get_parent().add_child(damage_number)
	damage_number.global_position = position + Vector2(0, -50)
	damage_number.show_number(str(amount), color)

# 判断角色是否为玩家角色
func is_player_character(character: Character) -> bool:
	return player_characters.has(character)

# MP检查和消耗
func check_and_consume_mp(caster: Character, skill: SkillData) -> bool:
	if caster.current_mp < skill.mp_cost:
		print_rich("[color=red]魔力不足，法术施放失败！[/color]")
		return false
	
	caster.use_mp(skill.mp_cost)
	return true

func calculate_skill_damage(caster: Character, target: Character, skill: SkillData) -> int:
	# 基础伤害计算
	var base_damage = skill.power + (caster.magic_attack * 0.8)
	
	# 考虑目标防御
	var damage_after_defense = base_damage - (target.magic_defense * 0.5)
	
	# 加入随机浮动因素 (±10%)
	var random_factor = randf_range(0.9, 1.1)
	var final_damage = damage_after_defense * random_factor
	
	# 确保伤害至少为1
	return max(1, round(final_damage))

func play_cast_animation(caster: Character) -> void:
	var tween = create_tween()
	# 角色短暂发光效果
	tween.tween_property(caster, "modulate", Color(1.5, 1.5, 1.5), 0.2)
	tween.tween_property(caster, "modulate", Color(1, 1, 1), 0.2)
	
	# 这里可以播放施法音效
	# AudioManager.play_sfx("spell_cast")

func play_heal_cast_animation(caster: Character) -> void:
	play_cast_animation(caster)

# 播放命中动画
func play_hit_animation(target: Character):
	var tween = create_tween()
	
	# 目标变红效果
	tween.tween_property(target, "modulate", Color(2, 0.5, 0.5), 0.1)
	
	# 抖动效果
	var original_pos = target.position
	tween.tween_property(target, "position", original_pos + Vector2(5, 0), 0.05)
	tween.tween_property(target, "position", original_pos - Vector2(5, 0), 0.05)
	tween.tween_property(target, "position", original_pos, 0.05)
	
	# 恢复正常颜色
	tween.tween_property(target, "modulate", Color(1, 1, 1), 0.1)
	
	# 这里可以播放命中音效
	# AudioManager.play_sfx("hit_impact")

## 伤害效果
func play_damage_effect(_target: Character, _params: Dictionary = {}) -> void:
	pass

# 治疗效果视觉反馈
func play_heal_effect(target: Character, params: Dictionary = {}) -> void:
	var tween = create_tween()
	
	# 目标变绿效果（表示恢复）
	tween.tween_property(target, "modulate", Color(0.7, 1.5, 0.7), 0.2)
	
	# 上升的小动画，暗示"提升"
	var original_pos = target.position
	tween.tween_property(target, "position", original_pos - Vector2(0, 5), 0.2)
	tween.tween_property(target, "position", original_pos, 0.1)
	
	# 恢复正常颜色
	tween.tween_property(target, "modulate", Color(1, 1, 1), 0.2)
	
	# 如果有指定动画，则播放
	if target.has_method("play_animation") and "animation" in params:
		target.play_animation(params["animation"])

# 状态效果应用视觉反馈
func play_status_effect(target: Character, params: Dictionary = {}) -> void:
	#var status_type = params.get("status_type", "buff")
	var is_positive = params.get("is_positive", true)
	
	var effect_color = Color(0.7, 1, 0.7) if is_positive else Color(1, 0.7, 0.7)
	
	var tween = create_tween()
	tween.tween_property(target, "modulate", effect_color, 0.2)
	
	# 正面状态上升效果，负面状态下沉效果
	var original_pos = target.position
	var offset = Vector2(0, -4) if is_positive else Vector2(0, 4)
	tween.tween_property(target, "position", original_pos + offset, 0.1)
	tween.tween_property(target, "position", original_pos, 0.1)
	
	# 恢复正常颜色
	tween.tween_property(target, "modulate", Color(1, 1, 1), 0.2)
	
	# 如果有指定动画，则播放
	if target.has_method("play_animation") and "animation" in params:
		target.play_animation(params["animation"])

# 防御姿态效果
func play_defend_effect(character: Character) -> void:
	var tween = create_tween()
	
	# 角色微光效果
	tween.tween_property(character, "modulate", Color(0.8, 0.9, 1.3), 0.2)
	
	# 如果有对应动画，播放防御动画
	if character.has_method("play_animation"):
		character.play_animation("defend")

func calculate_skill_healing(caster: Character, target: Character, skill: SkillData) -> int:
	# 治疗量通常更依赖施法者的魔法攻击力
	var base_healing = skill.power + (caster.magic_attack * 1.0)
	
	# 随机浮动 (±5%)
	var random_factor = randf_range(0.95, 1.05)
	var final_healing = base_healing * random_factor
	
	return max(1, round(final_healing))

# 执行技能
func execute_skill(caster: Character, skill: SkillData, custom_targets: Array = []) -> Dictionary:
	# 检查参数
	if not is_instance_valid(caster) or not skill:
		push_error("SkillSystem: 无效的施法者或技能")
		return {}
	
	# 检查MP消耗
	if not skill.can_cast(caster.current_mp):
		push_error("SkillSystem: MP不足，无法施放技能")
		return {"error": "mp_not_enough"}
	
	# 扣除MP
	if caster.can_cast_skill(skill):
		caster.deduct_mp_for_skill(skill)
	
	# 获取目标
	var targets = custom_targets if !custom_targets.is_empty() else get_targets_for_skill(caster, skill)
	
	if targets.is_empty():
		push_warning("SkillSystem: 没有有效目标")
		return {"error": "no_valid_targets"}
	
	# 播放施法动画
	if skill.cast_animation != "":
		_request_animation(caster, skill.cast_animation)
	
	# 等待短暂时间（供动画播放）
	if Engine.get_main_loop():
		await Engine.get_main_loop().process_frame

	# 处理直接效果
	var effect_results = {}
	if not skill.effects.is_empty():
		effect_results = await apply_effects(skill.effects, caster, targets)

	# 合并结果
	var final_results = {}
	for target in targets:
		final_results[target] = {}
		
		if effect_results.has(target):
			for key in effect_results[target]:
				final_results[target][key] = effect_results[target][key]
	
	# 发送技能执行信号
	skill_executed.emit(caster, targets, skill, final_results)
	
	# 行动结束后转入回合结束
	_set_state(BattleState.ROUND_END)
	return final_results

# 应用单个效果
func apply_effect(effect: SkillEffectData, source: Character, target: Character) -> Dictionary:
	# 检查参数有效性
	if !is_instance_valid(source) or !is_instance_valid(target):
		push_error("SkillSystem: 无效的角色引用")
		return {}
	
	if not effect:
		push_error("SkillSystem: 无效的效果引用")
		return {}
	
	# 获取对应的处理器
	var processor_id = get_processor_id_for_effect(effect)
	var processor = effect_processors.get(processor_id)
	
	if processor and processor.can_process_effect(effect):
		# 使用处理器处理效果
		var result = await processor.process_effect(effect, source, target)
		
		# 发出信号
		effect_applied.emit(effect.effect_type, source, target, result)
		return result
	else:
		push_error("SkillSystem: 无效的效果处理器")
		return {}

## 应用多个效果
## [param effects] 要应用的效果数组
## [param source] 效果的施法者
## [param targets] 效果的目标角色数组
## [return] 所有效果的结果
func apply_effects(effects: Array, source: Character, targets: Array) -> Dictionary:
	var all_results = {}

	for target in targets:
		if !is_instance_valid(target) or target.current_hp <= 0:
			continue
		
		all_results[target] = {}
		
		for effect in effects:
			var result = await apply_effect(effect, source, target)
			for key in result:
				all_results[target][key] = result[key]
	
	return all_results

# 获取技能的目标
func get_targets_for_skill(caster: Character, skill: SkillData) -> Array:
	var targets = []
	var target_type = skill.target_type
	
	match target_type:
		SkillData.TargetType.SELF:
			targets = [caster]
		
		SkillData.TargetType.ENEMY_SINGLE:
			# 获取一个有效的敌方目标
			targets = _get_valid_enemy_targets(caster)
			if !targets.is_empty():
				targets = [targets[0]]  # 只取第一个敌人
		
		SkillData.TargetType.ALLY_SINGLE:
			# 获取一个有效的友方目标（不包括自己）
			targets = _get_valid_ally_targets(caster, false)
			if !targets.is_empty():
				targets = [targets[0]]  # 只取第一个友方
		
		SkillData.TargetType.ENEMY_ALL:
			# 获取所有有效的敌方目标
			targets = _get_valid_enemy_targets(caster)
		
		SkillData.TargetType.ALLY_ALL:
			# 获取所有有效的友方目标（不包括自己）
			targets = _get_valid_ally_targets(caster, false)
		
		SkillData.TargetType.ALLY_SINGLE_INC_SELF:
			# 获取除自己外的所有友方目标
			targets = _get_valid_ally_targets(caster, false)
		
		SkillData.TargetType.ALLY_ALL_INC_SELF:
			# 获取所有角色
			targets = _get_valid_enemy_targets(caster) + _get_valid_ally_targets(caster, true)
	
	return targets

## 注册效果处理器
func register_effect_processor(processor: EffectProcessor):
	var processor_id = processor.get_processor_id()
	effect_processors[processor_id] = processor
	print("注册效果处理器: %s" % processor_id)

## 根据效果类型获取处理器ID
func get_processor_id_for_effect(effect: SkillEffectData) -> String:
	match effect.effect_type:
		SkillEffectData.EffectType.DAMAGE:
			return "damage"
		SkillEffectData.EffectType.HEAL:
			return "heal"
		# SkillEffectData.EffectType.ATTRIBUTE_MODIFY:
		# 	return "attribute"
		SkillEffectData.EffectType.STATUS:
			return "status"
		SkillEffectData.EffectType.DISPEL:
			return "dispel"
		SkillEffectData.EffectType.SPECIAL:
			return "special"
		_:
			return "unknown"

## 获取有效的敌方单位
func get_valid_enemy_targets(caster: Character) -> Array:
	return _get_valid_enemy_targets(caster)

## 获取有效的友方单位
func get_valid_ally_targets(caster: Character, include_self: bool = true) -> Array:
	return _get_valid_ally_targets(caster, include_self)

## 私有方法: 触发视觉效果
func _trigger_visual_effect(effect: SkillEffectData, _source: Character, target: Character, result: Dictionary) -> void:
	match effect.effect_type:
		SkillEffectData.EffectType.DAMAGE:
			play_damage_effect(target, {
				"amount": result.get("amount", 0),
				"element": result.get("element", 0)
			})
		
		SkillEffectData.EffectType.HEAL:
			play_heal_effect(target, {
				"amount": result.get("amount", 0)
			})

# 在初始化方法中注册新的效果处理器
func _init_effect_processors():
	# 注册处理器
	register_effect_processor(DamageEffectProcessor.new(self))
	register_effect_processor(HealingEffectProcessor.new(self))
	register_effect_processor(ApplyStatusProcessor.new(self))
	register_effect_processor(DispelStatusProcessor.new(self))

#region 辅助函数
## 获取有效的敌方目标
func _get_valid_enemy_targets(caster: Character) -> Array:
	var targets = []
	var enemy_list = []
	
	# 确定敌人列表
	if is_player_character(caster):
		enemy_list = enemy_characters
	else:
		enemy_list = player_characters
	
	# 过滤出存活的敌人
	for enemy in enemy_list:
		if enemy.is_alive:
			targets.append(enemy)
	
	return targets

## 获取有效的友方目标
func _get_valid_ally_targets(caster: Character, include_self: bool = true) -> Array:
	var targets = []
	var ally_list = []
	
	# 确定友方列表
	if is_player_character(caster):
		ally_list = player_characters
	else:
		ally_list = enemy_characters
	
	# 过滤出存活的友方
	for ally in ally_list:
		if ally.is_alive and (include_self or ally != caster):
			targets.append(ally)
	
	return targets

## 请求播放动画
## [param character] 角色
## [param animation_name] 动画名称
func _request_animation(character: Character, animation_name: String) -> void:
	if character.has_method("play_animation"):
		character.play_animation(animation_name)
	else:
		push_warning("character not has method play_animation!")

## 处理视觉效果请求
func _on_visual_effect_requested(effect_type: String, target, params: Dictionary = {}):
	if not is_instance_valid(target):
		return
		
	# 分发到适当的视觉效果方法
	var effect_method = "play_" + effect_type + "_effect"
	if has_method(effect_method):
		call(effect_method, target, params)
	else:
		push_warning("BattleManager: 未找到视觉效果方法 play_" + effect_type + "_effect")

## 订阅角色信号
func _subscribe_to_character_signals(character : Character) -> void:
	if not character.character_defeated.is_connected(_on_character_defeated):
		character.character_defeated.connect(_on_character_defeated)
	#TODO 链接其他信号

# 设置战斗状态
func _set_state(new_state: BattleState):
	if current_state == new_state:
		return
		
	print("战斗状态转换: ", BattleState.keys()[current_state], " -> ", BattleState.keys()[new_state])
	current_state = new_state
	emit_signal("battle_state_changed", current_state)
	
	# 处理进入新状态时的逻辑
	match current_state:
		BattleState.IDLE:
			# 重置战斗相关变量
			start_battle()
			
		BattleState.BATTLE_START:
			# 战斗初始化
			build_turn_queue()
			_set_state(BattleState.ROUND_START)
			
		BattleState.ROUND_START:
			# 回合开始处理，确定行动者
			next_turn()
			# 重置当前回合角色标记
			if current_turn_character:
				current_turn_character.reset_turn_flags()
		BattleState.PLAYER_TURN:
			# 通知UI需要玩家输入
			print("玩家回合：等待输入...")
			player_action_required.emit(current_turn_character)
			
		BattleState.ENEMY_TURN:
			# 执行敌人AI
			print("敌人回合：", current_turn_character.character_name, " 思考中...")
			# 延迟一下再执行AI，避免敌人行动过快
			await get_tree().create_timer(1.0).timeout
			execute_enemy_ai()
			
		BattleState.ACTION_EXECUTION:
			# 执行选择的行动
			# 这部分通常在选择行动后直接调用execute_action
			pass
			
		BattleState.ROUND_END:
			# 回合结束处理
			if not check_battle_end_condition():
				current_turn_character.process_active_statuses_for_turn_end(self)
				_set_state(BattleState.ROUND_START)
				
		BattleState.VICTORY:
			print("战斗胜利!")
			emit_signal("battle_ended", true)
			
		BattleState.DEFEAT:
			print("战斗失败...")
			emit_signal("battle_ended", false)

# 角色死亡信号处理函数
func _on_character_defeated(character: Character) -> void:
	print_rich("[color=purple]" + character.character_name + " 已被击败![/color]")
	
	# 从相应列表中移除
	if player_characters.has(character):
		player_characters.erase(character)
	elif enemy_characters.has(character):
		enemy_characters.erase(character)
	
	# 从回合队列中移除
	if turn_queue.has(character):
		turn_queue.erase(character)
	
	# 如果当前行动者死亡，需要特殊处理
	if current_turn_character == character:
		print("当前行动者 " + character.character_name + " 已阵亡。")
	
	# 检查战斗是否结束
	check_battle_end_condition()
#endregion
