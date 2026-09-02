@icon( "res://general/icons/breakable.svg" )
class_name SlamBreakable extends StaticBody2D

#持久化：被ground_slam破坏后记录到SaveManager.persistent_data，切换地图/读档不再刷新，新游戏时重置
@export var persistent : bool = true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	#已破坏过的持久化墙体直接消失，不再刷新
	if persistent and SaveManager.persistent_data.has( _get_persistent_id() ):
		queue_free()


#生成当前墙体在存档中的唯一ID：场景路径+节点路径（与Breakable规则一致）
func _get_persistent_id() -> String:
	var scene_root : Node = get_tree().current_scene
	if scene_root:
		return str( scene_root.scene_file_path ) + "|" + str( scene_root.get_path_to( self ) )
	return str( get_path() )


#外部直接销毁（如ground_slam）时调用，确保持久化状态被记录
func destroy() -> void:
	if persistent:
		SaveManager.persistent_data[ _get_persistent_id() ] = true
	queue_free()
