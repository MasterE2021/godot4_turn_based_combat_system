extends Node
class_name CharacterSkillComponent

## 持有者引用
var _owner: Character

## 状态字典
var _active_statuses: Dictionary = {} # Key: status_id (StringName), Value: SkillStatusData (运行时实例)

## 当状态效果被应用到角色身上时发出
signal status_applied_to_character(character: Character, status_instance: SkillStatusData)							
## 当状态效果从角色身上移除时发出
signal status_removed_from_character(character: Character, status_id: StringName, status_instance_data_before_removal: SkillStatusData)
## 当状态效果更新时发出 (例如 stacks 或 duration 变化)
signal status_updated_on_character(character: Character, status_instance: SkillStatusData, old_stacks: int, old_duration: int)

func _init(owner: Character):
	_owner = owner
	name = "SkillComponent"

## 初始化组件
func initialize() -> void:
	# 这里可以进行任何技能组件特定的初始化
	pass

## 获取所有活跃状态
func get_active_statuses() -> Dictionary:
	return _active_statuses

## 添加状态效果到角色身上 (由 ApplyStatusProcessor 调用)
## [param effect_data_from_skill] 是那个类型为STATUS的SkillEffectData，用于获取duration_override等
func apply_skill_status(status_template: SkillStatusData, p_source_char: Character, effect_data_from_skill: SkillEffectData) -> Dictionary:
	if not is_instance_valid(status_template):
		return {"applied_successfully": false, "reason": "invalid_status_template"}
	
	var status_id := status_template.status_id
	var result_info = {"applied_successfully": false, "reason": "unknown", "status_instance": null}
	
	# 检查状态抵抗
	if _check_status_resistance(status_template, result_info):
		return result_info
	
	# 处理覆盖状态逻辑
	_handle_status_override(status_template)
	
	# 获取自定义持续时间，如果有
	var duration_override = effect_data_from_skill.status_duration_override \
		if effect_data_from_skill and effect_data_from_skill.status_duration_override > 0 \
		else 0
	
	# 计算实际要应用的层数
	var stacks_to_apply = effect_data_from_skill.status_stacks_to_apply \
		if effect_data_from_skill and effect_data_from_skill.status_stacks_to_apply > 0 \
		else 1
	
	# 获取或创建运行时状态实例
	var runtime_status_instance: SkillStatusData
	
	if _active_statuses.has(status_id):
		# 更新已存在的状态
		runtime_status_instance = _update_existing_status(
			status_template, p_source_char, duration_override, stacks_to_apply, result_info)
	else:
		# 应用新状态
		runtime_status_instance = _apply_new_status(
			status_template, p_source_char, duration_override, stacks_to_apply, result_info)
	
	result_info["status_instance"] = runtime_status_instance
	return result_info

## 私有方法：检查状态抵抗
func _check_status_resistance(status_template: SkillStatusData, result_info: Dictionary) -> bool:
	# 遍历所有当前已有的状态，检查是否有状态会抵抗即将应用的状态
	for status_id in _active_statuses:
		var active_status = _active_statuses[status_id]
		if active_status.resists_statuses.has(status_template.status_id):
			result_info["applied_successfully"] = false
			result_info["reason"] = "resisted_by_status"
			result_info["resisted_by"] = active_status.status_id
			
			print(_owner.character_name + " 的状态 " + active_status.status_name + " 抵抗了 " + status_template.status_name)
			return true
	
	return false

## 私有方法：处理状态覆盖
func _handle_status_override(status_template: SkillStatusData) -> void:
	if not status_template.overrides_states.is_empty():
		var ids_to_remove_due_to_override: Array[StringName] = []
		
		# 检查此状态会覆盖哪些已有状态
		for status_id in _active_statuses:
			if status_template.overrides_states.has(status_id):
				ids_to_remove_due_to_override.append(status_id)
		
		# 移除被覆盖的状态
		for status_id in ids_to_remove_due_to_override:
			var status_to_remove = _active_statuses[status_id]
			print(status_template.status_name + " 覆盖了状态 " + status_to_remove.status_name)
			remove_status(status_id)

