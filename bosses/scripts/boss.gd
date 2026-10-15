@tool
@icon( "res://general/icons/boss_orchestrator.svg" )
class_name Boss extends CharacterBody2D

## BOSS 根节点（模块化重构后与小怪同构）
## - 结构：Boss + BossStateMachine + BossState 子状态 + BossDecisionEngine + BossBlackboard
## - 数值与行为与重构前的单文件实现完全一致：
##   阶段阈值每损失 8 点生命切换一次（共 24 血、三阶段）、阶段过场下蹲无敌、
##   一阶段 jump 追击 / 二阶段 crouch→dash→attack / 三阶段 skill_01 跃顶→skill_02 蓄力 2 秒
##   →砸地 npbh_enemy_ground_slam + 左右 npbh_enemy_wave（10 秒内置冷却），
##   jump/dash 共用 5 秒内置冷却，死亡动画，粒子/震屏过场。
## - 物理由各状态脚本自行处理（LEAP / SKILL_CHARGE 不调用 move_and_slide），与本体重构前一致。

#被击败时的广播：掉落系统（lootDropper）等外部对象据此结算掉落，与小怪 Enemy.was_killed 同构
@warning_ignore( "unused_signal" )
signal was_killed()


#开局朝向：勾选后 BOSS 出生即面朝左（与小怪 Enemy.face_left_on_start 同名同义，在关卡实例上按需勾选）
@export var face_left_on_start : bool = false:
	set( value ):
		face_left_on_start = value
		_update_face_left()


#复用已有的 BOSS 专用特效场景（落地砸击 / 左右光波）
const GROUND_SLAM_SCENE : PackedScene = preload( "res://bosses/01/npbh_enemy_ground_slam.tscn" )
const WAVE_SCENE : PackedScene = preload( "res://bosses/01/npbh_enemy_wave.tscn" )
#二阶段专属技能的投射物
const PB_SCENE : PackedScene = preload( "res://bosses/01/pb.tscn" )

#死亡掉落：在尸体处留下的能力球（冲刺）
const DASH_PICKUP_SCENE : PackedScene = preload( "res://general/ability_pickup/ability_pickup.tscn" )
#能力球原点即球心，悬浮在距地面这个高度（与关卡里手工摆放的惯例一致）
const PICKUP_GROUND_OFFSET : float = 24.0
#能力球刚出现时的无敌时间：击破 BOSS 的那一下攻击判定往往还在生效，避免球一落地就被打碎
const PICKUP_INVULNERABLE_TIME : float = 0.8

#砸地爆发音效
const GROUND_SLAM_AUDIO = preload( "res://bosses/01/audio/ground slam.wav" )

const BOSS_NAME : String = "旧日的幻影"

#region /// 数值参数
#生命与阶段
const MAX_HP : float = 24.0
const PHASE_HP_STEP : float = 8.0
const MAX_PHASE : int = 3

#物理
const GRAVITY : float = 980.0
const MAX_FALL_SPEED : float = 900.0

#通用行为
const ATTACK_RANGE : float = 66.0
const DECIDE_DELAY : float = 0.25
#普通攻击内置冷却：冷却中不进入 attack，改走常规追击
const ATTACK_COOLDOWN_MSEC : int = 1000

#追击手段通用：jump 与 dash 共用同一套 5 秒内置冷却，冷却未好时改用 run 追击
const CHASE_COOLDOWN_MSEC : int = 5000
const RUN_SPEED : float = 155.0
const RUN_MIN_TIME : float = 0.25

#一阶段：跳跃贴近
const JUMP_SPEED_X : float = 210.0
const JUMP_FORCE : float = 400.0
const JUMP_GRACE : float = 0.2

#二阶段：下蹲蓄力 → dash → attack
const CHARGE_TIME : float = 0.6
const DASH_SPEED : float = 640.0
const DASH_MIN_TIME : float = 0.12
const DASH_MAX_TIME : float = 0.9
const AFTERIMAGE_INTERVAL : float = 0.05

#蓄力表现：自身颜色在明暗之间循环，用来直观表示正在蓄力
const CHARGE_DARK_COLOR : Color = Color( 0.45 , 0.45 , 0.45 , 1.0 )
const CHARGE_LIGHT_COLOR : Color = Color( 1.0 , 1.0 , 1.0 , 1.0 )
#单向渐变时长（一次完整往复为它的两倍）
const CHARGE_FLASH_TIME : float = 0.12

#三阶段：组合技
const SKILL_COOLDOWN_MSEC : int = 10000
const SKILL_CHARGE_TIME : float = 2.0
const SLAM_SPEED : float = 900.0
const SKILL_TOP_MARGIN : float = 48.0
#技能释放粒子与精灵可视上沿之间的间距
const RING_GAP : float = 20.0

