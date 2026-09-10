class_name Treasure extends Area2D

const ANIM_OPEN := &"open"
const 宝箱 = preload("uid://dwtugrm4uqdsl")

#默认奖励：苹果（可在 Inspector 中替换为任意 ItemData 资源、修改数量）
const DEFAULT_REWARD := preload(  "res://pause_menu/bag/items/grapes.tres" )

#宝箱奖励（开箱后自动放入背包并持久化）
@export var reward_item : ItemData = DEFAULT_REWARD
@export_range( 1 , 99 ) var reward_amount : int = 1

#奖励弹窗参数
const POPUP_START_Y : float = -50.0
const POPUP_RISE : float = 22.0
const POPUP_TOTAL_TIME : float = 1.5
const POPUP_ICON_SIZE : float = 40.0

var _opened : bool = false

@onready var animated_sprite : AnimatedSprite2D = $AnimatedSprite2D



func _ready() -> void:
	animated_sprite.animation = ANIM_OPEN
	animated_sprite.animation_finished.connect( _on_animation_finished )
	#已打开过的宝箱不再提供交互：定格在最终帧（切换地图/读档后保持已打开状态）
	if SaveManager.persistent_data.has( _get_persistent_id() ):
		_show_opened_state()
		return
	body_entered.connect( _on_body_entered )
	body_exited.connect( _on_body_exited )
	pass


#已打开：保持动画最终帧，关闭区域检测，不再弹出交互提示
func _show_opened_state() -> void:
	_opened = true
	monitoring = false
	animated_sprite.pause()
	animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count( ANIM_OPEN ) - 1
	pass


func _on_body_entered( n : Node2D ) -> void:
	if n is not Player or _opened:
		return
	Messages.player_interacted.connect( _on_player_interacted )
	Messages.input_hint_changed.emit( "interact" )
	pass


func _on_body_exited( n : Node2D ) -> void:
	if n is not Player:
		return
	if Messages.player_interacted.is_connected( _on_player_interacted ):
		Messages.player_interacted.disconnect( _on_player_interacted )
	if not _opened:
		Messages.input_hint_changed.emit( "" )
	pass


func _on_player_interacted( _player : Player ) -> void:
	#立即断开连接，防止同一帧重复触发
	if Messages.player_interacted.is_connected( _on_player_interacted ):
		Messages.player_interacted.disconnect( _on_player_interacted )
	Messages.input_hint_changed.emit( "" )
	_opened = true
	monitoring = false
	#记录持久化状态：打开后切换地图/读档保持已打开（ID规则与钻石一致）
	SaveManager.persistent_data[ _get_persistent_id() ] = true
	#发放奖励到背包（同类自动堆叠），按实际放入数量展示反馈
	var got_amount : int = 0
	if reward_item != null and reward_amount > 0:
		got_amount = Inventory.add_item( reward_item , reward_amount )
	#立即保存进度（背包与开箱状态一并落盘，保留存档点位置）
	SaveManager.save_progress()
	#立即播放打开动画（非循环，播完停在最终帧）
	animated_sprite.play( ANIM_OPEN )
	Audio.play_spatial_sound( 宝箱 , global_position )
	#宝箱上方弹出奖励图标+数量（仅实际获得时）
	if got_amount > 0:
		_spawn_reward_popup( got_amount )
	pass


func _on_animation_finished() -> void:
	#非循环动画（Godot 4 的 animation_finished 无参数）播完本就停在最后一帧；
	#pause() 显式保持当前帧（stop() 会回到首帧）
	animated_sprite.pause()
	pass


#在宝箱正上方生成世界空间的奖励反馈：仅显示物品图标
#弹出放大→缓慢上浮→淡出，结束后自动销毁（玩家无需交互）
func _spawn_reward_popup( _amount : int ) -> void:
	if reward_item == null or reward_item.icon == null:
		return
	var popup := Node2D.new()
	popup.name = "RewardPopup"
	popup.position = Vector2( 0 , POPUP_START_Y )
	popup.z_index = 10
	add_child( popup )
	#物品图标（按图标原始尺寸等比缩放到统一显示大小，像素风不糊化），居中于宝箱正上方
	var icon := Sprite2D.new()
	icon.texture = reward_item.icon
	if reward_item.icon.get_width() > 0:
		var s0 : float = POPUP_ICON_SIZE / float( reward_item.icon.get_width() )
		icon.scale = Vector2( s0 , s0 )
	popup.add_child( icon )
	#入场 + 上浮 + 淡出（一条并行 Tween，结束自动清理）
	popup.scale = Vector2( 0.6 , 0.6 )
	popup.modulate.a = 0.0
	var tw := popup.create_tween()
	tw.set_parallel( true )
	tw.tween_property( popup , "scale" , Vector2.ONE , 0.25 ) \
		.from( Vector2( 0.6 , 0.6 ) ) \
		.set_trans( Tween.TRANS_BACK ).set_ease( Tween.EASE_OUT )
	tw.tween_property( popup , "modulate:a" , 1.0 , 0.18 )
	tw.tween_property( popup , "modulate:a" , 0.0 , 0.45 ) \
		.set_delay( POPUP_TOTAL_TIME - 0.45 )
	tw.tween_property( popup , "position:y" , POPUP_START_Y - POPUP_RISE , POPUP_TOTAL_TIME ) \
		.from( POPUP_START_Y ).set_trans( Tween.TRANS_SINE ).set_ease( Tween.EASE_OUT )
	tw.tween_callback( popup.queue_free ).set_delay( POPUP_TOTAL_TIME )
	pass


#生成当前宝箱在存档中的唯一ID：场景路径+节点路径，与钻石/Breakable持久化键格式一致
func _get_persistent_id() -> String:
	var scene_root : Node = get_tree().current_scene
	if scene_root:
		return str( scene_root.scene_file_path ) + "|" + str( scene_root.get_path_to( self ) )
	return str( get_path() )
