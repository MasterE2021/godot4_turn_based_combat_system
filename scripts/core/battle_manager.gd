extends Node
class_name BattleManager

const DAMAGE_NUMBER_SCENE : PackedScene = preload("res://scenes/ui/damage_number.tscn")

# 核心系统引用
var character_registry: BattleCharacterRegistryManager		## 角色注册管理器
var state_manager: BattleStateManager
var visual_effects: BattleVisualEffects
var combat_rules: CombatRuleManager
var turn_order_manager: TurnOrderManager					## 回合顺序管理器

## 当前选中的技能
var current_selected_skill : SkillData = null

var effect_processors = {}		## 效果处理器

# 信号
signal turn_changed(character)
signal battle_ended(is_victory)
# 添加额外信号用于与UI交互
signal player_action_required(character) # 通知UI玩家需要行动
signal enemy_action_executed(attacker, target, damage) # 敌人执行了行动

func _ready():
	_init_core_systems()
	_start_battle()

func get_valid_ally_targets(caster: Character, include_self: bool) -> Array[Character]:
	var skill_context := SkillSystem.SkillExecutionContext.new(
		character_registry,
		visual_effects,
	)
	return SkillSystem.get_valid_ally_targets(skill_context, caster, include_self)

func get_valid_enemy_targets(caster: Character) -> Array[Character]:
	var skill_context := SkillSystem.SkillExecutionContext.new(
		character_registry,
		visual_effects,
	)
	return SkillSystem.get_valid_enemy_targets(skill_context, caster)

## 执行动作
## [param action_type] 动作类型
## [param source] 动作执行者
## [param target] 动作目标
## [param params] 额外参数（如技能数据、道具数据等）
## [return] 动作执行结果
func execute_action(action_type: CharacterCombatComponent.ActionType, source: Character, target = null, params = null) -> Dictionary:
	if not is_instance_valid(source):
		push_error("无效的动作执行者")
		return {"success": false, "error": "无效的动作执行者"}
	
	if not source.combat_component:
		push_error("角色缺少战斗组件")
		return {"success": false, "error": "角色缺少战斗组件"}
	
	# 调用角色战斗组件的执行动作方法
	var result = await source.combat_component.execute_action(action_type, source, target, params)
	
	# 检查战斗是否结束
	combat_rules.check_battle_end_conditions()
	
	return result

## 执行攻击
## [param attacker] 攻击者
## [param target] 目标
## [return] 攻击结果
func execute_attack(attacker: Character, target: Character) -> Dictionary:
	return await execute_action(CharacterCombatComponent.ActionType.ATTACK, attacker, target)

## 执行防御
## [param character] 防御的角色
## [return] 防御结果
func execute_defend(character: Character) -> Dictionary:
	return await execute_action(CharacterCombatComponent.ActionType.DEFEND, character)

## 执行技能
## [param caster] 施法者
## [param skill] 技能数据
## [param targets] 目标列表
## [return] 技能执行结果
func execute_skill(caster: Character, skill: SkillData, targets: Array = []) -> Dictionary:
	var skill_context = SkillSystem.SkillExecutionContext.new(
		character_registry,
		visual_effects,
	)
	
	var params = {
		"skill": skill,
		"targets": targets,
		"skill_context": skill_context
	}
	
	return await execute_action(CharacterCombatComponent.ActionType.SKILL, caster, null, params)

## 执行使用道具
## [param user] 使用者
## [param item] 道具数据
## [param targets] 目标列表
## [return] 道具使用结果
func execute_item(user: Character, item, targets: Array) -> Dictionary:
	var params = {
		"item": item,
		"targets": targets
	}
	
	return await execute_action(CharacterCombatComponent.ActionType.ITEM, user, null, params)