#受击退避：1 秒内被玩家连砍两刀 → 播放 hurt 动画并带残影向后急退，拉开与玩家的距离
const HURT_COMBO_WINDOW_MSEC : int = 1000
const HURT_RETREAT_SPEED : float = 320.0
const HURT_RETREAT_TIME : float = 0.3

#二/三阶段专属技能：贴近玩家完成该次数的普通攻击后触发（hurt 后撤 → attack_2 水平投掷 pb 投射物）
const PB_ATTACK_COUNT : int = 2
const PB_SPEED : float = 300.0

#交互唤醒起身后的登场演出：无敌时长（同时也作为震屏时长），期间不输出贴身碰撞伤害
const AWAKEN_INVULNERABLE_TIME : float = 2.0
#登场震屏强度（PlayerCamera 的 max_shake_offset 为 15，取 6 为一次明显但不晃晕的震屏）
const AWAKEN_SHAKE_STRENGTH : float = 6.0

#玩家原点在脚下，躯干中心约在原点上方该高度（与玩家 DamageArea 的 CapsuleShape2D 偏移一致）
const PLAYER_BODY_CENTER : Vector2 = Vector2( 0.0 , -26.0 )

#阶段过场时长（按阶段索引：0 占位 / 2 阶段 / 3 阶段）
const TRANSITION_TIME : Array[ float ] = [ 0.0 , 1.1 , 1.3 , 1.5 ]

#阶段推进时背景整体加深：按原色整体压暗关卡背景美术，二阶段轻微加深、三阶段在其基础上再加深
const BACKGROUND_DARKEN_PHASE2 : float = 0.2
const BACKGROUND_DARKEN_PHASE3 : float = 0.5
#要压暗的背景美术容器名：各关卡都是「视差背景 BGParallaxLayers + 地块层 TileMap」这两块。
#只压暗视差背景会出现「天空变暗、洞窟岩壁纹丝不动」——岩壁瓦片铺满画面时会把视差背景整片盖住
#（07 的竞技场就是被岩壁瓦片整片铺满），所以地块层必须一起压暗才看得出整体变暗
const BACKGROUND_DARKEN_NODES : Array[ String ] = [ "BGParallaxLayers" , "TileMap" ]
#加深过渡时长
const BACKGROUND_DARKEN_TIME : float = 0.6
#endregion

var sprite : Sprite2D
var sprite_weapon : Sprite2D
var animation_player : AnimationPlayer
var attack_area : AttackArea
#贴身碰撞伤害判定（HazardArea 是 AttackArea 的子类，需单独捕获，否则会被 attack_area 抢先命中）
var hazard_area : HazardArea
var damage_area : DamageArea

var state_machine : BossStateMachine
var decision_engine : BossDecisionEngine
var blackboard : BossBlackboard

var _facing : int = 1
var _hurt_tween : Tween
#蓄力时的明暗循环补间
var _charge_tween : Tween
#技能蓄力音效需要持续到下落阶段：autoload Audio 走的是「即用即走」的对象池播放器，无法中途停止，
#因此持续型音效由 BOSS 自己持有的独立播放器承载
var hold_audio_player : AudioStreamPlayer2D
#阶段推进时要压暗的背景美术容器（按 BACKGROUND_DARKEN_NODES 依次收集：视差背景 + 地块层）
var background_art : Array[ Node2D ] = []
#各容器本来的 modulate，用于 BOSS 被击败后按原样恢复
var background_art_base : Array[ Color ] = []
#回退方案：关卡没有任何背景美术容器时（背景就是清屏色），用画在世界之下的全屏暗色层压暗清屏色
var background_overlay : ColorRect
#休眠：等待玩家进入检测范围并按交互键唤醒（休眠期保持 RESET 默认姿态与场景里配好的暗色外观）
var waking : bool = false
var player_in_range : bool = false

#技能冷却状态广播给 HUD（仅在可见变化时发射）
var _skill_emit_q : int = -1
var _skill_emit_ready : bool = false
var _skill_emit_unlocked : bool = false


func _ready() -> void:
	#编辑器里不跑运行时初始化（与小怪 Enemy 一致），朝向预览交给 face_left_on_start 的 setter
	if Engine.is_editor_hint():
		set_physics_process( false )
		return
	setup()
	pass


