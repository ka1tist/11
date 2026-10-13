@icon( "res://general/icons/state_machine.svg" )
class_name BossStateMachine extends Node

var boss : Boss
var blackboard : BossBlackboard
var states : Array[ BossState ]

var current_state : BossState :
	get():
		return states.front()

var prev_state : BossState :
	get():
		return states.get( 1 )


func setup( b : Boss , bb : BossBlackboard ) -> void:
	blackboard = bb
	boss = b
	#子状态按场景中的顺序注册，第一个子节点即初始状态（必须为 BSIdle）
	for c in get_children():
		if c is BossState:
			c.blackboard = bb
			c.boss = b
			c.state_machine = self
			states.append( c )
	current_state.enter()
	pass


func change_state( new_state : BossState ) -> void:
	if not new_state:
		return

	#同一状态：只重入，不重播进入逻辑（与原实现 _change 的同状态早退等价）
	if new_state == current_state:
		current_state.re_enter()
		return

	if current_state:
		current_state.exit()

	states.push_front( new_state )
	current_state.enter()
	if boss and boss.decision_engine:
		boss.decision_engine.current_state = new_state
	states.resize( 2 )
	pass


func physics_update( delta : float ) -> void:
	if current_state:
		current_state.physics_update( delta )
	pass
