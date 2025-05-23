# d:\GodotProject\godot4_tbc_system_tutorial\godot4_turn_based_combat_system\scripts\core\battle\skill_system.gd
extends Node
class_name SkillSystem

# 引用 BattleManager 和其他需要的模块
var character_registry: CharacterRegistryManager
var visual_effects: BattleVisualEffects
# var turn_manager: TurnOrderManager # 可能需要，例如处理技能的施法时间或延迟效果

# 效果处理器
var effect_processors = {}
## 当前选中的技能 (如果需要由 SkillSystem 管理选择状态)
var current_selected_skill : SkillData = null

# 信号
signal skill_execution_started(caster: Character, skill: SkillData, targets: Array[Character])
signal skill_execution_completed(caster: Character, skill: SkillData, targets: Array[Character], results: Dictionary) # results 可以包含伤害、治疗、状态等信息
signal skill_failed(caster: Character, skill: SkillData, reason: String) # 例如 MP不足, 目标无效等
signal skill_executed(caster, targets, skill, results) # Moved from BattleManager
signal effect_applied(effect_type, source, target, result) # Moved from BattleManager

func _init():
	_init_effect_processors() # Initialize processors when SkillSystem is created

## 初始化，在 BattleManager 中获取其他模块的引用
func initialize(registry: CharacterRegistryManager, vfx: BattleVisualEffects) -> void: #, p_turn_manager: TurnOrderManager
	if not registry:
		push_error("SkillSystem requires a CharacterRegistryManager reference.")
		return
	if not vfx:
		push_error("SkillSystem requires a BattleVisualEffects reference.")
		return
		
	character_registry = registry
	visual_effects = vfx
	# turn_manager = p_turn_manager
	print("SkillSystem initialized.")

#region Effect Processor Management
# 在初始化方法中注册新的效果处理器
func _init_effect_processors():
	# 注册处理器
	register_effect_processor(DamageEffectProcessor.new(self))
	register_effect_processor(HealingEffectProcessor.new(self))
	register_effect_processor(ApplyStatusProcessor.new(self))
	register_effect_processor(DispelStatusProcessor.new(self))

func register_effect_processor(processor) -> void:
	if processor and processor.has_method("get_effect_type") and processor.has_method("process"):
		var effect_type = processor.get_effect_type()
		effect_processors[effect_type] = processor
		print("SkillSystem: Registered effect processor for type: %s" % effect_type)
	else:
		push_error("SkillSystem: Failed to register invalid effect processor.")
#endregion

## 尝试执行一个技能
## [param caster] 施法者
## [param skill_data] 要使用的技能数据
## [param selected_targets] 玩家或AI选择的目标
func attempt_execute_skill(caster: Character, skill_data: SkillData, selected_targets: Array[Character]) -> bool:
	if not is_instance_valid(caster) or not skill_data:
		push_error("Invalid caster or skill_data for skill execution.")
		skill_failed.emit(caster, skill_data, "invalid_caster_or_skill")
		return false

	# 1. 验证施法条件 (MP, 冷却, 目标等)
	var validation_result = _validate_skill_usability(caster, skill_data, selected_targets)
	if not validation_result.is_usable:
		print_rich("[color=orange]Skill '%s' failed validation: %s[/color]" % [skill_data.skill_name, validation_result.reason])
		skill_failed.emit(caster, skill_data, validation_result.reason)
		if visual_effects: visual_effects.show_status_text(caster, validation_result.reason, Color.YELLOW) # 显示失败原因
		return false

	print_rich("[color=lightblue]%s attempts to use skill: %s on %s[/color]" % [caster.character_name, skill_data.skill_name, selected_targets])
	skill_execution_started.emit(caster, skill_data, selected_targets)

	# 2. 消耗资源 (MP, 物品等)
	_consume_skill_resources(caster, skill_data)

	# 3. 异步执行技能效果处理
	call_deferred("_process_skill_effects_async", caster, skill_data, selected_targets)
	
	return true