func setup() -> void:
	blackboard = BossBlackboard.new()
	blackboard.max_hp = MAX_HP
	blackboard.hp = MAX_HP
	#玩家死亡广播：BOSS 立即冻结（与敌人一致）
	Messages.player_died.connect( _on_player_died )

	for c in get_children():
		if c is AnimationPlayer and not animation_player:
			animation_player = c
		elif c is Sprite2D and not sprite:
			sprite = c
		elif c is DamageArea and not damage_area:
			damage_area = c
			c.damage_taken.connect( _on_damage_taken )
		elif c is HazardArea and not hazard_area:
			hazard_area = c
		elif c is AttackArea and not attack_area:
			attack_area = c
		elif c is BossStateMachine and not state_machine:
			state_machine = c
		elif c is BossDecisionEngine and not decision_engine:
			decision_engine = c
		pass

	#武器精灵是主精灵的子节点，单独取
	if sprite:
		sprite_weapon = sprite.get_node_or_null( "Sprite2D" ) as Sprite2D

	#开局朝向：与关卡里摆放小怪一致，勾选 face_left_on_start 时出生即面朝左（含精灵镜像与攻击判定区翻转）
	_facing = -1 if face_left_on_start else 1
	apply_facing()
	setup_phase_background()

	if state_machine and decision_engine and damage_area:
		state_machine.setup( self , blackboard )
		decision_engine.boss = self
		decision_engine.blackboard = blackboard
		#休眠开局：定格 RESET 默认姿态（上面 setup 已进入待机并播放 idle），
		#同时暂时不可被攻击、不输出贴身伤害，等玩家按交互键唤醒
		play_animation( "RESET" )
		set_damage_invulnerable( true )
		set_contact_damage( false )
	else:
		set_physics_process( false )
	pass


func _physics_process( delta : float ) -> void:
	if blackboard.dead:
		return

	#休眠：定格 RESET 默认姿态。玩家进入交互范围（与 BOSS 的 DamageArea 判定框一致）时提示交互，
	#按下交互键才由 _on_player_interact 唤醒并开战；休眠期不锁定、不出手、不广播冷却
	if not blackboard.combat_started:
		if not waking:
			update_dormant_interaction()
		#仍跑待机的物理（重力/刹停），但不重播动画，保持 RESET 姿态定格
		state_machine.physics_update( delta )
		return

	#二阶段专属技能：贴近玩家打满两次普通攻击后触发
	update_pb_skill_readiness()

	state_machine.physics_update( delta )

	#组合技冷却状态同步给 HUD
	sync_skill_cooldown()
	pass


#region /// 基础工具（供各状态脚本调用）

func has_target() -> bool:
	return is_instance_valid( blackboard.target ) and not blackboard.target.is_queued_for_deletion()


#交互范围：与 BOSS 自身的 DamageArea 判定框完全一致（同一个矩形，取其 CollisionShape2D 的
#全局中心与 RectangleShape2D 的半长；在编辑器里改它的大小，交互范围即同步变化）。
#判定玩家躯干中心（原点在脚下的玩家，躯干中心在原点上方 PLAYER_BODY_CENTER）是否落在矩形内。
func in_interact_range( candidate : Player ) -> bool:
	if damage_area == null:
		return false
	var shape_node := damage_area.get_node_or_null( "CollisionShape2D" ) as CollisionShape2D
	if shape_node == null:
		return false
	var hurt_shape := shape_node.shape as RectangleShape2D
	if hurt_shape == null:
		return false
	var offset : Vector2 = candidate.global_position + PLAYER_BODY_CENTER - shape_node.global_position
	var half : Vector2 = hurt_shape.size * 0.5
	return absf( offset.x ) <= half.x and absf( offset.y ) <= half.y


func dx_to_target() -> float:
	if not has_target():
		return 0.0
	return blackboard.target.global_position.x - global_position.x


func dir_to_target() -> int:
	return 1 if dx_to_target() >= 0.0 else -1


func face_towards_target() -> void:
	if has_target():
		face( dir_to_target() )


func face( dir : int ) -> void:
	if dir == 0:
		return
	_facing = 1 if dir > 0 else -1
	apply_facing()
	pass


#同步精灵与攻击判定区的朝向（武器残影贴图同步镜像，保证挥击出现在面朝一侧）
func apply_facing() -> void:
	var left : bool = _facing < 0
	sprite.flip_h = left
	sprite_weapon.flip_h = left
	sprite_weapon.position.x = -26.666 if left else 26.666
	attack_area.flip( _facing )
	pass


#编辑器里勾选 face_left_on_start 时立刻翻转预览（与小怪 Enemy._update_face_left 同一套写法）
func _update_face_left() -> void:
	if not Engine.is_editor_hint():
		return
	for c in get_children():
		if c is Sprite2D:
			c.flip_h = face_left_on_start
	pass


func apply_gravity( delta : float ) -> void:
	velocity.y = minf( velocity.y + GRAVITY * delta , MAX_FALL_SPEED )
	pass


func skill_ready() -> bool:
	return Time.get_ticks_msec() >= blackboard.skill_next_use_msec


#普通攻击是否已过内置冷却
func attack_ready() -> bool:
	return Time.get_ticks_msec() >= blackboard.attack_next_use_msec


#记录一次普通攻击
func start_attack_cooldown() -> void:
	blackboard.attack_next_use_msec = Time.get_ticks_msec() + ATTACK_COOLDOWN_MSEC
	pass