## 私有方法：更新已存在的状态
func _update_existing_status(status_template: SkillStatusData, p_source_char: Character, 
		duration_override: int, stacks_to_apply: int, result_info: Dictionary) -> SkillStatusData:
	var status_id: StringName = status_template.status_id
	var runtime_status_instance: SkillStatusData = _active_statuses[status_id]
	var old_stacks: int = runtime_status_instance.stacks
	var old_duration: int = runtime_status_instance.remaining_duration
	
	# 根据状态的堆叠行为处理
	match runtime_status_instance.stack_behavior:
		SkillStatusData.StackBehavior.NO_STACK:
			# 不堆叠，仅刷新持续时间
			if duration_override > 0:
				runtime_status_instance.remaining_duration = duration_override
			else:
				runtime_status_instance.remaining_duration = runtime_status_instance.base_duration
			
			result_info["applied_successfully"] = true
			result_info["reason"] = "refreshed_duration"
			print(status_id, " 刷新持续时间为 ", runtime_status_instance.remaining_duration)
		
		SkillStatusData.StackBehavior.REFRESH_DURATION:
			# 替换为新的层数和持续时间
			runtime_status_instance.stacks = stacks_to_apply
			
			if duration_override > 0:
				runtime_status_instance.remaining_duration = duration_override
			else:
				runtime_status_instance.remaining_duration = runtime_status_instance.base_duration
			
			result_info["applied_successfully"] = true
			result_info["reason"] = "replaced_stacks_and_duration"
			print(status_id, " 替换为 ", stacks_to_apply, " 层，持续时间 ", runtime_status_instance.remaining_duration)
		
		SkillStatusData.StackBehavior.ADD:
			# 增加层数并刷新持续时间
			var new_stacks = runtime_status_instance.stacks + stacks_to_apply
			if runtime_status_instance.max_stacks > 0:
				new_stacks = mini(new_stacks, runtime_status_instance.max_stacks)
			
			runtime_status_instance.stacks = new_stacks
			
			if duration_override > 0:
				runtime_status_instance.remaining_duration = duration_override
			else:
				runtime_status_instance.remaining_duration = runtime_status_instance.base_duration
			
			result_info["applied_successfully"] = true
			result_info["reason"] = "added_stacks_and_refreshed"
			print(status_id, " 增加 ", stacks_to_apply, " 层至 ", new_stacks, "，刷新持续时间为 ", runtime_status_instance.remaining_duration)
	
	# 仅当层数实际变化时，重新应用修饰符
	if old_stacks != runtime_status_instance.stacks:
		# 移除当前的修饰符并重新应用
		_apply_attribute_modifiers_for_status(runtime_status_instance, false) # 移除旧修饰符
		_apply_attribute_modifiers_for_status(runtime_status_instance, true)  # 应用新修饰符
	
	# 发出状态更新信号
	status_updated_on_character.emit(_owner, runtime_status_instance, old_stacks, old_duration)
	
	return runtime_status_instance

## 私有方法：应用新状态
func _apply_new_status(status_template: SkillStatusData, p_source_char: Character, 
		duration_override: int, stacks_to_apply: int, result_info: Dictionary) -> SkillStatusData:
	# 创建运行时状态实例（克隆模板）
	var runtime_status_instance: SkillStatusData = status_template.duplicate(true)
	
	# 设置源角色引用
	runtime_status_instance.source_character = p_source_char
	
	# 设置堆叠层数
	if runtime_status_instance.max_stacks > 0:
		runtime_status_instance.stacks = mini(stacks_to_apply, runtime_status_instance.max_stacks)
	else:
		runtime_status_instance.stacks = stacks_to_apply
	
	# 设置持续时间
	if duration_override > 0:
		runtime_status_instance.remaining_duration = duration_override
	else:
		runtime_status_instance.remaining_duration = runtime_status_instance.base_duration
	
	# 将状态添加到活跃状态字典
	_active_statuses[runtime_status_instance.status_id] = runtime_status_instance
	
	# 应用属性修饰符
	_apply_attribute_modifiers_for_status(runtime_status_instance, true)
	
	result_info["applied_successfully"] = true
	result_info["reason"] = "new_status_applied"
	
	print("%s 获得状态: %s (%d层，持续%d回合)" % [
		_owner.character_name,
		runtime_status_instance.status_name,
		runtime_status_instance.stacks,
		runtime_status_instance.remaining_duration
	])
	
	# 发出状态应用信号
	status_applied_to_character.emit(_owner, runtime_status_instance)
	
	return runtime_status_instance

