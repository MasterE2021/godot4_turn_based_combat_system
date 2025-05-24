extends RefCounted
class_name EffectProcessor

## 效果处理器基类
## 所有具体效果处理器都应继承此类，并实现相应的方法

# 处理上下文
var _context = null

## 设置处理上下文
## [param context] 处理上下文，通常包含视觉效果处理器等
func set_context(context) -> void:
	_context = context

## 构造函数
func _init(p_context = null):
	set_context(p_context)

## 处理效果 - 主要接口方法
## [return] 处理结果的字典
func process_effect(_effect: SkillEffectData, _source: Character, _target: Character) -> Dictionary:
	push_error("EffectProcessor.process_effect() 必须被子类重写")
	return {}

## 获取效果处理器ID
## [return] 处理器ID
func get_processor_id() -> StringName:
	push_error("EffectProcessor.get_processor_id() 必须被子类重写")
	return "base"

## 检查是否可以处理指定效果类型
## [param effect] 要检查的效果
## [return] 是否可以处理
func can_process_effect(_effect: SkillEffectData) -> bool:
	# 默认实现，子类应该根据需要重写
	return false

## 通用辅助方法
## [param effect_type] 视觉效果类型
## [param target] 目标角色
## [param params] 视觉效果参数
## 发送视觉效果请求
func _request_visual_effect(effect_type: StringName, target, params: Dictionary = {}):
	if not _context or not _context.visual_effects_handler or not is_instance_valid(target):
		return
		
	# 分发到适当的视觉效果方法
	if _context.visual_effects_handler.has_method("create_damage_number"):
		if effect_type == "damage":
			_context.visual_effects_handler.create_damage_number(target, params.get("amount", 0), false)
		elif effect_type == "heal":
			_context.visual_effects_handler.create_damage_number(target, params.get("amount", 0), true)
	
	if _context.visual_effects_handler.has_method("play_hit_animation") and effect_type == "damage":
		_context.visual_effects_handler.play_hit_animation(target)
	
	if _context.visual_effects_handler.has_method("play_heal_animation") and effect_type == "heal":
		_context.visual_effects_handler.play_heal_animation(target)
	
	if _context.visual_effects_handler.has_method("show_status_text"):
		if effect_type == "status":
			_context.visual_effects_handler.show_status_text(target, params.get("text", "Status"), true)
		elif effect_type == "dispel":
			_context.visual_effects_handler.show_status_text(target, "Dispelled: " + params.get("status_id", "Status"), true)