#记录一次追击动作（jump / dash），两者共用 5 秒内置冷却
func start_chase_cooldown() -> void:
	blackboard.chase_next_use_msec = Time.get_ticks_msec() + CHASE_COOLDOWN_MSEC
	pass


func chase_ready() -> bool:
	return Time.get_ticks_msec() >= blackboard.chase_next_use_msec


func leap_duration() -> float:
	return maxf( anim_length( "skill_01" ) , 0.3 )


#屏幕正上方中心点的世界坐标：以当前相机可视区中心为基准上移半屏
func screen_top_center() -> Vector2:
	var center : Vector2 = global_position
	var view : Vector2 = get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam:
		center = cam.global_position + cam.offset
	elif has_target():
		center = blackboard.target.global_position
	return Vector2( center.x , center.y - view.y * 0.5 + SKILL_TOP_MARGIN )


func phase_display_name() -> String:
	match blackboard.phase:
		2:
			return "第 二 阶 段"
		3:
			return "第 三 阶 段 "
	return "第 一 阶 段"


func anim_length( anim_name : String ) -> float:
	var a := animation_player.get_animation( anim_name )
	return a.length if a else 0.0


func play_animation( anim_name : String ) -> void:
	#武器残影（Sprite 的子节点 Sprite2D）只有 attack / attack_2 动画带显隐轨道，
	#其余动画不会碰它；若不先隐藏，攻击中途被打断（如受击退避 hurt）时它会停在上一次的可见状态而残留
	if sprite_weapon:
		sprite_weapon.visible = false
	if animation_player.has_animation( anim_name ):
		animation_player.play( anim_name )
	pass


func set_damage_invulnerable( on : bool ) -> void:
	if is_instance_valid( damage_area ):
		#判定区在信号派发期间处于锁定状态，必须延迟设置
		damage_area.set_deferred( "process_mode" , Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT )
	pass


#阶段过场期间关闭贴身碰撞伤害（HazardArea），过场结束后恢复。
#判定区在信号派发期间处于锁定状态，必须延迟设置。
func set_contact_damage( on : bool ) -> void:
	if is_instance_valid( hazard_area ):
		hazard_area.set_deferred( "monitoring" , on )
		hazard_area.set_deferred( "visible" , on )
	pass


#阶段背景加深的准备：收集关卡里的背景美术容器（BACKGROUND_DARKEN_NODES，即视差背景 + 地块层），
#记下它们本来的 modulate 以便 BOSS 被击败后按原样恢复；压暗的是这些容器本身、不碰角色与道具，
#也不受图层次序与相机滚动影响。
#若关卡一个都没有（画面背景就是清屏色，例如独立竞技场里 Background 多边形 visible=false），
#则回退到「画在世界之下的全屏暗色层」去压暗清屏色。
func setup_phase_background() -> void:
	var world := get_parent()
	if world == null:
		return
	for node_name in BACKGROUND_DARKEN_NODES:
		_add_background_art( world.get_node_or_null( node_name ) as Node2D )
	#地块层也可能不套在 TileMap 容器里、直接挂在关卡根下（06 就是这样），一并收进来，
	#否则那些关卡只会压暗视差背景，出现「天空变暗、地面纹丝不动」
	for child in world.get_children():
		if child is TileMapLayer:
			_add_background_art( child as Node2D )
	if background_art.is_empty():
		#不给静默失败留余地：找不到任何背景美术容器时明确报警，并走清屏色回退路径
		push_warning( "Boss：关卡里找不到任何背景美术容器 %s，阶段加深将只能压暗清屏色" % str( BACKGROUND_DARKEN_NODES ) )
		create_background_overlay()
	pass


#登记一个要随阶段压暗的背景美术节点（记录它本来的 modulate 供恢复），重复登记会被忽略
func _add_background_art( art : Node2D ) -> void:
	if art == null or background_art.has( art ):
		return
	background_art.append( art )
	background_art_base.append( art.modulate )
	pass


#回退方案：创建背景加深层，挂在场地上、只画在最底（CanvasLayer -1 位于整个世界之下），
#压暗的是关卡内容没盖住的清屏色部分；关卡自己有背景美术时这层会被整片盖住、完全看不到，
#所以只在上面找不到背景美术时才用它（竞技场的背景就是清屏色，这条路径在那里有效）
func create_background_overlay() -> void:
	var world := get_parent()
	if world == null:
		return
	var layer := CanvasLayer.new()
	#世界（Node2D）绘制在图层 0；这里用 -1 保证排在最底
	layer.layer = -1
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color( 0.0 , 0.0 , 0.0 , 0.0 )
	layer.add_child( rect )
	background_overlay = rect
	#BOSS 的 _ready() 正处于父节点（场地）实例化子节点的过程中，此刻父节点被锁定，
	#add_child 会被拒绝（Parent node is busy setting up children），必须延后挂载；
	#入树后再按视口铺满（CanvasLayer 的空间即屏幕）
	world.add_child.call_deferred( layer )
	rect.set_anchors_and_offsets_preset.call_deferred( Control.PRESET_FULL_RECT )
	pass


