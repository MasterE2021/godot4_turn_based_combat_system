extends Node
class_name CharacterCombatComponent

## 战斗组件，专注于战斗逻辑

## 依赖skill_component组件
@export var _skill_component : CharacterSkillComponent
## 防御状态伤害减免系数
@export var defense_damage_reduction: float = 0.5
## 防御状态标记
var is_defending: bool = false:
	set(value):
		is_defending = value
		defending_changed.emit(value)

## 死亡时发出信号
signal character_defeated()
signal defending_changed(value: bool)

## 初始化组件
func initialize() -> void:
	# 这里可以进行任何战斗组件特定的初始化
	if not _skill_component:
		_skill_component = get_parent().skill_component
	if not _skill_component:
		push_error("无法找到技能组件！")
		return
	
	_skill_component.attribute_current_value_changed.connect(_on_attribute_current_value_changed)

## 设置防御状态
func set_defending(value: bool) -> void:
	is_defending = value

## 伤害处理方法
## [param base_damage] 基础伤害值
## [param source] 伤害来源角色
## [return] 实际造成的伤害值
func take_damage(base_damage: float, source: Variant = null) -> float:
	var final_damage: float = base_damage

	# 如果处于防御状态，则减免伤害
	if is_defending:
		final_damage = round(final_damage * defense_damage_reduction)
		print(owner.to_string() + " 正在防御，伤害减半！")
		set_defending(false)  # 防御效果通常在受到一次攻击后解除

	if final_damage <= 0:
		return 0
	# 消耗生命值	
	_skill_component.consume_hp(final_damage, source)

	return final_damage

## 治疗处理方法
## [param amount] 治疗量
## [param source] 治疗来源角色
## [return] 实际恢复的治疗量
func heal(amount: float, source: Variant = null) -> float:
	if amount <= 0:
		return 0
	# 恢复生命值
	_skill_component.restore_hp(amount, source)
	return amount

## 回合开始时重置标记
func reset_turn_flags() -> void:
	set_defending(false)

## 死亡处理方法
func _die(death_source: Variant = null):
	print_rich("[color=red][b]%s[/b] has been defeated by %s![/color]" % [owner.character_data.character_name, death_source])
	character_defeated.emit(owner)

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
#region --- 信号处理 ---
## 属性当前值变化的处理
func _on_attribute_current_value_changed(
		attribute_name: StringName, new_value: float, 
		_old_value: float, _source: Variant = null) -> void:
	if attribute_name == &"CurrentHealth":
		if new_value <= 0:
			_die()
	
#endregion
