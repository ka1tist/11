class_name CoinPickup extends CharacterBody2D

const 金币 = preload("uid://dmf8f37dma7bb")




@export var coin_amount : float = 1.0

## 磁吸追踪速度上限（像素/秒）与加速度（像素/秒²）
@export var magnet_speed : float = 320.0
@export var magnet_accel : float = 1800.0

var bounce_count : int = 8
var _attracted : bool = false

@onready var area_2d: Area2D = $Area2D



func _ready() -> void:
	add_to_group( "loot_drop" )
	area_2d.body_entered.connect( _on_player_entered )
	pass



func _physics_process( delta: float ) -> void:
	#被磁吸后不再受弹跳/重力控制，持续飞向玩家
	if _attracted:
		_home_to_player( delta )
		return
	if bounce_count > 0:
		velocity += get_gravity() * delta
		var collision : KinematicCollision2D = move_and_collide( velocity * delta )
		if collision:
			bounce_count -= 1
			velocity = velocity.bounce( collision.get_normal() ) * 0.75
			velocity.x *= 0.75
	pass



#玩家吸取范围内调用（幂等），激活后追踪直到自身拾取判定收集
func attract() -> void:
	_attracted = true
	pass


func _home_to_player( delta: float ) -> void:
	var player := get_tree().get_first_node_in_group( "Player" ) as Player
	if player == null:
		return
	var to_center : Vector2 = player.get_loot_magnet_center() - global_position
	velocity = velocity.move_toward( to_center.normalized() * magnet_speed , magnet_accel * delta )
	var collision := move_and_collide( velocity * delta )
	if collision:
		#被墙挡住时沿墙滑行，避免原地抖动
		velocity = velocity.slide( collision.get_normal() )
	pass




func _on_player_entered( n : Node2D ) -> void:
	if n is Player:
		area_2d.body_entered.disconnect( _on_player_entered )
		n.coin += int( coin_amount )
		Audio.play_spatial_sound( 金币 , global_position )
		Messages.coin_collected.emit( n.coin )
		# 保存金币进度（保留存档点位置），确保死亡重生后金币不丢失
		SaveManager.save_progress()
		queue_free()
	pass
