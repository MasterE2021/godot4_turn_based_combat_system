extends Node
class_name CharacterCombatComponent

## 持有者引用
var _owner: Character

## 防御状态标记
var is_defending: bool = false

## 死亡时发出信号
signal character_defeated(character: Character)

func _init(owner: Character):
	_owner = owner
	name = "CombatComponent"

## 初始化组件
func initialize() -> void:
	# 这里可以进行任何战斗组件特定的初始化
	pass

## 设置防御状态
func set_defending(value: bool) -> void:
	is_defending = value
	if _owner.defense_indicator:
		if is_defending:
			_owner.defense_indicator.show_indicator()
		else:
			_owner.defense_indicator.hide_indicator()

## 伤害处理方法
func take_damage(base_damage: float, source: Variant = null) -> float:
	var final_damage: float = base_damage

	# 如果处于防御状态，则减免伤害
	if is_defending:
		final_damage = round(final_damage * 0.5)
		print(_owner.character_name + " 正在防御，伤害减半！")
		set_defending(false)  # 防御效果通常在受到一次攻击后解除

	if final_damage <= 0:
		return 0

	var current_health = _owner.active_attribute_set.get_current_value(&"CurrentHealth")
	_owner.active_attribute_set.set_current_value(&"CurrentHealth", current_health - final_damage, source)
	return final_damage

## 治疗处理方法
func heal(amount: float, source: Variant = null) -> float:
	if amount <= 0:
		return 0
		
	var current_health = _owner.active_attribute_set.get_current_value(&"CurrentHealth")
	_owner.active_attribute_set.set_current_value(&"CurrentHealth", current_health + amount, source)
	return amount

## 处理角色死亡
func handle_death(death_source: Variant = null) -> void:
	print_rich("[color=red][b]%s[/b] has been defeated by %s![/color]" % [_owner.character_data.character_name, death_source])
	character_defeated.emit(_owner)
	_owner.modulate = Color(0.5, 0.5, 0.5, 0.5) # 变灰示例

## 回合开始时重置标记
func reset_turn_flags() -> void:
	set_defending(false)

## 播放战斗动画
func play_animation(animation_name: String) -> void:
	print("播放战斗动画：", animation_name, " 角色: ", _owner.character_name)
	
## 检查是否有足够的MP使用技能
func has_enough_mp_for_skill(skill: SkillData) -> bool:
	if not skill:
		return false
	return _owner.current_mp >= skill.mp_cost
	
## 使用MP
func use_mp(amount: float, source: Variant = null) -> bool:
	if amount <= 0:
		return true
		
	if _owner.current_mp < amount:
		return false
		
	var current_mp = _owner.active_attribute_set.get_current_value(&"CurrentMana")
	_owner.active_attribute_set.set_current_value(&"CurrentMana", current_mp - amount, source)
	return true

## 恢复MP
func restore_mp(amount: float, source: Variant = null) -> float:
	if amount <= 0:
		return 0
		
	var current_mp = _owner.active_attribute_set.get_current_value(&"CurrentMana")
	_owner.active_attribute_set.set_current_value(&"CurrentMana", current_mp + amount, source)
	return amount
