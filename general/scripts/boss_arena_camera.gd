extends Node

## BOSS 战镜头限制：玩家交互唤醒 BOSS（Messages.boss_awakened）后，把镜头钳制在左右两道门之间，
## 镜头看不到门外的区域；BOSS 被击败（Messages.boss_defeated）后解除限制、镜头随玩家自由移动。
## 复用 LevelBounds 的隐藏墙镜头限制机制（Breakable 用的同一套），自身不改 Camera2D 参数。

#左右两道门（scene 里固定挂在 props 下，_ready 时按路径解析；解析不到会明确报警而不是静默跳过）
var _left_door : Node2D
var _right_door : Node2D


func _ready() -> void:
	_left_door = get_parent().get_node_or_null( "props/Door" ) as Node2D
	_right_door = get_parent().get_node_or_null( "props/Door2" ) as Node2D
	if _left_door == null:
		push_warning( "BossArenaCamera：找不到左门（props/Door），镜头左边界不会受限" )
	if _right_door == null:
		push_warning( "BossArenaCamera：找不到右门（props/Door2），镜头右边界不会受限" )
	#诊断输出：确认本节点确实进了场景、以及门是否解析到（排查限制不生效时可据此定位断点，确认无误后可删）
	print( "[BossArenaCamera] 已就绪：左门=%s 右门=%s" % [ _left_door , _right_door ] )
	Messages.boss_awakened.connect( _on_boss_awakened )
	Messages.boss_defeated.connect( _on_boss_defeated )
	pass


#开战：向 LevelBounds 注册左右两道边界（id 带节点路径，避免同一关多处限制互相覆盖）
func _on_boss_awakened() -> void:
	var bounds : LevelBounds = get_tree().get_first_node_in_group( "level_bounds" )
	if bounds == null:
		push_warning( "BossArenaCamera：场景里没有 LevelBounds（level_bounds 组为空），镜头限制无法生效" )
		return
	#side=1 限制镜头左边界、side=2 限制镜头右边界（与 Breakable 的 camera_limit_side 取值一致）
	if _left_door != null:
		bounds.set_camera_wall_limit( _limit_id( "left" ) , 1 , _left_door.global_position.x )
	if _right_door != null:
		bounds.set_camera_wall_limit( _limit_id( "right" ) , 2 , _right_door.global_position.x )
	_report_limits()
	pass


#战斗结束：门已打开，解除限制，镜头平滑扩展回 LevelBounds 基础边界
func _on_boss_defeated() -> void:
	var bounds : LevelBounds = get_tree().get_first_node_in_group( "level_bounds" )
	if bounds == null:
		return
	bounds.clear_camera_wall_limit( _limit_id( "left" ) , 1 )
	bounds.clear_camera_wall_limit( _limit_id( "right" ) , 2 )
	pass


func _limit_id( side_name : String ) -> String:
	return str( get_path() ) + "_" + side_name


#诊断输出：打印限制写入后的相机边界，确认是否真的落到 Camera2D 上（确认无误后可删）
func _report_limits() -> void:
	var camera : Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		print( "[BossArenaCamera] 当前视口没有相机，限制已登记但无法确认是否生效" )
		return
	print( "[BossArenaCamera] 镜头限制已应用：limit_left=%d limit_right=%d" % [ camera.limit_left , camera.limit_right ] )
	pass
