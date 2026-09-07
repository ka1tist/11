class_name CoinPickup extends CharacterBody2D

const 金币 = preload("uid://41602xkilaj5")



@export var coin_amount : float = 1.0

var bounce_count : int = 8

@onready var area_2d: Area2D = $Area2D



func _ready() -> void:
	area_2d.body_entered.connect( _on_player_entered )
	pass



func _physics_process( delta: float ) -> void:
	if bounce_count > 0:
		velocity += get_gravity() * delta
		var collision : KinematicCollision2D = move_and_collide( velocity * delta )
		if collision:
			bounce_count -= 1
			velocity = velocity.bounce( collision.get_normal() ) * 0.75
			velocity.x *= 0.75
	pass




func _on_player_entered( n : Node2D ) -> void:
	if n is Player:
		area_2d.body_entered.disconnect( _on_player_entered )
		n.coin += int( coin_amount )
		Audio.play_spatial_sound( 金币 , global_position )
		Messages.coin_collected.emit( n.coin )
		queue_free()
	pass
