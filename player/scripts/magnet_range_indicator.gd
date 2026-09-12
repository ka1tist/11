@tool
extends Area2D
## 磁吸范围可视化 + 调节手柄：
## 磁吸范围完全由子节点 CollisionShape2D 的 CircleShape2D 半径决定。
## 编辑器里可直接拖动本节点改变磁吸圆心位置，或选中 CollisionShape2D 拖动圆形半径手柄调节范围；
## 位置与半径都会保存到场景，运行时凋落物以本节点全局位置为追踪目标。
## 运行时通过 Area2D 的 body_entered 信号检测进入范围的凋落物并激活追踪，不再需要轮询。
## 必须挂在 Player 根节点下

const CIRCLE_COLOR := Color( 0.35 , 0.9 , 1.0 , 0.85 )
const FILL_COLOR := Color( 0.35 , 0.9 , 1.0 , 0.07 )
const LOOT_LAYER := 256  #凋落物所在碰撞层（project.godot layer_9="Loot"）

## 吸取半径（像素），0=禁用磁吸；与子节点 CollisionShape2D 的圆形半径双向同步
@export var magnet_range : float = 40.0 :
	set( value ):
		magnet_range = maxf( 0.0 , value )
		_apply_shape_radius( magnet_range )
		queue_redraw()
		#_ready之前（场景实例化阶段）禁止推送：此时父节点属性尚未就绪，
		#推送会用本节点默认值覆盖Player已存储的范围值
		if _armed:
			_push_to_player()

var _collision_shape : CollisionShape2D
var _armed : bool = false
var _last_shape_radius : float = -1.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = LOOT_LAYER
	#抵消父节点（玩家根）的负 scale：玩家根 scale.x≈-1 会使本节点全局变换行列式为负，
	#导致 Area2D 的圆形碰撞在物理服务端被错误判定（远处物体也触发 body_entered）。
	#将本节点 scale 设为玩家 scale 的倒数，使全局有效 scale 为正，碰撞形状恢复正常圆形
	var ps := ( get_parent() as Node2D ).scale
	scale = Vector2( 1.0 / ps.x , 1.0 / ps.y )
	_ensure_collision_shape()
	_armed = true
	if Engine.is_editor_hint():
		#加载时以Player当前值为准对齐形状半径，避免两边数值不同步
		_sync_from_player()
		_last_shape_radius = _get_shape_radius()
	else:
		#运行时：连接信号检测凋落物进入
		body_entered.connect( _on_body_entered )
		#已有重叠凋落物补激活（等物理空间就绪后再查，call_deferred时物理未同步会误判）
		call_deferred( "_check_overlapping_deferred" )
	pass


#确保存在 CollisionShape2D 子节点且形状为 CircleShape2D，并强制其居中于本节点
#（编辑器可能误存偏移位置，导致判定圆心与可视化/追踪目标不一致）
func _ensure_collision_shape() -> void:
	_collision_shape = get_node_or_null( "CollisionShape2D" ) as CollisionShape2D
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "CollisionShape2D"
		#先配好形状再挂到树上，避免物理服务端一帧延迟导致首帧重叠检测异常
		var shape := CircleShape2D.new()
		shape.radius = magnet_range
		_collision_shape.shape = shape
		add_child( _collision_shape )
		if Engine.is_editor_hint():
			_collision_shape.owner = get_tree().edited_scene_root
	else:
		var shape := _collision_shape.shape as CircleShape2D
		if shape == null:
			shape = CircleShape2D.new()
			_collision_shape.shape = shape
		if shape.radius != magnet_range:
			shape.radius = magnet_range
	#碰撞形状始终居中于本节点：圆心由本节点 position 决定，不要偏移 CollisionShape2D
	_collision_shape.position = Vector2.ZERO
	pass


func _get_shape_radius() -> float:
	if _collision_shape and _collision_shape.shape is CircleShape2D:
		return ( _collision_shape.shape as CircleShape2D ).radius
	return magnet_range


func _apply_shape_radius( r : float ) -> void:
	if _collision_shape and _collision_shape.shape is CircleShape2D:
		( _collision_shape.shape as CircleShape2D ).radius = r
	pass


func _process( _delta : float ) -> void:
	#编辑器下轮询形状半径变化：用户在 Inspector/视口拖动圆形半径手柄时实时同步
	if Engine.is_editor_hint() == false:
		return
	var r := _get_shape_radius()
	if r != _last_shape_radius:
		_last_shape_radius = r
		if not is_equal_approx( r , magnet_range ):
			magnet_range = r  #setter会把相同半径写回形状，无副作用
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
	if not is_equal_approx( r , magnet_range ):
		magnet_range = r  #setter同步形状半径+推回Player（无副作用）
	pass


func _push_to_player() -> void:
	var player := get_parent() as Player
	if player:
		player.set( "loot_magnet_range" , magnet_range )
	pass


func _check_overlapping_deferred() -> void:
	#等物理步完成后再查，避免首帧物理空间未同步导致误判
	await get_tree().physics_frame
	for b in get_overlapping_bodies():
		_try_attract( b )
	pass


func _on_body_entered( body : Node2D ) -> void:
	_try_attract( body )
	pass


func _try_attract( body : Node2D ) -> void:
	if body.has_method( "attract" ) == false:
		return
	#距离兜底校验：物理信号在玩家 reparent/负 scale 等场景下可能误报远处重叠，
	#用实际距离二次确认（+16 容差覆盖凋落物自身碰撞半径 5~8px）
	var r := _get_shape_radius() + 16.0
	if global_position.distance_to( body.global_position ) <= r:
		body.attract()
	pass


func _draw() -> void:
	if magnet_range <= 0.0:
		return
	#Area2D自身位置即磁吸圆心，局部原点画圆
	draw_circle( Vector2.ZERO , magnet_range , FILL_COLOR )
	draw_arc( Vector2.ZERO , magnet_range , 0.0 , TAU , 96 , CIRCLE_COLOR , 1.5 , true )
	#中心小十字标记角色中心（吸取距离的圆心）
	draw_line( Vector2( -6 , 0 ) , Vector2( 6 , 0 ) , CIRCLE_COLOR , 1.5 , true )
	draw_line( Vector2( 0 , -6 ) , Vector2( 0 , 6 ) , CIRCLE_COLOR , 1.5 , true )
	pass
