@icon( "res://general/icons/attack_area.svg" )
class_name AttackArea extends Area2D

@export var damege : float = 1
#开启后碰到Breakable直接摧毁（与ground_slam的ShapeCast判定一致），不走扣血流程
@export var instant_destroy_breakable : bool = false


func _ready() -> void:
	body_entered.connect( _on_body_entered )
	area_entered.connect( _on_body_entered )
	visible = false
	monitorable = false
	monitoring = false
	pass


func _on_body_entered( body : Node2D ) -> void:
	if body is DamageArea:
		if instant_destroy_breakable and body.get_parent() is Breakable:
			var b : Breakable = body.get_parent()
			#destroy()内走完整击破流程（destroyed信号/音效/粒子/淡出），AbilityPickup等依赖destroyed信号
			b.destroy()
		else:
			body.take_damage( self )
		var pos : Vector2 = global_position
		pos.x = body.global_position.x
		VisualEffects.hit_dust( pos )
	pass


func activate( duration : float = 0.1 ) -> void:
	set_activate( true )
	await get_tree().create_timer( duration ).timeout
	set_activate( false )
	pass


func set_activate( value : bool = true ) -> void:
	monitoring = value
	visible = value
	pass

func flip( direction_x : float ) -> void:
	if direction_x > 0:
		scale.x = 1
	elif direction_x < 0:
		scale.x = -1