## 初始化核心系统
func _init_core_systems() -> void:	
	# 创建角色注册管理器
	character_registry = BattleCharacterRegistryManager.new()
	add_child(character_registry)
	character_registry.name = "BattleCharacterRegistryManager"
	character_registry.initialize()

	# 创建状态管理器
	state_manager = BattleStateManager.new()
	add_child(state_manager)
	state_manager.name = "BattleStateManager"
	state_manager.state_changed.connect(_on_battle_state_changed)

	# 创建回合管理器
	turn_order_manager = TurnOrderManager.new()
	add_child(turn_order_manager)
	turn_order_manager.name = "TurnOrderManager"
	turn_order_manager.initialize(character_registry)

	# 创建视觉效果系统
	visual_effects = BattleVisualEffects.new()
	add_child(visual_effects)
	visual_effects.initialize(DAMAGE_NUMBER_SCENE)
	
	# 创建战斗规则管理器
	combat_rules = CombatRuleManager.new()
	add_child(combat_rules)
	combat_rules.initialize(character_registry)

# 玩家选择行动 - 由BattleScene调用
func player_select_action(action_type: String, target = null):
	if not state_manager.is_in_state(BattleStateManager.BattleState.PLAYER_TURN):
		return
		
	print("玩家选择行动: ", action_type)
	
	# 设置为行动执行状态
	state_manager.change_state(BattleStateManager.BattleState.ACTION_EXECUTION)
	
	# 获取当前回合角色
	var current_turn_character = turn_order_manager.current_character
	
	# 执行选择的行动
	match action_type:
		"attack":
			if target and target is Character:
				await execute_attack(current_turn_character, target)
			else:
				print("错误：攻击需要选择有效目标")
				state_manager.change_state(BattleStateManager.BattleState.PLAYER_TURN) # 返回选择状态
				return
		"defend":
			await execute_defend(current_turn_character)
		_:
			print("未知行动类型: ", action_type)
			state_manager.change_state(BattleStateManager.BattleState.PLAYER_TURN)
			return
	
	# 行动结束后转入回合结束
	state_manager.change_state(BattleStateManager.BattleState.ROUND_END)

# 处理战斗状态变化
func _on_battle_state_changed(old_state, new_state):
	print("战斗状态变化: ", state_manager.get_state_name(old_state), " -> ", state_manager.get_state_name(new_state))
	
	match new_state:
		BattleStateManager.BattleState.BATTLE_START:
			print("战斗开始初始化...")
			# 战斗初始化
			turn_order_manager.build_queue()
			await get_tree().create_timer(1.0).timeout
			state_manager.change_state(BattleStateManager.BattleState.ROUND_START)
			
		BattleStateManager.BattleState.ROUND_START:
			print("回合开始...")
			# 回合开始处理，确定行动者
			_next_turn()
			#TODO 重置当前回合角色标记
			
		BattleStateManager.BattleState.PLAYER_TURN:
			# 通知UI需要玩家输入
			print("玩家回合：等待输入...")
			player_action_required.emit(turn_order_manager.current_character)
		
		BattleStateManager.BattleState.ENEMY_TURN:
			# 执行敌人AI
			print("敌人回合：", turn_order_manager.current_character.character_name, " 思考中...")
			# 延迟一下再执行AI，避免敌人行动过快
			await get_tree().create_timer(1.0).timeout
			_execute_enemy_ai()
			
		BattleStateManager.BattleState.ROUND_END:
			print("回合结束...")
			# 处理回合结束效果
			await get_tree().create_timer(0.5).timeout
			var is_battle_ended = combat_rules.check_battle_end_conditions()
			if is_battle_ended:
				state_manager.change_state(BattleStateManager.BattleState.VICTORY if character_registry.is_team_defeated(false) else BattleStateManager.BattleState.DEFEAT)
			else:
				state_manager.change_state(BattleStateManager.BattleState.ROUND_START)
			
		BattleStateManager.BattleState.VICTORY:
			print("胜利!")
			# 处理胜利后的逻辑
			battle_ended.emit(true)

		BattleStateManager.BattleState.DEFEAT:
			print("失败!")
			# 处理失败后的逻辑
			battle_ended.emit(false)
			
		BattleStateManager.BattleState.ACTION_EXECUTION:
			# 执行选择的行动
			# 这部分通常在选择行动后直接调用execute_action
			print("执行选择的行动...")
			
			# TODO: 实现execute_action逻辑