#阶段推进时调用：二阶段轻微加深背景、三阶段在二阶段基础上再加深；传入 1（BOSS 被击败）时补回原样。
#补间一律挂在被改动的节点上创建 —— BOSS 被击败后自身会被释放，绑在 BOSS 上的补间会中途夭折、颜色卡在半路
func apply_phase_background( phase : int ) -> void:
	var a : float = 0.0
	if phase >= 3:
		a = BACKGROUND_DARKEN_PHASE3
	elif phase >= 2:
		a = BACKGROUND_DARKEN_PHASE2
	#按各容器原本的颜色整体乘 k：传入 1 时 k = 1 即原样（打完 BOSS 恢复）
	var k : float = 1.0 - a
	for i in background_art.size():
		var art := background_art[ i ]
		if not is_instance_valid( art ):
			continue
		var base := background_art_base[ i ]
		var target := Color( base.r * k , base.g * k , base.b * k , base.a )
		art.create_tween().tween_property( art , "modulate" , target , BACKGROUND_DARKEN_TIME )
	if not background_art.is_empty():
		#诊断输出：确认本阶段加深确实执行、执行到哪几个容器（排查「看不出变化」时据此定位，确认无误后可删）
		print( "[Boss] 阶段背景加深：phase=%d a=%.2f 容器=%d" % [ phase , a , background_art.size() ] )
		return
	if background_overlay != null:
		var overlay_tween := background_overlay.create_tween()
		overlay_tween.tween_property( background_overlay , "color:a" , a , BACKGROUND_DARKEN_TIME )
	pass


#切断 BOSS 的全部伤害来源：普攻判定区（AttackArea）+ 贴身碰撞判定（HazardArea）。
#死亡回调由受击信号派发，此刻 Area2D 的 monitoring 处于锁定状态（引擎拒绝修改），
#直接赋值会被丢弃导致攻击判定区在剩余 0.2 秒激活窗口内继续命中玩家，必须 set_deferred。
func stop_damage_output() -> void:
	for a in [ attack_area , hazard_area ]:
		var area := a as Area2D
		if is_instance_valid( area ):
			area.set_deferred( "monitoring" , false )
			area.set_deferred( "visible" , false )
	pass


#播放需要一直持续到指定阶段才停止的音效（如技能蓄力：0.8 秒素材 < 2 秒蓄力时长，靠 replay_hold_audio 重播填满）
#注意：stream 必须直接传资源本体，不能传 duplicate() 的副本 ——
#导入的 wav 采样数据存放在 .godot/imported/*.sample，副本没有资源路径会取不到数据，播放静音
func play_hold_audio( stream : AudioStream ) -> void:
	if hold_audio_player == null:
		hold_audio_player = AudioStreamPlayer2D.new()
		hold_audio_player.bus = "SFX"
		add_child( hold_audio_player )
	hold_audio_player.stream = stream
	hold_audio_player.play()
	pass


#从头重播当前持续音效（素材比状态时长短时用来填满）
func replay_hold_audio() -> void:
	if hold_audio_player:
		hold_audio_player.play()
	pass


func stop_hold_audio() -> void:
	if hold_audio_player and hold_audio_player.playing:
		hold_audio_player.stop()
	pass


#BOSS 精灵可视上沿上方一点的世界坐标（技能释放粒子用）
func ring_position() -> Vector2:
	return global_position + Vector2( 0.0 , _ring_offset_y() )


#精灵可视上沿之上再上抬 RING_GAP：帧高 = 贴图高 / 垂直帧数，再乘精灵缩放
func _ring_offset_y() -> float:
	var tex : Texture2D = sprite.texture
	if tex == null:
		return -140.0
	var frame_h : float = float( tex.get_height() ) / float( maxi( sprite.vframes , 1 ) )
	var top : float = sprite.position.y - sprite.scale.y * frame_h * 0.5
	return top - RING_GAP

#endregion


#region /// 休眠 / 交互唤醒

#休眠期每帧检测：玩家进入/离开交互范围（与 BOSS 的 DamageArea 判定框一致）时切换交互提示。
#与开关、存档点的写法一致：进入范围时提示按键图标并监听交互广播，离开时收回提示并断连
func update_dormant_interaction() -> void:
	var player : Player = get_tree().get_first_node_in_group( "Player" ) as Player
	var in_range : bool = player != null and in_interact_range( player )
	if in_range == player_in_range:
		return
	player_in_range = in_range
	if in_range:
		Messages.input_hint_changed.emit( "interact" )
		if not Messages.player_interacted.is_connected( _on_player_interact ):
			Messages.player_interacted.connect( _on_player_interact )
	else:
		Messages.input_hint_changed.emit( "" )
		if Messages.player_interacted.is_connected( _on_player_interact ):
			Messages.player_interacted.disconnect( _on_player_interact )
	pass


