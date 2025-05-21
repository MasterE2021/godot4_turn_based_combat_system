extends EffectProcessor
class_name ApplyStatusEffectProcessor

## 状态效果处理器

func get_processor_id() -> StringName:
    return &"STATUS" # 确保与 BattleManager.get_processor_id_for_effect 中 STATUS 类型对应的值一致

func can_process_effect(effect_data: SkillEffectData) -> bool:
    return effect_data.effect_type == SkillEffectData.EffectType.STATUS

func process_effect(effect_data: SkillEffectData, source: Character, target: Character, skill_context: SkillData = null) -> Dictionary:
    var status_template_to_apply: SkillStatusData = effect_data.status
    if not is_instance_valid(status_template_to_apply):
        return {"success": false, "error": "invalid_status_template_in_effect_data", "applied_status_id": null}

    var chance = effect_data.application_chance
    var results = {
        "success": false,
        "applied_status_id": status_template_to_apply.status_id, 
        "target_name": target.character_name,
        "reason": "chance_failed" 
    }

    if randf() <= chance:
        # 调用目标角色的 apply_status_effect 方法
        var application_result: Dictionary = await target.apply_status_effect(status_template_to_apply, source, effect_data)
        results["success"] = application_result.get("applied_successfully", false)
        results["reason"] = application_result.get("reason", "unknown_char_method_reason")
        
        var applied_status_instance: SkillStatusData = application_result.get("status_instance")

        if results.success and is_instance_valid(applied_status_instance):
            # 状态成功应用/更新后，触发其初始效果
            if not applied_status_instance.initial_effects.is_empty():
                if _battle_manager and _battle_manager.has_method("_apply_skill_effects_to_targets"):
                    await _battle_manager._apply_skill_effects_to_targets(
                        applied_status_instance.get_initial_effects(), 
                        applied_status_instance.source_char, 
                        [target],
                        skill_context
                    )
                else:
                    push_warning("ApplyStatusEffectProcessor: Cannot trigger initial_effects: BattleManager or _apply_skill_effects_to_targets method not found.")
            
            if effect_data.visual_effect_key != "":
                _request_visual_effect(effect_data.visual_effect_key, target, 
                    {"status_name": status_template_to_apply.status_name, 
                        "is_buff": status_template_to_apply.status_type == SkillStatusData.StatusType.BUFF})
    return results
