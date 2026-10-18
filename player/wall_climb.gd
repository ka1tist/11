@icon( "res://general/icons/state.svg" )
class_name PlayerStateWallClimb extends PlayerState

@onready var sprite_2d: Sprite2D = $"../../Sprite2D"
@onready var sprite_2d_2: Sprite2D = $"../../Sprite2D2"
@onready var sprite_2d_3: Sprite2D = $"../../Sprite2D3"
@onready var sprite_2d_4: Sprite2D = $"../../Sprite2D4"
@onready var sprite_2d_5: Sprite2D = $"../../Sprite2D5"

#贴墙停顿时间（秒）：上墙后停在墙面停顿，播放climb_stay，之后开始下滑
@export var stay_time : float = 0
#下滑速度（像素/秒）：停顿结束后匀速下滑，播放climb
@export var slide_speed : float = 60.0

#墙所在的世界方向：+1 墙在右侧，-1 墙在左侧
var wall_dir : int = 1
var stay_timer : float = 0.0
var sliding : bool = false

#状态初始化时做什么
func init() -> void:
	pass


#当我们进入这个状态时会发生什么
func enter() -> void:
	#触发时玩家正按向墙面，输入方向即墙所在方向
	wall_dir = 1 if player.direction.x > 0 else -1
	sliding = false
	stay_timer = stay_time
	#爬墙动画在Sprite2D5上：隐藏其他所有精灵，只显示Sprite2D5
	sprite_2d.visible = false
	sprite_2d_2.visible = false
	sprite_2d_3.visible = false
	sprite_2d_4.visible = false
	sprite_2d_5.visible = true
	#朝向墙面：wall slide素材默认是手撑画面左墙（贴左墙），经节点变换flip_h=false时贴世界左墙
	#所以贴世界右墙时需镜像；position为玩家局部坐标（根节点scale.x=-1），世界右对应局部负x
	sprite_2d_5.flip_h = wall_dir > 0
	sprite_2d_5.position.x = -2.0 if wall_dir > 0 else 2.0
	player.animation_player.play( "climb_stay" )
	#停顿时不受重力、静止贴在墙上
	player.gravity_mulitplier = 0.0
	player.velocity = Vector2.ZERO
	#重置跳跃计数：蹬墙跳算作一次新跳跃，蹬离后仍可再跳一次。
	#仅已解锁二段跳时才重置：未解锁时不刷新计数，蹬墙跳不会白送一次空中跳跃
	if player.double_jump:
		player.jump_count = 0
	#抓住墙面刷新空中冲刺：蹬墙跳/脱离墙面后可再次冲刺（与落地重置一致）
	player.dash_count = 0
	pass


#当我们退出这个状态会发生什么
func exit() -> void:
	#隐藏爬墙精灵，后续进入的状态会自行恢复各自精灵的显隐
	sprite_2d_5.visible = false
	player.gravity_mulitplier = 1.0
	pass


#按下输入会发生什么
func handle_input( event : InputEvent ) -> PlayerState:
	#蹬墙跳：向远离墙的方向跳出，并启动0.3秒攀爬禁用，期间无法重新附着墙面
	if event.is_action_pressed( "jump" ):
		#蹬墙跳需要二段跳：未解锁时按跳不生效，避免爬墙变成绕过二段跳禁令的第二次空中跳跃；
		#此时仍可按远离墙的方向键脱离墙面，或自然下滑离开
		if not player.double_jump:
			return null
		player.wall_climb_cooldown = player.WALL_CLIMB_JUMP_COOLDOWN
		player.velocity.x = -wall_dir * player.move_speed
		return jump
	return null


#在这个状态下，每个过程tick会发生什么
func process(_delta: float) -> PlayerState:
	#停顿结束后开始下滑，切换climb动画
	if not sliding:
		stay_timer -= _delta
		if stay_timer <= 0.0:
			sliding = true
			player.animation_player.play( "climb" )
	return next_state


#在这个状态下，每个物理过程tick会发生什么
func physics_process(_delta: float) -> PlayerState:
	#下滑落地：回到idle
	if player.is_on_floor():
		return idle
	#按向墙外方向（主动脱离）或墙已到尽头：回到下落状态
	if player.direction.x == -wall_dir or not player.is_wall_on_side( wall_dir ):
		return fall
	#x方向压向墙面保持贴墙；y方向停顿为0、下滑为匀速
	player.velocity.x = wall_dir * player.move_speed
	player.velocity.y = 0.0 if not sliding else slide_speed
	return next_state
