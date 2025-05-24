extends RefCounted
class_name EffectProcessor

## 效果处理器基类
## 所有具体效果处理器都应继承此类，并实现相应的方法

## 处理效果 - 主要接口方法
## [return] 处理结果的字典
func process_effect(_effect: SkillEffectData, source: Character, _target: Character) -> Dictionary:
	# 延迟一帧执行
	await source.get_tree().process_frame
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
func _request_visual_effect(effect_type: StringName, target, params: Dictionary = {}) -> void:
	SkillSystem.request_visual_effect(effect_type, target, params)
