@icon( "res://player/states/state.svg" )
class_name PlayerState extends Node

var player : Player
var next_state : PlayerState

#region /// state references
@onready var run: PlayerStateRun = %Run
@onready var idle: PlayerStateIdle = %Idle
@onready var jump: PlayerStateJump = %Jump
@onready var fall: PlayerStateFall = %Fall
@onready var crouch: PlayerStateCrouch = %Crouch
@onready var attack: PlayerStateAttack = %Attack
@onready var take_damage: PlayerStateTakeDamage = %TakeDamage
@onready var death: PlayerStateDeath = %Death
#endregion


#状态初始化时做什么
func init() -> void:
	pass
	
	
#当我们进入这个状态时会发生什么
func enter() -> void:
	pass
	
#当我们退出这个状态会发生什么
func exit() -> void:
	pass

#按下输入会发生什么
func handle_input( _event : InputEvent ) -> PlayerState:
	return next_state
	
	
#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:

	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	return next_state
