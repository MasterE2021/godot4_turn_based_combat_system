extends Node
class_name BattleVisualEffects

## 伤害数字场景 (需要预加载或在编辑器中设置)
@export var damage_number_scene: PackedScene 
## 治疗数字场景
@export var heal_number_scene: PackedScene
## 状态效果文本场景 (例如 "中毒!", "眩晕!")
@export var status_text_scene: PackedScene 

## 初始化
func initialize() -> void:
	# 预加载资源检查
	if not damage_number_scene:
		push_warning("Damage number scene not set in BattleVisualEffects.")
	if not heal_number_scene:
		push_warning("Heal number scene not set in BattleVisualEffects.")
	if not status_text_scene:
		push_warning("Status text scene not set in BattleVisualEffects.")
	
	print("BattleVisualEffects initialized.")

## 显示伤害数字
## [param target_character] 受到伤害的角色
## [param damage_amount] 伤害数值
## [param is_critical] 是否暴击
## [param damage_type] 伤害类型 (例如 "物理", "火焰") - 可选，用于显示不同颜色的数字或图标
func show_damage_number(target_character: Character, damage_amount: float, is_critical: bool = false, damage_type: String = "") -> void:
	if not is_instance_valid(target_character) or not damage_number_scene:
		return

	var damage_num_instance = damage_number_scene.instantiate()
	if not damage_num_instance: 
		push_error("Failed to instantiate damage number scene.")
		return
		
	# 将伤害数字添加到目标角色的位置或一个全局的UI层
	# 这里假设添加到目标角色节点下，并向上偏移一些
	target_character.add_child(damage_num_instance)
	damage_num_instance.global_position = target_character.global_position - Vector2(0, 50) # 示例偏移
	
	# 配置伤害数字 (假设DamageNumber场景有一个setup方法)
	if damage_num_instance.has_method("setup"):
		damage_num_instance.setup(damage_amount, is_critical, damage_type)
	else:
		push_warning("DamageNumber scene does not have a 'setup' method.")
		# 可以直接设置 Label 的 text 等属性作为备用
		if damage_num_instance.has_node("Label"):
			var label = damage_num_instance.get_node("Label") as Label
			label.text = str(roundi(damage_amount))
			if is_critical:
				label.modulate = Color.RED # 示例暴击颜色
	
	print("Showed damage number: %d on %s" % [damage_amount, target_character.character_name])

## 显示治疗数字
func show_heal_number(target_character: Character, heal_amount: float) -> void:
	if not is_instance_valid(target_character) or not heal_number_scene:
		return

	var heal_num_instance = heal_number_scene.instantiate()
	if not heal_num_instance:
		push_error("Failed to instantiate heal number scene.")
		return

	target_character.add_child(heal_num_instance)
	heal_num_instance.global_position = target_character.global_position - Vector2(0, 50)

	if heal_num_instance.has_method("setup"):
		heal_num_instance.setup(heal_amount)
	else:
		push_warning("HealNumber scene does not have a 'setup' method.")
		if heal_num_instance.has_node("Label"):
			(heal_num_instance.get_node("Label") as Label).text = "+" + str(roundi(heal_amount))
			(heal_num_instance.get_node("Label") as Label).modulate = Color.GREEN # 示例治疗颜色
			
	print("Showed heal number: %d on %s" % [heal_amount, target_character.character_name])

## 显示状态文本 (例如 "中毒!", "眩晕!")
func show_status_text(target_character: Character, text: String, color: Color = Color.WHITE) -> void:
	if not is_instance_valid(target_character) or not status_text_scene:
		return

	var status_text_instance = status_text_scene.instantiate()
	if not status_text_instance:
		push_error("Failed to instantiate status text scene.")
		return
		
	target_character.add_child(status_text_instance)
	status_text_instance.global_position = target_character.global_position - Vector2(0, 70) # 示例偏移

	if status_text_instance.has_method("setup"):
		status_text_instance.setup(text, color)
	else:
		push_warning("StatusText scene does not have a 'setup' method.")
		if status_text_instance.has_node("Label"):
			(status_text_instance.get_node("Label") as Label).text = text
			(status_text_instance.get_node("Label") as Label).modulate = color

	print("Showed status text: '%s' on %s" % [text, target_character.character_name])

