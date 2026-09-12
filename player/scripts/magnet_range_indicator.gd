@tool
extends Node2D
## 磁吸范围可视化 + 调节手柄（仅编辑器绘制，运行时不画）：
## 1) 在视口里拖动本节点 → 圆心始终是角色中心，半径=节点到角色中心的距离，实时同步到 Player.loot_magnet_range
## 2) 在 Inspector 里改 magnet_range → 圆圈变化，本节点自动吸附到圆周对应位置
## 3) 直接改 Player 的 loot_magnet_range → 圆圈跟随（三种方式双向同步）
## 游戏运行时实际读取的是 Player.loot_magnet_range，本节点只负责编辑期显示与调参
## 必须挂在 Player 根节点下；注意玩家根节点 scale.x≈-1，手柄的世界方向与局部坐标镜像，但距离不受影响

const CIRCLE_COLOR := Color( 0.35 , 0.9 , 1.0 , 0.85 )
const FILL_COLOR := Color( 0.35 , 0.9 , 1.0 , 0.07 )
#磁吸圆心在玩家局部坐标下的位置（胶囊中心），须与 player.gd 的 LOOT_MAGNET_CENTER_OFFSET 一致
const MAGNET_CENTER := Vector2( 0 , -26 )
const MIN_HANDLE_DIST := 0.01  #节点位于圆心时的方向兜底阈值

## 吸取半径（像素），0=禁用磁吸；与节点到角色中心的距离保持同步
@export var magnet_range : float = 40.0 :
	set( value ):
		magnet_range = maxf( 0.0 , value )
		queue_redraw()
		#拖拽来源时节点已经在圆周上，不再回写位置，避免与编辑器拖拽互相拉扯
		if _from_drag == false:
			_sync_position_to_range()
		#_ready之前（场景实例化阶段）禁止推送：此时父节点属性尚未就绪，
		#推送会用本节点默认值覆盖Player已存储的范围值
		if _armed:
			_push_to_player()

var _armed : bool = false
var _from_drag : bool = false
var _syncing_position : bool = false
var _last_player_range : float = -1.0


func _ready() -> void:
	_armed = true
	if Engine.is_editor_hint():
		set_notify_local_transform( true )
		#加载时以Player当前值为准，避免两边数值不同步，并把手柄吸附到圆周上
		_sync_from_player()
		_sync_position_to_range()
	pass


func _notification( what : int ) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		return
	#视口拖拽节点位置 → 半径跟随（仅编辑器）
	if _syncing_position or Engine.is_editor_hint() == false:
		return
	var r := roundf( ( position - MAGNET_CENTER ).length() * 100.0 ) / 100.0
	if is_equal_approx( r , magnet_range ) == false:
		_from_drag = true
		magnet_range = r
		_from_drag = false
	pass


func _process( _delta : float ) -> void:
	#编辑器下轮询：用户直接改Player的loot_magnet_range时圆圈跟随
	if Engine.is_editor_hint() == false:
		return
	_sync_from_player()
	pass


#Player脚本是非@tool脚本，编辑器里是placeholder实例，属性按场景存储值/脚本默认值读取
func _sync_from_player() -> void:
	var player := get_parent() as Player
	if player == null:
		return
	var value = player.get( "loot_magnet_range" )
	if value == null:
		return
	var r := float( value )
	if r != _last_player_range:
		_last_player_range = r
		if r != magnet_range:
			magnet_range = r  #setter会重绘/吸附手柄并把相同值推回Player（无副作用）
	pass


#Inspector改数值时，把手柄节点摆到圆周上（保持原方向；位于圆心时默认放+x方向）
func _sync_position_to_range() -> void:
	if Engine.is_editor_hint() == false:
		return
	var offset := position - MAGNET_CENTER
	var dir := offset.normalized() if offset.length() > MIN_HANDLE_DIST else Vector2.RIGHT
	var target := MAGNET_CENTER + dir * magnet_range
	if target.is_equal_approx( position ) == false:
		_syncing_position = true
		position = target  #触发NOTIFICATION_LOCAL_TRANSFORM_CHANGED，已用标志跳过
		_syncing_position = false
	pass


func _push_to_player() -> void:
	var player := get_parent() as Player
	if player:
		player.set( "loot_magnet_range" , magnet_range )
	pass


func _draw() -> void:
	if Engine.is_editor_hint() == false:
		return
	if magnet_range <= 0.0:
		return
	#圆心画在角色中心：子空间里取 MAGNET_CENTER - position，画到父节点局部(0,-26)处
	var center := MAGNET_CENTER - position
	draw_circle( center , magnet_range , FILL_COLOR )
	draw_arc( center , magnet_range , 0.0 , TAU , 96 , CIRCLE_COLOR , 1.5 , true )
	#中心小十字标记角色中心（吸取距离的圆心）
	draw_line( center + Vector2( -6 , 0 ) , center + Vector2( 6 , 0 ) , CIRCLE_COLOR , 1.5 , true )
	draw_line( center + Vector2( 0 , -6 ) , center + Vector2( 0 , 6 ) , CIRCLE_COLOR , 1.5 , true )
	pass