#玩家在检测范围内按下交互键：外观恢复正常（休眠期是场景里配好的暗色）→
#播放 start 苏醒动画 → 起身后 2 秒登场演出（无敌 + 关闭碰撞伤害 + 震屏）→ 亮血条正式开战
func _on_player_interact( player : Player ) -> void:
	if blackboard.combat_started or waking:
		return
	waking = true
	player_in_range = false
	if Messages.player_interacted.is_connected( _on_player_interact ):
		Messages.player_interacted.disconnect( _on_player_interact )
	Messages.input_hint_changed.emit( "" )
	sprite.modulate = Color.WHITE
	play_animation( "start" )
	#苏醒：入场音乐等据此开始播放（休眠期不放）
	Messages.boss_awakened.emit()
	await animation_player.animation_finished
	if blackboard.dead:
		waking = false
		return
	#起身后的登场演出：2 秒无敌、关闭贴身碰撞伤害，同时震屏；期间血条不出现、玩家打不到它
	set_damage_invulnerable( true )
	set_contact_damage( false )
	VisualEffects.camera_shake( AWAKEN_SHAKE_STRENGTH , AWAKEN_INVULNERABLE_TIME )
	await get_tree().create_timer( AWAKEN_INVULNERABLE_TIME ).timeout
	waking = false
	if blackboard.dead:
		return
	set_damage_invulnerable( false )
	set_contact_damage( true )
	blackboard.target = player
	begin_combat()
	pass

#endregion


#region /// 战斗开始 / 受击与阶段推进

func begin_combat() -> void:
	blackboard.combat_started = true
	BossHud.show_bar( BOSS_NAME , blackboard.max_hp )
	Messages.boss_health_changed.emit( blackboard.hp , blackboard.max_hp )
	state_machine.change_state( decision_engine.bs_decide )
	pass


#普通攻击每次实际出手时由 bs_attack 调用：计入二/三阶段专属技能的触发计数。
#二/三阶段的攻击才计数（一阶段不计数）；死亡、阶段过场（无敌）与技能进行中一律清零。
#冲刺连招收尾的那记普攻算在冲刺里，bs_attack 会跳过本次调用（见 blackboard.skip_next_attack_count）。
func notify_attack_performed() -> void:
	if blackboard.dead or blackboard.invulnerable or blackboard.phase < 2 or blackboard.pb_skill_locked:
		blackboard.pb_attack_count = 0
		return
	blackboard.pb_attack_count += 1
	pass


#二/三阶段专属技能的就绪判定：贴近玩家打满 PB_ATTACK_COUNT 次普通攻击 → 触发。
#在帧末统一判定，避免在 bs_attack.enter() 内部嵌套切换状态。
func update_pb_skill_readiness() -> void:
	if blackboard.dead or blackboard.invulnerable or blackboard.phase < 2 or blackboard.pb_skill_locked:
		return
	if blackboard.pb_attack_count < PB_ATTACK_COUNT:
		return

	blackboard.pb_attack_count = 0
	#状态锁：技能流程期间不再重复触发，技能结束时由 bs_pb_skill.exit() 解锁
	blackboard.pb_skill_locked = true
	state_machine.change_state( decision_engine.bs_pb_skill )
	pass


func _on_damage_taken( a : AttackArea ) -> void:
	#阶段过场（下蹲无敌）与死亡期间免疫伤害
	if blackboard.dead or blackboard.invulnerable:
		return

	blackboard.hp = maxf( blackboard.hp - a.damege , 0.0 )
	Messages.boss_health_changed.emit( blackboard.hp , blackboard.max_hp )
	Messages.enemy_damaged.emit( global_position , a.damege )
	VisualEffects.spawn_damage_number( global_position + Vector2( 0 , -118 ) , a.damege , true )
	flash_hurt()

	#记录受击连锁：距离上一刀在 1 秒内则累加，否则重新从 1 开始
	var now : int = Time.get_ticks_msec()
	if now - blackboard.last_hit_msec <= HURT_COMBO_WINDOW_MSEC:
		blackboard.hit_chain += 1
	else:
		blackboard.hit_chain = 1
	blackboard.last_hit_msec = now

	if blackboard.hp <= 0.0:
		state_machine.change_state( decision_engine.bs_death )
		return

	#每损失 8 点生命推进一个阶段
	var new_phase : int = clampi( int( ( blackboard.max_hp - blackboard.hp ) / PHASE_HP_STEP ) + 1 , 1 , MAX_PHASE )
	if new_phase > blackboard.phase:
		blackboard.phase = new_phase
		state_machine.change_state( decision_engine.bs_transition )
		return

	#1 秒内被连砍两刀 → 受击退避：hurt 动画 + 带残影后撤
	if blackboard.hit_chain >= 2:
		blackboard.hit_chain = 0
		state_machine.change_state( decision_engine.bs_hurt )
	pass