## 播放角色攻击动画 (简易版，实际可能需要更复杂的动画状态机控制)
## [param attacker] 攻击者
## [param targets] 目标 (可以是单个角色或角色数组)
## [param skill_animation_name] 技能特定的动画名称 (可选)
func play_attack_animation(attacker: Character, targets: Array[Character], skill_animation_name: String = "") -> Signal:
	if not is_instance_valid(attacker): 
		return Signal() # 返回一个立即完成的信号
		
	print("%s plays attack animation towards %s (Skill: %s)" % [attacker.character_name, targets, skill_animation_name if skill_animation_name else "Default Attack"])
	
	# 实际的动画播放逻辑:
	# 1. 获取 attacker 的 AnimationPlayer
	# 2. 播放指定的动画 (skill_animation_name 或默认攻击动画)
	# 3. 等待动画完成 (yield attacker.animation_player.animation_finished)
	
	# 模拟动画播放延迟
	var tween = get_tree().create_tween()
	tween.tween_interval(0.5) # 假设动画持续0.5秒
	await tween.finished
	
	return tween.finished # 返回动画完成的信号

## 播放角色受击动画
func play_hit_animation(target_character: Character) -> Signal:
	if not is_instance_valid(target_character):
		return Signal() # 返回一个立即完成的信号

	print("%s plays hit animation" % target_character.character_name)
	# 实际的受击动画逻辑
	# ...
	var tween = get_tree().create_tween()
	tween.tween_interval(0.2) 
	await tween.finished
	return tween.finished

## 播放角色死亡动画
func play_death_animation(character: Character) -> Signal:
	if not is_instance_valid(character):
		return Signal() # 返回一个立即完成的信号
		
	print("%s plays death animation" % character.character_name)
	# 例如，让角色渐隐
	var tween = get_tree().create_tween()
	tween.tween_property(character, "modulate:a", 0, 0.5) # 0.5秒内透明度变为0
	await tween.finished
	return tween.finished

## 播放技能特效 (例如在目标身上显示一个爆炸效果)
## [param skill_data] 使用的技能数据
## [param caster] 施法者
## [param targets] 技能目标
func play_skill_visual_effects(skill_data: SkillData, caster: Character, targets: Array[Character]) -> Signal:
	if not skill_data:
		return Signal() # 返回一个立即完成的信号

	print("Playing visual effects for skill: %s by %s on %s" % [skill_data.skill_name, caster.character_name, targets])
	
	# 根据 skill_data.visual_effect_scene_path (假设有这个属性) 来实例化特效
	# if skill_data.visual_effect_scene_path and not skill_data.visual_effect_scene_path.is_empty():
	# 	var vfx_scene = load(skill_data.visual_effect_scene_path) as PackedScene
	# 	if vfx_scene:
	# 		for target in targets:
	# 			if is_instance_valid(target):
	# 				var vfx_instance = vfx_scene.instantiate()
	# 				target.add_child(vfx_instance) # 或者添加到全局层
	# 				# vfx_instance.global_position = target.global_position
	# 				# 如果特效节点有自己的播放逻辑和完成信号，可以 await 它
	# else:
	# 	print("No specific visual effect scene for skill: ", skill_data.skill_name)

	# 模拟特效播放
	var tween = get_tree().create_tween()
	tween.tween_interval(0.3) # 假设特效持续0.3秒
	await tween.finished
	return tween.finished

# --- 其他可能的视觉效果方法 ---
# func show_buff_applied_effect(target: Character, buff_name: String)
# func show_debuff_applied_effect(target: Character, debuff_name: String)
# func highlight_active_character(character: Character)
# func dim_inactive_characters(characters_to_dim: Array[Character])
