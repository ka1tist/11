class_name ESChase extends EnemyState

@export var chase_speed : float = 100

func enter() -> void:
	enemy.play_animation( animation_name if animation_name else "chase" )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta: float ) -> void:
	var dir : float = sign( blackboard.target.global_position.x - enemy.global_position.x )
	enemy.change_dir( dir )
	enemy.velocity.x = dir * chase_speed
	pass
