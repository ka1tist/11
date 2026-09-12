@tool
@icon( "res://general/icons/patrol_limit.svg" )
class_name PatrolLimit extends Node2D

const PATROL_LIMIT = preload("uid://d0p78uho1a7k3")


@export var side : Side = Side.SIDE_LEFT:
	set( value ):
		side = value
		_add_sprite()


func _ready() -> void:
	if Engine.is_editor_hint():
		_add_sprite()
		return
	queue_free()
	pass 



func _add_sprite() -> void:
	if get_child_count() > 0:
		for c in get_children():
			c.queue_free()
	
	var s : Sprite2D = Sprite2D.new()
	add_child( s )
	s.texture = PATROL_LIMIT
	s.position = Vector2( 0 , -16 )
	
	var l : Label = Label.new()
	add_child( l )
	l.size.x = 32
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2( -16 , -24 )
	
	if side == Side.SIDE_LEFT:
		s.modulate = Color.WHITE
		l.text = "L"
		l.modulate = Color( 0.2 , 0.2 , 0.2 )
	if side == Side.SIDE_RIGHT:
		s.modulate = Color.RED
		l.text = "R"
		l.modulate = Color.WHITE
	pass