## 私有方法：验证技能可用性
func _validate_skill_usability(caster: Character, skill: SkillData, targets: Array[Character]) -> Dictionary:
	var result = {"is_usable": true, "reason": ""}

	# 检查MP消耗
	if caster.current_mp < skill.mp_cost:
		result.is_usable = false
		result.reason = "Not enough MP"
		return result
	
	# 检查技能冷却 (如果实现了冷却系统)
	# if skill.is_on_cooldown(caster):
	#    result.is_usable = false
	#    result.reason = "Skill on cooldown"
	#    return result

	# 检查目标选择是否有效
	# First, determine the actual list of targets based on skill's target type if not explicitly provided
	var actual_targets_for_validation = targets
	match skill.target_type:
		SkillData.TargetType.NONE:
			actual_targets_for_validation = []
		SkillData.TargetType.SELF:
			actual_targets_for_validation = [caster]
		SkillData.TargetType.ALLY_SINGLE: # Renamed from SINGLE_ALLY, assumes excludes self
			if targets.is_empty() or not character_registry.get_allied_team_for_character(caster, false).has(targets[0]): # false for exclude self
				result.is_usable = false
				result.reason = "Invalid ally target (must be other ally)"
				return result
		SkillData.TargetType.ALLY_SINGLE_INC_SELF: # New case for ally including self
			if targets.is_empty() or not character_registry.get_allied_team_for_character(caster, true).has(targets[0]):
				result.is_usable = false
				result.reason = "Invalid ally target (can be self)"
				return result
		SkillData.TargetType.ENEMY_SINGLE: # Renamed from SINGLE_ENEMY
			if targets.is_empty() or not character_registry.get_opposing_team_for_character(caster).has(targets[0]):
				result.is_usable = false
				result.reason = "Invalid enemy target"
				return result
		SkillData.TargetType.ALLY_ALL: # Renamed from ALL_ALLIES, assumes excludes self
			actual_targets_for_validation = get_valid_ally_targets(caster, false) # false for exclude self
		SkillData.TargetType.ALLY_ALL_INC_SELF: # New case for all allies including self
			actual_targets_for_validation = get_valid_ally_targets(caster, true) # true for include self
		SkillData.TargetType.ENEMY_ALL: # Renamed from ALL_ENEMIES
			actual_targets_for_validation = get_valid_enemy_targets(caster)
		# Cases for EVERYONE, RANDOM_ENEMY, RANDOM_ALLY removed as they are not in SkillData.TargetType enum
		# Their logic needs to be handled elsewhere if still required.
		_:
			push_warning("SkillSystem: Unhandled or non-standard skill.target_type in _validate_skill_usability: %s. Skill: %s" % [skill.target_type, skill.skill_name])
			# Defaulting to no targets or could set unusable
			actual_targets_for_validation = [] 
			# result.is_usable = false # Or consider it unusable
			# result.reason = "Unknown target type"
			# return result
			pass

	if not _validate_skill_targets(caster, skill, actual_targets_for_validation):
		result.is_usable = false
		result.reason = "Invalid target(s) for skill scope"
		return result
		
	# 检查施法者是否处于无法施法的状态 (例如：沉默、眩晕)
	if caster.has_status(&"Silenced") or caster.has_status(&"Stunned"): # 假设有这些状态ID
		result.is_usable = false
		result.reason = "Cannot cast (Silenced/Stunned)"
		return result

	return result

## 私有方法：验证技能目标 (after initial target list is determined)
func _validate_skill_targets(_caster: Character, skill: SkillData, targets: Array[Character]) -> bool:
	if skill.target_type == SkillData.TargetType.NONE:
		return true
	
	if targets.is_empty() and skill.target_type != SkillData.TargetType.NONE:
		# This case should ideally be caught by the more specific target type checks in _validate_skill_usability
		# but as a fallback:
		if skill.target_type != SkillData.TargetType.ALLY_ALL and \
		   skill.target_type != SkillData.TargetType.ALLY_ALL_INC_SELF and \
		   skill.target_type != SkillData.TargetType.ENEMY_ALL:
			push_warning("Skill '%s' requires targets, but none were resolved or provided." % skill.skill_name)
			return false

	for target_char in targets:
		if not is_instance_valid(target_char):
			push_warning("Skill '%s' has an invalid target instance." % skill.skill_name)
			return false # An invalid instance in the list is a problem
		if not target_char.is_alive and not skill.can_target_dead:
			push_warning("Skill '%s' cannot target dead characters, but '%s' is dead." % [skill.skill_name, target_char.character_name])
			return false
		# TODO: Add more validation: range, line of sight, specific immunities to this skill type etc.
	return true


