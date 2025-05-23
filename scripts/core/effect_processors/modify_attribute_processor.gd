extends EffectProcessor
class_name ModifyAttributeProcessor

func get_processor_id() -> StringName:
	return &"modify_attribute"

func can_process_effect(effect_data: SkillEffectData) -> bool:
	return effect_data.effect_type == SkillEffectData.EffectType.MODIFY_ATTRIBUTE

func process_effect(effect_data: SkillEffectData, caster: Character, target: Character, source: Variant) -> Dictionary:
	var results := { "success": false, "attribute_modified": &"", "change_info": {} }

	if not is_instance_valid(target) or not is_instance_valid(effect_data.attribute_modifier_template):
		results["error"] = "Invalid target or missing attribute_modifier_template in effect_data."
		push_error("AttributeModifyEffectProcessor: " + results.error)
		return results

	# 假设 Character 有 active_attribute_set
	if not target.has_method("get_active_attribute_set") or not is_instance_valid(target.get_active_attribute_set()):
		results["error"] = "Target Character has no valid AttributeSet."
		push_error("AttributeModifyEffectProcessor: " + results.error)
		return results
		
	var attribute_set: SkillAttributeSet = target.get_active_attribute_set() # 假设 Character 有此方法
	var modifier_template: SkillAttributeModifier = effect_data.attribute_modifier_template
	var attribute_to_change: StringName = effect_data.attribute_to_modify_direct 
	
	# 关键：直接应用的Modifier模板，也应该复制其实例以确保独立性，特别是如果source_id等需要动态设置
	var modifier_instance = modifier_template.duplicate(true) as SkillAttributeModifier
	if not is_instance_valid(modifier_instance):
		results["error"] = "Failed to duplicate attribute_modifier_template."
		push_error("AttributeModifyEffectProcessor: " + results.error)
		return results
    
    # 设置来源
	modifier_instance.set_source(source)

	# 播放施法/效果触发前视觉（如果定义）
	# 对于属性修改，可能没有普适的“施法”视觉，更多是“命中”或“状态附加”类视觉
	# 但为了与你的 ApplyStatusEffectProcessor 风格一致：
	var cast_vfx_params = {}
	# if is_instance_valid(skill_context) and skill_context.has_meta("element"): # 如果技能有元素
	#    cast_vfx_params["element"] = skill_context.get_meta("element")
	_request_visual_effect(&"attribute_modify_cast", caster, cast_vfx_params) # 使用一个特定的key

	if Engine.get_main_loop(): # 保持风格一致的延迟
		await Engine.get_main_loop().process_frame

	# 应用修改器
	attribute_set.apply_modifier(modifier_instance, source)
	results["success"] = true
	results["attribute_modified"] = attribute_to_change
	results["change_info"] = {
		"operation": modifier_instance.operation,
		"magnitude": modifier_instance.magnitude,
		"source": source
	}

	# 播放属性变化视觉效果
	_request_visual_effect(&"attribute_changed", target, {
		"attribute": attribute_to_change, 
		"operation": modifier_instance.operation, 
		"magnitude": modifier_instance.magnitude
	})
	if effect_data.visual_effect_key != "": # 如果效果本身定义了特定视觉
		_request_visual_effect(effect_data.visual_effect_key, target, results.change_info)


	# 发出角色状态变化信号 (由AttributeSet内部的信号机制处理，这里不需要BattleManager直接发)
	# BattleManager可以监听AttributeSet的信号（通过Character中继）

	var attr_display_name = attribute_to_change # 后续可通过AttributeRegistry获取显示名
	var message = "[color=yellow]%s 的 %s 属性被修改 (来源: %s)[/color]" % [target.character_name, attr_display_name, source]
	print_rich(message)
			
	# 重要：这种直接应用的 ATTRIBUTE_MODIFY 效果，其修改器会持续存在于AttributeSet中，
	# 直到被明确移除。如果这是一次性、瞬时的修改（比如“临时提升本回合攻击力”然后恢复），
	# 则需要一个对应的机制来移除这个modifier_instance。
	# 对于永久性修改（如升级加点），这是合适的。
	# 对于由Buff/Debuff带来的临时属性修改，应通过 ApplyStatusEffectProcessor 施加状态来实现。

	return results