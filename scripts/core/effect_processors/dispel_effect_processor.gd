extends EffectProcessor
class_name DispelEffectProcessor

func get_processor_id() -> StringName:
    return &"DISPEL"

func can_process_effect(effect_data: SkillEffectData) -> bool:
    return effect_data.effect_type == SkillEffectData.EffectType.DISPEL

## 
func process_effect(effect_data: SkillEffectData, _source: Character, target: Character, _skill_context: SkillData = null) -> Dictionary:
    if effect_data.effect_type != SkillEffectData.EffectType.DISPEL:
        return {"success": false, "error": "wrong_effect_type_for_processor", "dispelled_count": 0}

    if not is_instance_valid(target) or not target.has_method("remove_status_effect"):
        return {"success": false, "error": "invalid_target_or_missing_method", "dispelled_count": 0}

    var dispel_type_enum_val: int = effect_data.dispel_status_type # 这是枚举的整数值
    var count_to_dispel: int = effect_data.dispel_count
    var dispel_all: bool = effect_data.dispel_all_of_type
    
    var dispelled_count_actual: int = 0
    var dispelled_ids: Array[StringName] = []

    var target_active_statuses_copy = []
    if target.has_method("get_all_active_status_instances_for_check"):
         target_active_statuses_copy = target.get_all_active_status_instances_for_check().duplicate()


    for status_instance: SkillStatusData in target_active_statuses_copy:
        if not is_instance_valid(status_instance): continue

        if status_instance.status_type == dispel_type_enum_val: 
            if dispel_all or dispelled_count_actual < count_to_dispel:
                var bm_ref = _get_battle_manager() 
                var removed = await target.remove_status_effect(status_instance.status_id, true, bm_ref)
                if removed:
                    dispelled_count_actual += 1
                    dispelled_ids.append(status_instance.status_id)
            else: 
                break 
    
    if dispelled_count_actual > 0:
        if effect_data.visual_effect_key != "":
            var type_key = "UNKNOWN_TYPE"
            # 确保 SkillStatusData 类已加载或通过 defined 检查
            if Engine.is_singleton_registered("SkillStatusData") and "StatusType" in SkillStatusData:
                if dispel_type_enum_val < SkillStatusData.StatusType.size():
                    type_key = SkillStatusData.StatusType.keys()[dispel_type_enum_val]
            _request_visual_effect(effect_data.visual_effect_key, target, {"count": dispelled_count_actual, "type_dispelled_key": type_key})
        return {"success": true, "dispelled_count": dispelled_count_actual, "dispelled_ids": dispelled_ids}
    else:
        return {"success": false, "reason": "no_matching_effects_to_dispel", "dispelled_count": 0}