## 私有方法：消耗技能资源
func _consume_skill_resources(caster: Character, skill: SkillData) -> void:
	if skill.mp_cost > 0:
		caster.use_mp(skill.mp_cost, skill) # Character类应有 use_mp 方法
	
	# 处理其他资源消耗，例如物品、怒气等
	# if skill.consumes_item:
	#    caster.inventory.remove_item(skill.item_consumed_id, 1)
	#
	# if skill.rage_cost > 0:
	#    caster.use_rage(skill.rage_cost)

	# 设置技能冷却 (如果实现了冷却系统)
	# skill.start_cooldown(caster)


## 异步处理技能效果的核心逻辑 (使用 call_deferred 调用)
func _process_skill_effects_async(caster: Character, skill_data: SkillData, initial_selected_targets: Array[Character]) -> void:
	# 确保在操作前，所有参与者仍然有效
	if not is_instance_valid(caster) or not skill_data:
		skill_failed.emit(caster, skill_data, "caster_or_skill_became_invalid")
		return

	# Determine actual targets at the moment of execution, considering skill's target type
	var actual_execution_targets = _determine_execution_targets(caster, skill_data, initial_selected_targets)
	
	if actual_execution_targets.is_empty() and skill_data.target_type != SkillData.TargetType.NONE:
		print_rich("[color=orange]Skill '%s' had no valid targets left at execution time.[/color]" % skill_data.skill_name)
		skill_execution_completed.emit(caster, skill_data, [], {"effects_applied": false, "reason": "no_valid_targets_left"})
		return

	# 播放攻击/技能动画 (如果之前没有播放施法动画)
	if visual_effects and visual_effects.has_method("play_attack_animation"): 
		await visual_effects.play_attack_animation(caster, actual_execution_targets, skill_data.animation_name if skill_data.animation_name else "")
	
	# 播放技能本身的视觉特效
	if visual_effects and visual_effects.has_method("play_skill_visual_effects"):
		await visual_effects.play_skill_visual_effects(skill_data, caster, actual_execution_targets)

	var overall_results = {"effects_applied": true, "details": [], "caster": caster, "skill": skill_data, "targets": actual_execution_targets}

	# 遍历技能效果并应用它们
	for effect_data: SkillEffectData in skill_data.effects:
		if not effect_data: continue

		# 根据效果类型选择目标
		var current_effect_targets = _determine_targets_for_effect(caster, skill_data, effect_data, actual_execution_targets)
		
		for target_char in current_effect_targets:
			if not is_instance_valid(target_char): continue # 再次检查目标有效性
			# Skip dead targets if effect cannot target dead, unless skill itself can (e.g. revive)
			if not target_char.is_alive and not effect_data.can_affect_dead and not skill_data.can_target_dead:
				continue

			var effect_result = _apply_single_effect(caster, target_char, skill_data, effect_data)
			overall_results.details.append({
				"target_node": target_char, # Store actual node for direct reference
				"target_name": target_char.character_name, 
				"effect_type": effect_data.effect_type, 
				"result": effect_result
			})
			
			# Trigger visual for this specific effect result
			_trigger_visual_effect(effect_data, caster, target_char, effect_result)

			# 短暂延迟，让视觉效果（如伤害数字）有时间显示
			if visual_effects and current_effect_targets.size() > 0 : await get_tree().create_timer(0.1).timeout 

	skill_executed.emit(caster, actual_execution_targets, skill_data, overall_results) # Use the moved signal
	skill_execution_completed.emit(caster, skill_data, actual_execution_targets, overall_results)
	print_rich("[color=lightgreen]%s's skill '%s' execution completed.[/color]" % [caster.character_name, skill_data.skill_name])

