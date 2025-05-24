extends Node
class_name BattleStateManager

## 战斗状态管理器
## 管理战斗流程的各个状态
## 状态切换时会触发_on_exit_state和_on_enter_state

## 战斗状态枚举
enum BattleState {
	IDLE,           				# 战斗未开始或已结束的空闲状态
	BATTLE_START,   				# 战斗初始化阶段
	ROUND_START,    				# 回合开始，处理回合初效果，决定行动者
	PLAYER_TURN,    				# 等待玩家输入并执行玩家行动
	ENEMY_TURN,     				# AI 决定并执行敌人行动
	ACTION_EXECUTION, 				# 正在执行某个角色的具体行动
	ROUND_END,      				# 回合结束，处理回合末效果，检查胜负
	VICTORY,        				# 战斗胜利
	DEFEAT          				# 战斗失败
}
## 当前状态
var current_state: BattleState = BattleState.IDLE
## 状态变化信号
signal state_changed(old_state, new_state)

## 切换到指定状态
## [param new_state] 要切换到的状态
func change_state(new_state: BattleState) -> void:
	if current_state == new_state:
		return
		
	var old_state = current_state
	current_state = new_state
	
	# 执行离开前一状态的逻辑
	_on_exit_state(old_state)
	
	# 执行进入新状态的逻辑
	_on_enter_state(new_state)
	
	# 发出状态变化信号
	state_changed.emit(old_state, new_state)

## 检查是否在指定状态
## [param state] 要检查的状态
## [return] 是否在指定状态
func is_in_state(state: BattleState) -> bool:
	return current_state == state

## 获取状态名称
## [param state] 要获取名称的状态
## [return] 状态名称
func get_state_name(state: BattleState = current_state) -> String:
	match state:
		BattleState.IDLE: return "空闲"
		BattleState.BATTLE_START: return "战斗开始"
		BattleState.ROUND_START: return "回合开始"
		BattleState.PLAYER_TURN: return "玩家回合"
		BattleState.ENEMY_TURN: return "敌人回合"
		BattleState.ACTION_EXECUTION: return "行动执行中"
		BattleState.ROUND_END: return "回合结束"
		BattleState.VICTORY: return "胜利"
		BattleState.DEFEAT: return "失败"
		_: return "未知状态"

## 检查是否可以玩家行动
func can_player_action() -> bool:
	return current_state == BattleState.PLAYER_TURN

## 检查是否可以敌人行动	
func can_enemy_action() -> bool:
	return current_state == BattleState.ENEMY_TURN

## 检查战斗是否结束
func is_battle_over() -> bool:
	return current_state == BattleState.VICTORY or current_state == BattleState.DEFEAT

## 离开指定状态
## [param state] 要离开的状态
func _on_exit_state(state: BattleState) -> void:
	match state:
		BattleState.PLAYER_TURN:
			print("玩家回合结束")
		BattleState.ENEMY_TURN:
			print("敌人回合结束")
		BattleState.ROUND_END:
			print("回合结束")
		# 其他状态...

## 进入指定状态
## [param state] 要进入的状态
func _on_enter_state(state: BattleState) -> void:
	match state:
		BattleState.BATTLE_START:
			print("战斗开始！")
		BattleState.ROUND_START:
			print("新回合开始")
		BattleState.PLAYER_TURN:
			print("玩家回合开始")
		BattleState.ENEMY_TURN:
			print("敌人回合开始")
		BattleState.VICTORY:
			print("战斗胜利！")
		BattleState.DEFEAT:
			print("战斗失败...")
		BattleState.ACTION_EXECUTION:
			print("执行行动中...")
		# 其他状态...