func flash_hurt() -> void:
	if _hurt_tween:
		_hurt_tween.kill()
	sprite.modulate = Color( 2.0 , 1.1 , 1.2 , 1.0 )
	_hurt_tween = create_tween()
	_hurt_tween.tween_property( sprite , "modulate" , Color.WHITE , 0.12 )
	pass


#死亡时清掉受击闪白补间，避免与死亡淡出争用 sprite.modulate
func clear_hurt_tween() -> void:
	if _hurt_tween:
		_hurt_tween.kill()
		_hurt_tween = null
	pass


#进入蓄力：自身颜色在明暗之间循环渐变，直观表示蓄力中（二/三阶段蓄力共用）
#用 self_modulate 只改本体颜色，与受击闪白、死亡淡出所用的 modulate 互不干扰
func start_charge_flash() -> void:
	stop_charge_flash()
	_charge_tween = create_tween()
	_charge_tween.set_loops()
	_charge_tween.set_trans( Tween.TRANS_SINE )
	_charge_tween.tween_property( sprite , "self_modulate" , CHARGE_DARK_COLOR , CHARGE_FLASH_TIME )
	_charge_tween.tween_property( sprite , "self_modulate" , CHARGE_LIGHT_COLOR , CHARGE_FLASH_TIME )
	pass


#结束蓄力：停掉循环补间并把颜色复位
func stop_charge_flash() -> void:
	if _charge_tween:
		_charge_tween.kill()
		_charge_tween = null
	sprite.self_modulate = CHARGE_LIGHT_COLOR
	pass

#endregion


#region /// 特效生成（供状态脚本调用）

#残影：与玩家下落攻击一致——同色半透明复制体在 0.2 秒内淡出
func spawn_afterimage() -> void:
	var world := get_parent()
	if world == null:
		return
	var ghost := Node2D.new()
	#插在 BOSS 前一位并沿用 BOSS 自己的 z_index：残影稳定画在 BOSS 身后、背景/地面之前
	#（BOSS 的 z_index 会被关卡实例覆盖，这里若写死层号，残影反而会盖到 BOSS 身上）
	var idx : int = get_index()
	world.add_child( ghost )
	world.move_child( ghost , idx )
	ghost.z_index = z_index
	ghost.global_transform = global_transform
	ghost.modulate = Color( 0.958 , 0.595 , 0.595 , 0.75 )

	var copy : Sprite2D = sprite.duplicate() as Sprite2D
	copy.flip_h = sprite.flip_h
	ghost.add_child( copy )

	var tw := ghost.create_tween()
	tw.set_ease( Tween.EASE_OUT )
	tw.tween_property( ghost , "modulate" , Color( 0.0 , 0.0 , 0.0 , 0.0 ) , 0.2 )
	tw.chain().tween_callback( ghost.queue_free )
	pass


func spawn_ground_slam() -> void:
	var fx := GROUND_SLAM_SCENE.instantiate() as Node2D
	add_world_child( fx )
	fx.global_position = global_position + Vector2( 0 , 4 )
	aim_hazard_at_player( fx )
	play_child_animation( fx )
	free_later( fx , 0.9 )
	pass


func spawn_wave( dir : int ) -> void:
	var fx := WAVE_SCENE.instantiate() as Node2D
	add_world_child( fx )
	#光波场景的精灵与判定以「根节点 y 即地面线」为锚点设计（帧高 128，精灵 y 偏移 -64 使底边正好落在根节点上），
	#砸地时 BOSS 原点就在地面线，故这里不再额外抬高，否则整体浮空
	fx.global_position = global_position + Vector2( float( dir ) * 50.0 , 0.0 )
	#镜像整节点使光波朝向该侧（含判定形状一起镜像），波体据 scale.x 决定推进方向
	fx.scale.x = float( dir )
	aim_hazard_at_player( fx )
	play_child_animation( fx )
	#波体自身（npbh_enemy_wave.gd）持续向该侧推进，撞到墙壁后淡出销毁
	pass


#二/三阶段专属技能：沿面朝方向水平发射 pb 投射物（从身体中心射出，不追踪玩家）
func spawn_pb() -> void:
	var proj := PB_SCENE.instantiate() as PbProjectile
	add_world_child( proj )
	#与身体中心对齐（玩家站姿躯干也在这个高度），保证水平飞行能够命中
	proj.global_position = global_position + Vector2( 0.0 , -45.0 )
	#始终按当前面朝方向水平飞行，发射后不再改变方向
	var dir : Vector2 = Vector2( float( _facing ) , 0.0 )
	proj.setup( dir , PB_SPEED )
	#发射的同时播放投射物自带的 default 动画
	play_child_animation( proj )
	#判定只保留玩家层（16）；墙壁由投射物自身的射线检测
	aim_hazard_at_player( proj )
	pass