func _determine_execution_targets(caster: Character, skill: SkillData, selected_targets: Array[Character]) -> Array[Character]:
	var final_targets: Array[Character] = []
	match skill.target_type:
		SkillData.TargetType.NONE:
			pass # No targets
		SkillData.TargetType.SELF:
			if is_instance_valid(caster) and caster.is_alive:
				final_targets.append(caster)
		SkillData.TargetType.ALLY_SINGLE: # Renamed from SINGLE_ALLY, assumes excludes self
			# For single target skills, selected_targets should contain the one chosen target
			if not selected_targets.is_empty() and is_instance_valid(selected_targets[0]) and (selected_targets[0].is_alive or skill.can_target_dead):
				final_targets.append(selected_targets[0])
		SkillData.TargetType.ALLY_SINGLE_INC_SELF: # New case for ally including self
			# For single target skills, selected_targets should contain the one chosen target
			if not selected_targets.is_empty() and is_instance_valid(selected_targets[0]) and (selected_targets[0].is_alive or skill.can_target_dead):
				final_targets.append(selected_targets[0])
		SkillData.TargetType.ENEMY_SINGLE: # Renamed from SINGLE_ENEMY
			# For single target skills, selected_targets should contain the one chosen target
			if not selected_targets.is_empty() and is_instance_valid(selected_targets[0]) and (selected_targets[0].is_alive or skill.can_target_dead):
				final_targets.append(selected_targets[0])
		SkillData.TargetType.ALLY_ALL: # Renamed from ALL_ALLIES, assumes excludes self
			final_targets = get_valid_ally_targets(caster, false) # false for exclude self
		SkillData.TargetType.ALLY_ALL_INC_SELF: # New case for all allies including self
			final_targets = get_valid_ally_targets(caster, true) # true for include self
		SkillData.TargetType.ENEMY_ALL: # Renamed from ALL_ENEMIES
			final_targets = get_valid_enemy_targets(caster)
		# Cases for EVERYONE, RANDOM_ENEMY, RANDOM_ALLY removed as they are not in SkillData.TargetType enum
		# Their logic needs to be handled elsewhere if still required.
		_:
			push_warning("SkillSystem: Unhandled skill.target_type in _determine_execution_targets: %s" % skill.target_type)
			final_targets = selected_targets
			pass

	# Filter out dead targets if the skill cannot target them
	if not skill.can_target_dead:
		final_targets = final_targets.filter(func(x): x.is_alive)

	return final_targets

# Determines the actual targets for a given effect, considering its override rules.
# This is called PER effect, as one skill might have multiple effects with different targeting.
func _determine_targets_for_effect(caster: Character, _skill: SkillData, _effect: SkillEffectData, initial_targets: Array[Character]) -> Array[Character]:
	var final_targets: Array[Character] = []
	var _source_for_targeting = caster # Default, might be used if EffectTargetOverride logic is restored

	# Commenting out EffectTargetOverride as it's not defined in SkillEffectData.gd
	# The logic below would handle effect-specific target overrides.
	# For now, effects will target the same characters as the main skill.
	# match _effect.target_override_type: 
	# 	SkillEffectData.EffectTargetOverride.DEFAULT_SKILL_TARGETS:
	# 		final_targets = initial_targets
	# 	SkillEffectData.EffectTargetOverride.CASTER_ONLY:
	# 		if is_instance_valid(caster) and (caster.is_alive or _skill.can_target_dead_for_effect(_effect)):
	# 			final_targets.append(caster)
	# 	SkillEffectData.EffectTargetOverride.ALL_ALLIES_OF_CASTER:
	# 		final_targets = get_valid_ally_targets(caster, _skill.can_target_self_in_aoe_for_effect(_effect)) # Requires new SkillData methods
	# 	SkillEffectData.EffectTargetOverride.ALL_ENEMIES_OF_CASTER:
	# 		final_targets = get_valid_enemy_targets(caster)
	# 	SkillEffectData.EffectTargetOverride.EVERYONE_IN_BATTLE:
	# 		final_targets = character_registry.get_all_characters()
	# 		# Further filter by can_target_dead_for_effect if needed
	# 	SkillEffectData.EffectTargetOverride.MAIN_TARGET_AND_ADJACENT_ALLIES: # Complex, needs position data
	# 		push_warning("EffectTargetOverride.MAIN_TARGET_AND_ADJACENT_ALLIES not yet implemented.")
	# 		final_targets = initial_targets # Fallback
	# 	SkillEffectData.EffectTargetOverride.MAIN_TARGET_AND_ADJACENT_ENEMIES: # Complex
	# 		push_warning("EffectTargetOverride.MAIN_TARGET_AND_ADJACENT_ENEMIES not yet implemented.")
	# 		final_targets = initial_targets # Fallback
	# 	_:
	# 		push_warning("Unhandled EffectTargetOverride type: %s" % _effect.target_override_type)
	# 		final_targets = initial_targets # Default to skill's initial targets
	# else:
	# 	# If no override, use the initial targets determined by the skill's main target type
	final_targets = initial_targets

	# TODO: Implement more sophisticated effect-specific targeting (e.g. splash from main target, chain, etc.)
	return final_targets