## 移除状态效果
func remove_status(status_id: StringName, trigger_end_effects: bool = true) -> bool:
	if not _active_statuses.has(status_id):
		return false
	
	var runtime_status_instance = _active_statuses[status_id]
	
	# 移除属性修饰符
	_apply_attribute_modifiers_for_status(runtime_status_instance, false)
	
	# 从活跃状态字典中移除
	_active_statuses.erase(status_id)
	
	# 触发结束效果
	if trigger_end_effects and not runtime_status_instance.end_effects.is_empty():
		# TODO: 处理结束效果
		pass
	
	# 发出状态移除信号
	status_removed_from_character.emit(_owner, status_id, runtime_status_instance)
	
	print("%s 移除状态: %s" % [_owner.character_name, runtime_status_instance.status_name])
	
	return true

## 私有方法：应用或移除属性修饰符
func _apply_attribute_modifiers_for_status(runtime_status_inst: SkillStatusData, add: bool = true) -> void:
	if not _owner.active_attribute_set or not is_instance_valid(runtime_status_inst): return
	if runtime_status_inst.attribute_modifiers.is_empty(): return
	
	for modifier_template: SkillAttributeModifier in runtime_status_inst.attribute_modifiers:
		# 创建运行时修饰符实例
		var runtime_modifier = modifier_template.duplicate()
		
		# 设置源和层数
		runtime_modifier.source = runtime_status_inst
		
		# 如果修饰符受层数影响，调整数值
		if runtime_modifier.affected_by_stacks and runtime_status_inst.stacks > 0:
			runtime_modifier.value *= runtime_status_inst.stacks
		
		# 应用或移除修饰符
		if add:
			_owner.active_attribute_set.apply_modifier(runtime_modifier, runtime_status_inst)
		else:
			_owner.active_attribute_set.remove_modifiers_by_source(runtime_status_inst)

## 更新状态持续时间（通常在回合结束时调用）
func update_status_durations() -> void:
	var expired_status_ids: Array[StringName] = []
	
	# 更新所有状态的持续时间
	for status_id in _active_statuses:
		var status = _active_statuses[status_id]
		
		# 如果状态是永久的，跳过
		if status.is_permanent:
			continue
		
		# 减少持续时间
		status.remaining_duration -= 1
		
		# 检查是否过期
		if status.remaining_duration <= 0:
			expired_status_ids.append(status_id)
		else:
			print("%s 的状态 %s 剩余持续时间: %d" % [_owner.character_name, status.status_name, status.remaining_duration])
	
	# 移除过期的状态
	for status_id in expired_status_ids:
		print("%s 的状态 %s 已过期" % [_owner.character_name, _active_statuses[status_id].status_name])
		remove_status(status_id)

## 获取状态实例
func get_status(status_id: StringName) -> SkillStatusData:
	return _active_statuses.get(status_id)

## 检查是否有指定状态
func has_status(status_id: StringName) -> bool:
	return _active_statuses.has(status_id)

## 获取指定状态的层数
func get_status_stacks(status_id: StringName) -> int:
	if not _active_statuses.has(status_id):
		return 0
	return _active_statuses[status_id].stacks
	
## 是否有足够的MP释放技能
func has_enough_mp_for_any_skill() -> bool:
	for skill in _owner.character_data.skills:
		if _owner.current_mp >= skill.mp_cost:
			return true
	return false
