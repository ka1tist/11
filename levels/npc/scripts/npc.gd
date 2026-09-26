class_name NPC
extends CharacterBody2D


#NPC 状态：IDLE 静止 / WALKING 移动 / TALKING 对话中（移动冻结，由子类管理）
#对话状态优先级最高：TALKING 时水平速度为 0，跳过移动 AI 决策
enum State { IDLE , WALKING , TALKING }

#移动速度（像素/秒），在 Inspector 中按实例调整
@export var move_speed : float = 40.0
#重力加速度（像素/秒²），与玩家保持一致；设为 0 可关闭重力（用于飞行 / 固定站位 NPC）
@export var gravity : float = 980.0
#最大下落速度，防止长时间坠落时速度无限增长
@export var max_fall_velocity : float = 1000.0
#随机静止/移动的持续时间范围（秒），AI 在两者间随机切换
@export var idle_duration_min : float = 1.5
@export var idle_duration_max : float = 3.5
@export var walk_duration_min : float = 2.0
@export var walk_duration_max : float = 4.0

var sprite : Sprite2D
var animation : AnimationPlayer

var _state : State = State.IDLE
var _left_limit : float
var _right_limit : float
var _move_dir : float = 1.0
var _timer : float = 0.0
var _state_duration : float = 0.0


func _ready() -> void:
	_collect_children()
	_set_limits()
	_start_idle()
	pass


#每帧只做 AI 状态计时；实际位移统一在 _physics_process 通过 velocity + move_and_slide 完成
func _process( delta : float ) -> void:
	#对话状态优先：冻结一切移动逻辑，保持当前姿势不动
	if _state == State.TALKING:
		return
	match _state:
		State.IDLE:
			_update_idle( delta )
		State.WALKING:
			_update_walking( delta )
	pass


#物理帧：水平速度由 AI 状态驱动，垂直方向施加重力，再交给引擎碰撞解算。
#碰撞掩码 = 物理层 1+2（在场景中配置），因此 NPC 会被 TileSet 地面 / 墙体阻挡，
#自身 collision_layer = 0，不会与玩家或敌人互相推挤
func _physics_process( delta : float ) -> void:
	#NPC 不可见时（如藏在房屋内景中）不进行物理移动：
	#此时室内碰撞层也处于关闭状态，坠落只会让位置无限偏离
	if not visible:
		velocity = Vector2.ZERO
		return
	#水平移动速度
	if _state == State.WALKING:
		velocity.x = _move_dir * move_speed
	else:
		velocity.x = 0.0
	#重力
	if gravity > 0.0:
		velocity.y = minf( velocity.y + gravity * delta , max_fall_velocity )
	else:
		velocity.y = 0.0
	move_and_slide()
	#到达巡逻边界：钳制位置并反向，同步翻转朝向
	if _state == State.WALKING:
		if global_position.x <= _left_limit:
			global_position.x = _left_limit
			_reverse_dir( 1.0 )
		elif global_position.x >= _right_limit:
			global_position.x = _right_limit
			_reverse_dir( -1.0 )
	pass


#翻转移动方向并同步精灵朝向
func _reverse_dir( new_dir : float ) -> void:
	if _move_dir == new_dir:
		return
	_move_dir = new_dir
	_flip_sprite( _move_dir )
	pass


#遍历子节点收集根精灵与动画播放器（与 enemy.gd 的 setup 收集方式一致）
func _collect_children() -> void:
	for c in get_children():
		if c is Sprite2D and not sprite:
			sprite = c
		elif c is AnimationPlayer and not animation:
			animation = c
	pass


#从子树查找 PatrolLimit 节点确定移动边界（与 es_walk.gd 一致），
#未设置时回退到出生点 ±5000 的宽范围，边界异常时自动左右对调
func _set_limits() -> void:
	_left_limit = global_position.x - 5000.0
	_right_limit = global_position.x + 5000.0
	#PatrolLimit 在场景中挂在 NPC 根节点下，必须递归查找
	for c in find_children( "*" , "PatrolLimit" , true , false ):
		if c.side == Side.SIDE_LEFT:
			_left_limit = c.global_position.x
		elif c.side == Side.SIDE_RIGHT:
			_right_limit = c.global_position.x
	if _left_limit > _right_limit:
		var t : float = _left_limit
		_left_limit = _right_limit
		_right_limit = t
	pass


func _update_idle( delta : float ) -> void:
	_timer += delta
	if _timer >= _state_duration:
		_start_walking()
	pass


func _update_walking( delta : float ) -> void:
	_timer += delta
	#位移由 _physics_process 中的 velocity / move_and_slide 负责，这里只做状态计时
	if _timer >= _state_duration:
		_start_idle()
	pass


#进入静止状态：播放 idle 动画，随机设定本次静止时长
func _start_idle() -> void:
	_state = State.IDLE
	_timer = 0.0
	_state_duration = randf_range( idle_duration_min , idle_duration_max )
	_play_animation( "idle" )
	pass


#进入移动状态：播放 walk 动画，随机选取方向与本次移动时长
func _start_walking() -> void:
	_state = State.WALKING
	_timer = 0.0
	_state_duration = randf_range( walk_duration_min , walk_duration_max )
	_move_dir = 1.0 if randf() < 0.5 else -1.0
	_flip_sprite( _move_dir )
	_play_animation( "walk" )
	pass


#翻转朝向：通过根 Sprite2D 的 scale.x 符号控制，
#连带所有子精灵（clothes/skirt/hair）一起镜像，保证整体一致
func _flip_sprite( dir : float ) -> void:
	if sprite == null or dir == 0.0:
		return
	var abs_scale : float = absf( sprite.scale.x )
	sprite.scale.x = -abs_scale if dir > 0.0 else abs_scale
	pass


func _play_animation( anim_name : String ) -> void:
	if animation and animation.has_animation( anim_name ):
		animation.play( anim_name )
	pass


#进入对话状态：停止移动、播放 idle、冻结 AI 决策（由子类调用）
func start_talking() -> void:
	_state = State.TALKING
	_move_dir = 0.0
	velocity.x = 0.0
	_play_animation( "idle" )
	pass


#结束对话状态：恢复随机移动行为（由子类调用）
func stop_talking() -> void:
	_start_idle()
	pass