func _trigger_visual_effect(effect_data: SkillEffectData, _caster: Character, target: Character, result: Dictionary) -> void:
	if not visual_effects:
		push_warning("SkillSystem: VisualEffects node not set, cannot trigger visual effect.")
		return

	# Skip visual if result indicates no actual effect (e.g. no damage/heal, status failed to apply)
	if result.has("damage_dealt") and result.damage_dealt == 0 and not result.has("missed"):
		if not (effect_data.effect_type == SkillEffectData.EffectType.DAMAGE and result.get("missed", false)):
			# Allow miss animation for damage type, but skip 0 damage/heal otherwise
			# Check if it was a heal that did 0, or status that failed
			if effect_data.effect_type == SkillEffectData.EffectType.HEAL and result.get("healing_done", -1) == 0:
				return
			if effect_data.effect_type == SkillEffectData.EffectType.STATUS and not result.get("status_applied", true):
				return
			# For other types, if there's no specific positive outcome, maybe don't show VFX
			# This needs careful consideration based on game feel.

	# Apply visual effect based on type
	match effect_data.effect_type:
		SkillEffectData.EffectType.DAMAGE:
			var damage = result.get("damage_dealt", 0)
			if result.get("missed", false):
				visual_effects.show_status_text(target, "Miss", Color.WHITE)
			elif damage > 0:
				visual_effects.show_damage_number(target, damage)
				visual_effects.play_hit_effect(target, effect_data.visual_effect if effect_data.visual_effect else "default_hit")
			# else: 0 damage, not a miss - maybe a shield absorbed it all. Could have specific VFX.
		SkillEffectData.EffectType.HEAL:
			var healing = result.get("healing_done", 0)
			if healing > 0:
				visual_effects.show_heal_number(target, healing)
				visual_effects.play_heal_effect(target, effect_data.visual_effect if effect_data.visual_effect else "default_heal")
		SkillEffectData.EffectType.STATUS: # Renamed from APPLY_STATUS
			if result.has("status_applied") and result.status_applied:
				var status_id = result.get("status_id", "Status")
				visual_effects.show_status_text(target, status_id + " Applied!", Color.YELLOW)
				# Potentially play a status-specific visual effect from effect_data.visual_effect
			elif result.has("status_resisted") and result.status_resisted:
				visual_effects.show_status_text(target, "Resisted!", Color.ORANGE)
		SkillEffectData.EffectType.DISPEL: # Renamed from REMOVE_STATUS
			if result.has("status_removed") and result.status_removed:
				var status_id = result.get("status_id", "Status")
				visual_effects.show_status_text(target, status_id + " Removed!", Color.LIGHT_BLUE)
		SkillEffectData.EffectType.SPECIAL:
			# Handle special visual effects based on result or effect_data.special_type
			var special_text = result.get("special_vfx_text", effect_data.special_type if effect_data.special_type else "Special!")
			visual_effects.show_status_text(target, special_text, Color.PURPLE)
			# visual_effects.play_special_effect(target, effect_data.visual_effect if effect_data.visual_effect else "default_special")
		_:
			push_warning("SkillSystem: Unhandled effect_data.effect_type in _trigger_visual_effect: %s" % effect_data.effect_type)
			pass

	# Example for a generic effect text if not specifically handled by type
	# if not result.has("custom_vfx_triggered"): # Check if a specific VFX was already shown