# 注册战斗场景中的角色
func _register_characters() -> void:
	# 查找战斗场景中的所有角色
	var player_area = get_node_or_null("../PlayerArea")
	var enemy_area = get_node_or_null("../EnemyArea")
	
	if player_area:
		for child in player_area.get_children():
			if child is Character:
				character_registry.register_character(child, true)
				_subscribe_to_character_signals(child)
	
	if enemy_area:
		for child in enemy_area.get_children():
			if child is Character:
				character_registry.register_character(child, false)
				_subscribe_to_character_signals(child)
	
	print("已注册 ", character_registry.get_player_team(true).size(), " 名玩家角色和 ", character_registry.get_enemy_team(false).size(), " 名敌人")

# 开始战斗
func _start_battle() -> void:
	print("战斗开始!")

	# 自动查找并注册战斗场景中的角色
	_register_characters()
	
	if character_registry.get_player_team(true).is_empty() or character_registry.get_enemy_team(false).is_empty():
		push_error("无法开始战斗：缺少玩家或敌人!")
		return
	
	state_manager.change_state(BattleStateManager.BattleState.BATTLE_START)

## 订阅角色信号
func _subscribe_to_character_signals(character : Character) -> void:
	if not character.character_defeated.is_connected(_on_character_defeated):
		character.character_defeated.connect(_on_character_defeated)
	#TODO 链接其他信号

# 角色死亡信号处理函数
func _on_character_defeated(character: Character) -> void:
	print_rich("[color=purple]" + character.character_name + " 已被击败![/color]")
	# 检查战斗是否结束
	combat_rules.check_battle_end_conditions()

# 下一个回合
func _next_turn() -> void:
	var next_character = turn_order_manager.get_next_character()
	
	if not next_character:
		print("回合结束，重新构建回合顺序")
		turn_order_manager.build_queue()
		next_character = turn_order_manager.get_next_character()
		
	if not next_character:
		print("没有可行动的角色")
		combat_rules.check_battle_end_conditions()
		return
	
	turn_changed.emit(next_character)
	
	print(next_character.character_name, " 的回合")
	
	# 回合开始时重置防御状态
	next_character.set_defending(false)
	
	# 判断是玩家还是敌人的回合
	if character_registry.is_player_character(next_character):
		state_manager.change_state(BattleStateManager.BattleState.PLAYER_TURN)
	else:
		state_manager.change_state(BattleStateManager.BattleState.ENEMY_TURN)

# 执行敌人AI
func _execute_enemy_ai() -> void:
	var current_turn_character = turn_order_manager.current_character
	if not state_manager.is_in_state(BattleStateManager.BattleState.ENEMY_TURN) or current_turn_character == null:
		push_error("敌人回合：当前不是敌人回合或没有可行动的角色")
		return
		
	# 简单的AI逻辑：总是攻击第一个存活的玩家角色
	var target = null
	for player in character_registry.get_player_team(true):
		target = player
		break

	var damage := 0	
	if target:
		state_manager.change_state(BattleStateManager.BattleState.ACTION_EXECUTION)
		print(current_turn_character.character_name, " 选择攻击 ", target.character_name)
		var result := await execute_action(CharacterCombatComponent.ActionType.ATTACK, current_turn_character, target)
		damage = result.get("damage")
		state_manager.change_state(BattleStateManager.BattleState.ROUND_END)
	else:
		print("敌人找不到可攻击的目标")
		state_manager.change_state(BattleStateManager.BattleState.ROUND_END)

	enemy_action_executed.emit(turn_order_manager.current_character, target, damage)
