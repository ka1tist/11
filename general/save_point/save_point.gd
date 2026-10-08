@icon( "res://general/icons/save_point.svg" )
class_name SavePoint extends Node2D


@onready var area_2d: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $Node2D/AnimationPlayer



func _ready() -> void:
	area_2d.body_entered.connect( _on_player_entered )
	area_2d.body_exited.connect( _on_player_exited )
	pass
	

func _on_player_entered( _n : Node2D ) -> void:
	Messages.player_interacted.connect( _on_player_interacted )
	Messages.input_hint_changed.emit( "interact" )
	pass


func _on_player_exited( _n : Node2D ) -> void:
	#幂等断连：与 NPC1.set_interaction_enabled 的写法一致，防止重复触发时报“信号未连接”
	if Messages.player_interacted.is_connected( _on_player_interacted ):
		Messages.player_interacted.disconnect( _on_player_interacted )
	Messages.input_hint_changed.emit( "" )
	pass


func _on_player_interacted( _player : Player ) -> void:
	Messages.player_healed.emit( 999 )
	SaveManager.save_game()
	animation_player.play( "game_saved" )
	animation_player.seek( 0 )
	Audio.ui_success()
	
	pass


## 开关交互：关闭后不再提示“可交互”，也不会触发存档。
## 供房屋等容器在隐藏存档点时一并断掉屋外误触（做法与 NPC1.set_interaction_enabled 一致）
func set_interaction_enabled( enabled : bool ) -> void:
	area_2d.monitoring = enabled
	if not enabled:
		if Messages.player_interacted.is_connected( _on_player_interacted ):
			Messages.player_interacted.disconnect( _on_player_interacted )
		Messages.input_hint_changed.emit( "" )
	pass