func _apply_single_effect(caster_character: Character, target_character: Character, skill_data: SkillData, effect_data: SkillEffectData) -> Dictionary:
	# Ensure components are valid
	if not is_instance_valid(caster_character) or not is_instance_valid(target_character):
		push_error("SkillSystem: Invalid character instance in _apply_single_effect.")
		return {"error": "Invalid character instance"}
	if not caster_character.has_node("CombatComponent") or not target_character.has_node("CombatComponent") or \
	   not caster_character.has_node("SkillComponent") or not target_character.has_node("SkillComponent") :
		push_error("SkillSystem: Character is missing required components (CombatComponent/SkillComponent).")
		return {"error": "Missing components"}
			
	# Apply the actual effect logic
	var effect_application_result = {}
	match effect_data.effect_type:
		SkillEffectData.EffectType.DAMAGE:
			var damage_meta = effect_data.effect_meta.get("damage", {})
			if typeof(damage_meta) != TYPE_DICTIONARY:
				push_error("SkillSystem: Damage meta is not a dictionary for skill '%s'" % skill_data.skill_name)
				damage_meta = {} # Default to empty dict to avoid crash
			
			var damage_type = damage_meta.get("type", "physical")
			var base_damage = damage_meta.get("base_amount", 0)
			# TODO: Hit chance, critical_hits, resistances, vulnerabilities, buffs/debuffs
			# For now, direct damage application
			var final_damage = target_character.combat_component.take_damage(base_damage, damage_type, caster_character, skill_data)
			effect_application_result = {"damage_dealt": final_damage, "damage_type": damage_type}
			# Add "missed" if hit chance fails, e.g. effect_application_result.missed = true

		SkillEffectData.EffectType.HEAL:
			var heal_meta = effect_data.effect_meta.get("heal", {})
			if typeof(heal_meta) != TYPE_DICTIONARY:
				push_error("SkillSystem: Heal meta is not a dictionary for skill '%s'" % skill_data.skill_name)
				heal_meta = {} # Default to empty dict
				
			var base_healing = heal_meta.get("base_amount", 0)
			# TODO: Add scaling from caster_stats, critical_heals, etc.
			var actual_healing = target_character.combat_component.receive_heal(base_healing, caster_character, skill_data)
			effect_application_result = {"healing_done": actual_healing}

		SkillEffectData.EffectType.STATUS: # Renamed from APPLY_STATUS
			var status_meta = effect_data.effect_meta.get("status", {})
			if typeof(status_meta) != TYPE_DICTIONARY:
				push_error("SkillSystem: Status meta is not a dictionary for skill '%s'" % skill_data.skill_name)
				status_meta = {} # Default to empty dict

			var status_id = status_meta.get("id", "")
			var duration = status_meta.get("duration", 1) 
			var potency = status_meta.get("potency", 1.0)
			# TODO: Add chance to apply, resistance checks
			if not status_id.is_empty():
				var applied_status_node = target_character.skill_component.apply_status(status_id, caster_character, duration, potency, skill_data)
				effect_application_result = {"status_applied": applied_status_node != null, "status_id": status_id if applied_status_node else ""}
				# if not applied_status_node: effect_application_result.status_resisted = true
			else:
				push_warning("SkillSystem: Status effect in skill '%s' has no 'id' in meta." % skill_data.skill_name)
				effect_application_result = {"status_applied": false}

		SkillEffectData.EffectType.DISPEL:
			var dispel_meta = effect_data.effect_meta.get("dispel", {})
			if typeof(dispel_meta) != TYPE_DICTIONARY:
				push_error("SkillSystem: Dispel meta is not a dictionary for skill '%s'" % skill_data.skill_name)
				dispel_meta = {} # Default to empty dict
				
			var status_to_remove = dispel_meta.get("status_id", "") 
			var count = dispel_meta.get("count", 1) 
			var removed_count = target_character.skill_component.remove_status_effect(status_to_remove, count)
			effect_application_result = {"status_removed": removed_count > 0, "status_id": status_to_remove, "count_removed": removed_count}

		SkillEffectData.EffectType.SPECIAL:
			var special_meta = effect_data.effect_meta.get("special", {})
			if typeof(special_meta) != TYPE_DICTIONARY:
				push_error("SkillSystem: Special meta is not a dictionary for skill '%s'" % skill_data.skill_name)
				special_meta = {} # Default to empty dict
				
			var special_type = special_meta.get("type", "generic_special")
			push_warning("SkillSystem: Special effect type '%s' in skill '%s' needs custom implementation." % [special_type, skill_data.skill_name])
			effect_application_result = {"special_type": special_type, "custom_data": "Needs implementation", "special_vfx_text": special_type.capitalize()}
			# Example: if special_type == "revive": 
			#   var revived = target_character.combat_component.revive(special_meta.get("health_percent", 50))
			#   effect_application_result = {"revived": revived, "special_vfx_text": "Revived!"}
		_:
			push_warning("SkillSystem: Unhandled effect type '%s' in _apply_single_effect for skill '%s'." % [effect_data.effect_type, skill_data.skill_name])
			effect_application_result = {"error": "Unknown effect type"}
			
	return effect_application_result

#region Target Getter Methods (Moved from BattleManager)
func get_valid_ally_targets(caster: Character, include_self: bool) -> Array[Character]:
	var allies = character_registry.get_allied_team_for_character(caster, include_self)
	var valid_targets = []
	for ally in allies:
		if ally.is_alive:
			valid_targets.append(ally)
	return valid_targets

func get_valid_enemy_targets(caster: Character) -> Array[Character]:
	var enemies = character_registry.get_opposing_team_for_character(caster)
	var valid_targets = []
	for enemy in enemies:
		if enemy.is_alive:
			valid_targets.append(enemy)
	return valid_targets
#endregion
