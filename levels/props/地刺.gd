extends Node2D
## 地刺陷阱：玩家进入判定范围 → 扣除10点生命（走现有伤害系统）→ 全屏黑屏淡入 →
## 保持全黑0.5秒 → 黑幕淡出恢复正常显示；
## 玩家在全黑期间被传送回"进入判定范围前"记录的安全位置
## （安全位置=站在地面上且未接触任何地刺判定范围时的玩家位置，每物理帧持续记录）

@export var damage : float = 2.0
## 全黑保持时长（秒）
@export var black_hold_duration : float = 0.5
## 黑屏淡入/淡出时长（秒）
@export var fade_duration : float = 0.1

var hazard_area : HazardArea
var safe_position : Vector2 = Vector2.ZERO
var _has_safe_position : bool = false
var _candidate_position : Vector2 = Vector2.ZERO
var _candidate_grounded : bool = false
var _has_candidate : bool = false
var _sequence_active : bool = false
var _pinned_player : Player = null
var _overlay : ColorRect


func _ready() -> void:
	_build_hazard_area()
	_build_overlay()
	hazard_area.area_entered.connect( _on_hazard_area_entered )
	pass


#依据TileMapLayer已绘制的图块逐格生成判定形状，保证判定范围与地刺画面完全一致
func _build_hazard_area() -> void:
	hazard_area = HazardArea.new()
	hazard_area.name = "HazardArea"
	hazard_area.collision_layer = 0
	hazard_area.collision_mask = 16
	hazard_area.damege = damage
	add_child( hazard_area )
	var tilemap : TileMapLayer = $Sprite2D/TileMapLayer
	for cell in tilemap.get_used_cells():
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2( tilemap.tile_set.tile_size )
		shape.shape = rect
		hazard_area.add_child( shape )
		shape.global_position = tilemap.to_global( tilemap.map_to_local( cell ) )
	pass


#创建全屏黑幕：CanvasLayer不受相机与场景变换影响，layer=100覆盖包括HUD在内的一切
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BlackScreen"
	layer.layer = 100
	add_child( layer )
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = Color.BLACK
	_overlay.modulate.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset( Control.PRESET_FULL_RECT )
	layer.add_child( _overlay )
	pass


func _physics_process(_delta: float) -> void:
	#黑屏期间把玩家钉在安全位置：防止受击击退/重力在黑幕掩盖下把玩家推离传送落点
	if _pinned_player != null:
		_pin_player()
		return
	_record_safe_position()
	pass


func _pin_player() -> void:
	#玩家在黑屏期间死亡则解除钉住，交还给现有死亡流程
	if is_instance_valid( _pinned_player ) == false or _pinned_player.hp <= 0:
		_pinned_player = null
		return
	_pinned_player.global_position = safe_position
	_pinned_player.velocity = Vector2.ZERO
	pass


func _record_safe_position() -> void:
	var player := get_tree().get_first_node_in_group( "Player" ) as Player
	if player == null or player.hp <= 0:
		return
	#用玩家本体检测接触：受击无敌帧会禁用DamageArea的物理同步，
	#此时overlaps_area对它是过期结果，而本体碰撞体始终可靠
	if hazard_area.overlaps_body( player ):
		_has_candidate = false
		return
	#物理服务端已同步的本体坐标：节点transform被外部改动后（如测试/传送），
	#节点坐标会领先于物理服务端，用服务端坐标才能保证记录位置与碰撞判定来自同一状态
	var pos : Vector2 = PhysicsServer2D.body_get_state(
		player.get_rid() , PhysicsServer2D.BODY_STATE_TRANSFORM ).origin
	#overlaps_body结果滞后一个物理步：本帧记录"候选位置"，下一帧物理确认仍未接触时
	#才提交为安全位置，避免把"节点坐标已进入判定范围但碰撞尚未确认"的那一帧记录进去
	if _has_candidate and _candidate_grounded and player.is_on_floor():
		safe_position = _candidate_position
		_has_safe_position = true
	_candidate_position = pos
	_candidate_grounded = player.is_on_floor()
	_has_candidate = true
	pass


#玩家受击区进入判定范围：伤害由HazardArea(AttackArea)标准流程先行处理，
#本回调在其后触发（子节点_ready先连接信号），此时hp已被扣除
func _on_hazard_area_entered( area : Area2D ) -> void:
	if not ( area is DamageArea ):
		return
	if _sequence_active:
		return
	var player := get_tree().get_first_node_in_group( "Player" ) as Player
	if player == null or player.hp <= 0:
		#致死伤害交给现有死亡流程处理，不再黑屏传送
		return
	_sequence_active = true
	_run_trap_sequence( player )
	pass


func _run_trap_sequence( player : Player ) -> void:
	#1) 全屏黑幕淡入
	var fade_in := create_tween()
	fade_in.tween_property( _overlay , "modulate:a" , 1.0 , fade_duration )
	await fade_in.finished
	#2) 全黑期间传送回进入判定范围前的安全位置
	if _has_safe_position:
		_pinned_player = player
		player.global_position = safe_position
		player.velocity = Vector2.ZERO
		var cam := get_viewport().get_camera_2d()
		if cam is PlayerCamera:
			cam.reset_smoothing()
	#3) 保持全黑0.5秒
	await get_tree().create_timer( black_hold_duration ).timeout
	#4) 黑幕淡出，恢复正常显示
	var fade_out := create_tween()
	fade_out.tween_property( _overlay , "modulate:a" , 0.0 , fade_duration )
	await fade_out.finished
	_pinned_player = null
	_sequence_active = false
	pass


#当前黑幕不透明度（0=正常显示，1=全黑），供单元测试断言触发时机
func get_overlay_alpha() -> float:
	return _overlay.modulate.a
