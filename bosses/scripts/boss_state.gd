@icon( "res://general/icons/state.svg" )
class_name BossState extends Node

## BOSS 状态基类：每个状态一个脚本 + 场景节点（unique_name_in_owner = true）。
## 由 BossStateMachine 注册并驱动；状态之间不互相引用，
## 需要转移时统一走 boss.decision_engine 取目标状态，再交给 boss.state_machine 切换。

var state_machine : BossStateMachine
var boss : Boss
var blackboard : BossBlackboard


func enter() -> void:
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta : float ) -> void:
	pass
