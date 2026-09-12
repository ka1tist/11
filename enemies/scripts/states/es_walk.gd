class_name ESWalk
extends EnemyState

@export var walk_speed : float = 50.0

var left_limit : float
var right_limit : float


func _ready() -> void:
	_set_limits()
	pass



func enter() -> void:
	var anim : String = animation_name if animation_name else "walk"
	enemy.play_animation( anim )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta: float ) -> void:
	if enemy.is_on_wall():
		enemy.change_dir( -blackboard.dir )
	elif enemy.global_position.x <= left_limit and blackboard.dir < 0:
		enemy.change_dir( 1.0 )
	elif enemy.global_position.x >= right_limit and blackboard.dir > 0:
		enemy.change_dir( -1.0 )
	enemy.velocity.x = walk_speed * blackboard.dir
	pass


func _set_limits() -> void:
	left_limit = owner.global_position.x - 5000
	right_limit = owner.global_position.x + 5000
	# PatrolLimit 在关卡场景中挂在敌人根节点下（owner 与本状态节点不同），
	# 必须从 owner 子树递归查找并传 owned=false
	for c in owner.find_children( "*", "PatrolLimit", true, false ):
		if c.side == Side.SIDE_LEFT:
			left_limit = c.global_position.x
		if c.side == Side.SIDE_RIGHT:
			right_limit = c.global_position.x
	pass
