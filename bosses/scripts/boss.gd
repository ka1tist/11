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

#复用已有的 BOSS 专用特效场景（落地砸击 / 左右光波）
const GROUND_SLAM_SCENE : PackedScene = preload( "res://bosses/01/npbh_enemy_ground_slam.tscn" )
const WAVE_SCENE : PackedScene = preload( "res://bosses/01/npbh_enemy_wave.tscn" )

#砸地爆发音效
const GROUND_SLAM_AUDIO = preload( "res://bosses/01/audio/ground slam.wav" )

const BOSS_NAME : String = "NEGA BOX"

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

#三阶段：组合技
const SKILL_COOLDOWN_MSEC : int = 10000
const SKILL_CHARGE_TIME : float = 2.0
const SLAM_SPEED : float = 900.0
const SKILL_TOP_MARGIN : float = 48.0
#技能释放粒子与精灵可视上沿之间的间距
const RING_GAP : float = 20.0

#阶段过场时长（按阶段索引：0 占位 / 2 阶段 / 3 阶段）
const TRANSITION_TIME : Array[ float ] = [ 0.0 , 1.1 , 1.3 , 1.5 ]
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
#技能蓄力音效需要持续到下落阶段：autoload Audio 走的是「即用即走」的对象池播放器，无法中途停止，
#因此持续型音效由 BOSS 自己持有的独立播放器承载
var hold_audio_player : AudioStreamPlayer2D

#技能冷却状态广播给 HUD（仅在可见变化时发射）
var _skill_emit_q : int = -1
var _skill_emit_ready : bool = false
var _skill_emit_unlocked : bool = false


func _ready() -> void:
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

	_facing = 1
	apply_facing()

	if state_machine and decision_engine and damage_area:
		state_machine.setup( self , blackboard )
		decision_engine.boss = self
		decision_engine.blackboard = blackboard
	else:
		set_physics_process( false )
	pass


func _physics_process( delta : float ) -> void:
	if blackboard.dead:
		return

	#全程保持锁定：只在尚未锁定时尝试获取，已锁定则不主动丢弃
	if not has_target():
		blackboard.target = get_tree().get_first_node_in_group( "Player" ) as Player

	#没有锁定玩家时：播放 idle 待机，不做任何攻击行为（不开始战斗、不广播冷却）
	if blackboard.target == null:
		state_machine.change_state( decision_engine.decide() )
		state_machine.physics_update( delta )
		return

	if not blackboard.combat_started:
		begin_combat()

	state_machine.physics_update( delta )

	#组合技冷却状态同步给 HUD
	sync_skill_cooldown()
	pass


#region /// 基础工具（供各状态脚本调用）

func has_target() -> bool:
	return is_instance_valid( blackboard.target ) and not blackboard.target.is_queued_for_deletion()


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
	if animation_player.has_animation( anim_name ):
		animation_player.play( anim_name )
	pass


func set_damage_invulnerable( on : bool ) -> void:
	if is_instance_valid( damage_area ):
		#判定区在信号派发期间处于锁定状态，必须延迟设置
		damage_area.set_deferred( "process_mode" , Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT )
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


#region /// 战斗开始 / 受击与阶段推进

func begin_combat() -> void:
	blackboard.combat_started = true
	BossHud.show_bar( BOSS_NAME , blackboard.max_hp )
	Messages.boss_health_changed.emit( blackboard.hp , blackboard.max_hp )
	state_machine.change_state( decision_engine.bs_decide )
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

	if blackboard.hp <= 0.0:
		state_machine.change_state( decision_engine.bs_death )
		return

	#每损失 8 点生命推进一个阶段
	var new_phase : int = clampi( int( ( blackboard.max_hp - blackboard.hp ) / PHASE_HP_STEP ) + 1 , 1 , MAX_PHASE )
	if new_phase > blackboard.phase:
		blackboard.phase = new_phase
		state_machine.change_state( decision_engine.bs_transition )
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

#endregion


#region /// 特效生成（供状态脚本调用）

#残影：与玩家下落攻击一致——同色半透明复制体在 0.2 秒内淡出
func spawn_afterimage() -> void:
	var world := get_parent()
	if world == null:
		return
	var ghost := Node2D.new()
	world.add_child( ghost )
	world.move_child( ghost , 0 )
	#残影落在世界根节点索引 0，会排在不透明背景（Background）之前被完全盖住，
	#必须显式抬 z_index，与玩家下落攻击残影（player_sprite.gd 的 ghost()）保持一致
	ghost.z_index = 1
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


#落地砸击：地面砸击特效 + 左右光波 + 吹尘 + 强震屏
func slam_impact() -> void:
	Audio.play_spatial_sound( GROUND_SLAM_AUDIO , global_position )
	spawn_ground_slam()
	spawn_wave( -1 )
	spawn_wave( 1 )
	VisualEffects.hit_dust( global_position )
	VisualEffects.play_effect_row( 0 , global_position + Vector2( 0 , -20 ) , 1.7 , false , 16.0 )
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