#死亡掉落：在尸体所在的地面上方留下一颗冲刺能力球，玩家击碎它即可获得冲刺
func spawn_dash_pickup() -> void:
	var pickup := DASH_PICKUP_SCENE.instantiate() as AbilityPickup
	#先定类型再入树：入树时 _ready() 会按类型播放对应的图标动画
	pickup.type = AbilityPickup.Type.DASH
	add_world_child( pickup )
	#向下探到最近的地面，把能力球摆在地面上方，空中死亡时也不会悬在半空
	var from : Vector2 = global_position + Vector2( 0.0 , -1.0 )
	var to : Vector2 = global_position + Vector2( 0.0 , 900.0 )
	var query := PhysicsRayQueryParameters2D.create( from , to , 1 )
	var hit : Dictionary = get_world_2d().direct_space_state.intersect_ray( query )
	var ground_y : float = float( hit.position.y ) if not hit.is_empty() else global_position.y
	pickup.global_position = Vector2( global_position.x , ground_y - PICKUP_GROUND_OFFSET )
	#刚出现的瞬间无敌：击破 BOSS 的那一下攻击（判定可能仍与落点重叠）不会立刻把球打碎，
	#复用玩家受击无敌的同一套机制（DamageArea 禁用 process_mode）
	var pickup_damage_area := pickup.get_node_or_null( "Breakable/DamageArea" ) as DamageArea
	if pickup_damage_area:
		pickup_damage_area.make_invulnerable( PICKUP_INVULNERABLE_TIME )
	pass


#落地砸击：地面砸击特效 + 左右光波 + 吹尘 + 强震屏
func slam_impact() -> void:
	Audio.play_spatial_sound( GROUND_SLAM_AUDIO , global_position )
	spawn_ground_slam()
	spawn_wave( -1 )
	spawn_wave( 1 )
	VisualEffects.hit_dust( global_position )
	#尖刺爆发特效：单帧 128x128、Sprite2D 默认以帧中心为原点，抬高半个帧高（64 × 1.7 = 108.8）后
	#特效最下面正好落在 BOSS 脚底（BOSS 原点即脚底、砸地瞬间就在这里触发），不再埋进地面。
	#末位传 self：特效跟随 BOSS 的 z_index、插在 BOSS 前一位，不论关卡实例把 BOSS 调成几层都不会挡在它前面
	VisualEffects.play_effect_row( 0 , global_position + Vector2( 0 , -108.8 ) , 1.7 , false , 16.0 , self )
	VisualEffects.camera_shake( 14.0 , 0.5 )
	pass


#特效根节点挂在 BOSS 的父节点上，避免随 BOSS 移动/旋转
func add_world_child( node : Node2D ) -> void:
	var world := get_parent()
	if world:
		world.add_child( node )
	else:
		add_child( node )
	pass


#光波/砸击自带的 HazardArea 默认只命中 Ground 层，这里改为命中 Player 层
func aim_hazard_at_player( node : Node2D ) -> void:
	var hazard := node.get_node_or_null( "HazardArea" ) as Area2D
	if hazard:
		hazard.collision_mask = 16
	pass


func play_child_animation( node : Node2D ) -> void:
	var ap := node.get_node_or_null( "AnimationPlayer" ) as AnimationPlayer
	if ap and ap.has_animation( "default" ):
		ap.play( "default" )
	pass


func free_later( node : Node , delay : float ) -> void:
	await get_tree().create_timer( delay ).timeout
	if is_instance_valid( node ):
		node.queue_free()
	pass

#endregion


#region /// 技能冷却状态广播

#把组合技冷却状态广播给 HUD；仅在可见状态变化时发射，避免每帧刷信号
func sync_skill_cooldown() -> void:
	var unlocked : bool = blackboard.phase >= 3
	var skill_is_ready : bool = unlocked and skill_ready()
	var ratio : float = 1.0 if skill_is_ready else 0.0
	if unlocked and not skill_is_ready:
		var left : int = blackboard.skill_next_use_msec - Time.get_ticks_msec()
		ratio = 1.0 - clampf( float( left ) / float( SKILL_COOLDOWN_MSEC ) , 0.0 , 1.0 )

	var q : int = int( round( ratio * 100.0 ) )
	if q == _skill_emit_q and skill_is_ready == _skill_emit_ready and unlocked == _skill_emit_unlocked:
		return
	_skill_emit_q = q
	_skill_emit_ready = skill_is_ready
	_skill_emit_unlocked = unlocked

	Messages.boss_skill_cooldown.emit( ratio , skill_is_ready , unlocked )
	pass

#endregion


func _on_player_died() -> void:
	if blackboard.dead:
		return
	set_physics_process( false )
	animation_player.pause()
	stop_damage_output()
	set_damage_invulnerable( true )
	pass
