extends EffectProcessor
class_name ModifyDamageEffectProcessor

## 获取处理器ID
func get_processor_id() -> StringName:
	return &"modify_damage"

## 检查是否可以处理指定效果类型
func can_process_effect(effect: SkillEffectData) -> bool:
	return effect.effect_type == effect.EffectType.MODIFY_DAMAGE

## 处理修改伤害效果
## 这个处理器不直接应用伤害，而是修改传入的伤害信息对象
func process_effect(effect: SkillEffectData, source: Character, _target: Character, context: Dictionary = {}) -> Dictionary:
	var results = {}
	
	# 检查传入的上下文中是否有伤害信息
	# 首先检查事件类型
	var event_type = context.get("event_type", "")
	if event_type != &"on_damage_taken" and not context.has("original_event_context"):
		print_rich("[color=orange]ModifyDamageEffectProcessor: 上下文中没有伤害事件信息[/color]")
		return {"success": false, "error": "上下文中没有伤害事件信息"}
	
	# 如果是状态触发的效果，使用原始事件上下文
	var damage_context = context
	if context.has("original_event_context"):
		damage_context = context["original_event_context"]
	
	# 检查伤害信息
	if not damage_context.has("damage_info"):
		print_rich("[color=red]ModifyDamageEffectProcessor: 上下文中缺少伤害信息对象[/color]")
		return {"success": false, "error": "上下文中缺少伤害信息对象"}
	
	# 获取伤害信息对象
	var damage_info = damage_context["damage_info"]
	
	# 检查伤害是否可以被修改
	if not damage_info.get("can_be_modified", true):
		return {"success": false, "error": "伤害不可修改"}
	
	# 记录修改前的伤害值
	var damage_before = damage_info["damage_value"]
	
	# 应用百分比修改
	var modified_damage = damage_before * effect.damage_mod_percent
	
	# 应用固定值修改
	modified_damage += effect.damage_mod_flat
	
	# 确保伤害在最小和最大值之间
	modified_damage = clamp(modified_damage, effect.damage_mod_min, effect.damage_mod_max)
	
	# 更新伤害信息对象
	damage_info["damage_value"] = modified_damage
	
	# 记录修改日志
	var modification = {
		"modifier": "防御状态",
		"type": "百分比修改",
		"before": damage_before,
		"after": modified_damage
	}
	
	# 添加到修改日志
	if damage_info.has("modifications"):
		damage_info["modifications"].append(modification)
	
	# 打印修改信息
	print_rich("[color=cyan]伤害修改: %.1f -> %.1f (修改器: %s, 百分比: %.2f)[/color]" % 
		[damage_before, modified_damage, source.character_name, effect.damage_mod_percent])
	
	# 返回结果
	results["success"] = true
	results["original_damage"] = damage_before
	results["modified_damage"] = modified_damage
	
	return results
