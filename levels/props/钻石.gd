class_name DiamondPickup extends Area2D

const 宝石 = preload("uid://y38hr21ri3p1")
const DIAMOND_ITEM := preload( "res://pause_menu/bag/items/diamond.tres" )



func _ready() -> void:
	body_entered.connect( _on_body_entered )
	body_exited.connect( _on_body_exited )
	#已拾取过的钻石不再刷新（切换地图/读档后保持已收集状态）
	if SaveManager.persistent_data.has( _get_persistent_id() ):
		queue_free()
		return
	pass


func _on_body_entered( n : Node2D ) -> void:
	if n is not Player:
		return
	Messages.player_interacted.connect( _on_player_interacted )
	Messages.input_hint_changed.emit( "interact" )
	pass


func _on_body_exited( n : Node2D ) -> void:
	if n is not Player:
		return
	if Messages.player_interacted.is_connected( _on_player_interacted ):
		Messages.player_interacted.disconnect( _on_player_interacted )
	Messages.input_hint_changed.emit( "" )
	pass


func _on_player_interacted( player : Player ) -> void:
	#立即断开连接，防止同一帧重复触发
	if Messages.player_interacted.is_connected( _on_player_interacted ):
		Messages.player_interacted.disconnect( _on_player_interacted )
	Messages.input_hint_changed.emit( "" )
	#记录持久化状态：拾取后切换地图/读档不再刷新
	SaveManager.persistent_data[ _get_persistent_id() ] = true
	player.diamond += 1
	Inventory.add_item( DIAMOND_ITEM , 1 )
	Audio.play_spatial_sound( 宝石 , global_position )
	Messages.diamond_collected.emit( player.diamond )
	# 保存钻石进度（保留存档点位置），确保死亡重生后钻石不丢失且回到存档点
	SaveManager.save_progress()
	queue_free()
	pass


#生成当前钻石在存档中的唯一ID：场景路径+节点路径，与Breakable持久化键格式一致
func _get_persistent_id() -> String:
	var scene_root : Node = get_tree().current_scene
	if scene_root:
		return str( scene_root.scene_file_path ) + "|" + str( scene_root.get_path_to( self ) )
	return str( get_path() )
