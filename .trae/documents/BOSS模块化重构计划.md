# BOSS 代码模块化重构计划（对齐小怪架构）

## 一、背景与目标

`bosses/01/boss_01.gd` 目前是单文件 804 行的"上帝对象"：数值常量、状态枚举、状态机骨架、各状态逐帧逻辑、行为实现、特效生成、冷却广播、受击与阶段推进全部塞在一个类里。

小怪（`enemies/scripts/`）已经把同样的职责拆成了清晰的模块：

- 根节点脚本 `enemy.gd`（收集子节点引用、持有 blackboard / state_machine / decision_engine、统一物理与受击入口）
- `EnemyStateMachine`（注册并驱动子状态节点）
- `EnemyState`（状态基类：`enter / re_enter / exit / physics_update`）
- `DecisionEngine`（决策引擎，持有目标状态引用并返回下一步状态）
- `Blackboard`（共享数据黑板）
- `states/es_*.gd`（每个状态一个脚本 + 场景节点，`unique_name_in_owner`）

**目标**：把 BOSS 改造成与上表**结构相同**的独立模块，**行为与现状 1:1 等价**，且**对小怪代码零改动**。

## 二、现状分析

### 2.1 现有 BOSS 关键结构（`bosses/01/boss_01.gd`）

- `enum State { IDLE, DECIDE, RUN, ATTACK, JUMP, CHARGE, DASH, LEAP, SKILL_CHARGE, SLAM, TRANSITION, DEATH }`
- `_physics_process` 流程：`_dead` 早退 → 保持锁定（`_target` 为空则从 `"Player"` 组取）→ 无目标则强制 IDLE + 内联物理 + return → `_begin_combat()` → `_state_time += delta` → `match _state` 分发 `_tick_*` → `_sync_skill_cooldown()`
- 状态切换 `_change(s)`：同状态早退；`_exit_state(old)` → 置状态 → `_state_time = 0` → `_enter_state(s)`
- `_exit_state`：kill 共享 `_tween`；若退出 TRANSITION 且未死亡则解除无敌
- 每个 `_tick_*` **自行**施加重力与调用 `move_and_slide()`（LEAP / SKILL_CHARGE 例外：位移由 Tween 驱动、完全不调用 `move_and_slide`）
- 决策入口是 **DECIDE 状态**（等待 `DECIDE_DELAY=0.25` 后调用 `_decide()`），其余状态**显式**转移到下一状态
- 受击 `_on_damage_taken` 是阶段推进入口：扣血 → 广播 `boss_health_changed` / `enemy_damaged` → 飘伤害数字 → `_flash_hurt()` → hp≤0 切 DEATH → 按 `PHASE_HP_STEP=8` 计算新阶段，升高则立刻打断当前状态切 TRANSITION
- 对外依赖：`Messages.*` 信号、`BossHud.show_bar()`、`VisualEffects.play_effect_row/camera_shake/hit_dust/spawn_damage_number`、`AttackArea.activate/set_activate/flip`、`DamageArea.damage_taken`

### 2.2 场景接线现状（`bosses/01/boss_01.tscn`）

- 根 `Boss01`（`CharacterBody2D`，`collision_layer=0`、`collision_mask=3`）→ 脚本 `res://bosses/01/boss_01.gd`
- 子节点：`Sprite`(Sprite2D) → `Sprite/Sprite2D`(武器) → `CollisionShape2D` → `AnimationPlayer` → `AttackArea`(layer 0 / mask 16) → `DamageArea`(layer 32 / mask 0)
- 场景 uid：`uid://ctxm262ufe5hl`，被 `boss_arena.tscn` 以该 uid 实例化引用 → **必须保留**
- 没有任何脚本/场景引用 `Boss` 类名或访问 BOSS 的成员变量；唯一耦合是 `boss_hud.gd` 的注释提到文件名 `boss_01.gd`

### 2.3 与小怪架构的差异（重构需处理的保真点）

| 差异点 | 小怪约定 | BOSS 现状 | 处理方式 |
| --- | --- | --- | --- |
| 决策时机 | 决策引擎**每帧**返回下一状态 | DECIDE 状态做枢纽，其余状态显式转移 | 保留"显式转移"，决策引擎只负责**按阶段返回下一步行为**（`decide()`），由 `BSDecide` 调用 |
| 物理 | 根节点统一重力 + `move_and_slide()` | 各状态自行处理（LEAP/SKILL_CHARGE 不移动） | **状态自行处理**，根节点不做统一物理 |
| LEAP 位移 | 无 | 由 Tween 驱动 `global_position` | Tween 由 `BSLeap` 持有，`exit()` 时 kill |
| 阶段推进 | 无 | 受击回调中立即打断状态 | 保留在 `Boss._on_damage_taken` 中直接 `change_state(bs_transition/bs_death)` |
| 锁玩家 | `PlayerSensor` 写 `blackboard.target` | `"Player"` 组查找，已锁定不主动丢弃 | **保留组查找** |

## 三、目标结构

新增模块目录 `bosses/scripts/`（对齐 `enemies/scripts/` 布局，可被后续 BOSS 复用），场景仍留在 `bosses/01/boss_01.tscn`。

```
bosses/
├─ 01/
│  ├─ boss_01.tscn            （修改：新增状态机/决策引擎/12 个状态节点，换根脚本路径）
│  ├─ npbh_enemy_wave.gd/.tscn（不动，仅更新 1 行注释里的来源文件名）
│  ├─ npbh_enemy_ground_slam.tscn（不动）
│  └─ sprites/ audio/         （不动）
└─ scripts/
   ├─ boss.gd                 （新建：Boss 根节点）
   ├─ boss_blackboard.gd      （新建：共享黑板）
   ├─ boss_state.gd           （新建：状态基类）
   ├─ boss_state_machine.gd   （新建：状态机）
   ├─ boss_decision_engine.gd （新建：决策引擎，持有全部状态引用 + 阶段策略）
   └─ states/
      ├─ bs_idle.gd           ├─ bs_decide.gd        ├─ bs_run.gd
      ├─ bs_attack.gd         ├─ bs_jump.gd          ├─ bs_charge.gd
      ├─ bs_dash.gd           ├─ bs_leap.gd          ├─ bs_skill_charge.gd
      ├─ bs_slam.gd           ├─ bs_transition.gd    └─ bs_death.gd
```

删除：`bosses/01/boss_01.gd`、`bosses/01/boss_01.gd.uid`。

## 四、旧 → 新 映射表（保证 1:1）

| 旧（`boss_01.gd`） | 新位置 |
| --- | --- |
| `enum State` + `_state` / `_state_time` | `BossStateMachine.states` + 各状态自带 `timer` |
| `_change` / `_enter_state` / `_exit_state` | `BossStateMachine.change_state` + 各状态 `enter/re_enter/exit` |
| `_physics_process` | `Boss._physics_process`（驱动状态机） |
| `_begin_combat` | `Boss.begin_combat()` |
| `_decide()` | `BossDecisionEngine.decide()` |
| `_tick_idle` / `_enter_state(IDLE)` | `BSIdle` |
| `_tick_decide` / `_enter_state(DECIDE)` | `BSDecide` |
| `_tick_run` / `_enter_state(RUN)` | `BSRun` |
| `_tick_attack` / `_enter_state(ATTACK)` | `BSAttack` |
| `_tick_jump` / `_play_jump` | `BSJump` |
| `_tick_charge` / `_enter_state(CHARGE)` | `BSCharge` |
| `_tick_dash` / `_start_dash` | `BSDash` |
| `_tick_leap` / `_start_leap` | `BSLeap` |
| `_tick_skill_charge` / `_start_skill_charge` | `BSSkillCharge` |
| `_tick_slam` / `_start_slam` / `_slam_impact` | `BSSlam` + `Boss.slam_impact()` |
| `_tick_transition` / `_start_transition` | `BSTransition` |
| `_start_death` / `_death_sequence` | `BSDeath` |
| `_spawn_afterimage` / `_spawn_ground_slam` / `_spawn_wave` | `Boss.spawn_afterimage/spawn_ground_slam/spawn_wave` |
| `_sync_skill_cooldown` | `Boss.sync_skill_cooldown()` |
| `_on_damage_taken` / `_flash_hurt` | `Boss._on_damage_taken` / `Boss.flash_hurt()` |
| `_has_target` / `_dx_to_target` / `_dir_to_target` / `_face_towards_target` / `_face` / `_apply_facing` / `_apply_gravity` | `Boss.has_target/dx_to_target/dir_to_target/face_towards_target/face/apply_facing/apply_gravity` |
| `_skill_ready` / `_start_chase_cooldown` / `_chase_ready` / `_leap_duration` / `_screen_top_center` / `_phase_display_name` / `_anim_length` / `play_anim` | 同名去掉下划线的 `Boss.*` |
| `_ring_position` / `_ring_offset_y` | `Boss.ring_position()` / `Boss._ring_offset_y()` |
| `_set_damage_invulnerable` / `_add_world_child` / `_aim_hazard_at_player` / `_play_child_animation` / `_free_later` / `_on_player_died` | 同名去掉下划线的 `Boss.*`（`_on_player_died` 保留下划线） |

**数值常量全部保留在 `Boss` 上（名称、数值一字不改）**，状态脚本以 `Boss.XXX` 形式引用。唯一例外：`SKILL_CHARGE_TIME` 已是确认过的 `2.0`。

## 五、逐文件改动（完整代码）

### 5.1 新建 `bosses/scripts/boss_blackboard.gd`

```gdscript
class_name BossBlackboard extends Resource

## BOSS 模块共享黑板：状态脚本与决策引擎读写这里的字段，状态之间不直接互相引用。

#玩家目标：由 Boss 根节点在未锁定时从 "Player" 组取，锁定后不主动丢弃
var target : Player = null

#生命与阶段（由 Boss.setup() 初始化）
var max_hp : float = 0.0
var hp : float = 0.0
var phase : int = 1

#生死与无敌：阶段过场（下蹲）与死亡期间 invulnerable 为 true，作为受击回调的第一道拦截
var dead : bool = false
var invulnerable : bool = false

#是否已开始战斗（首次锁定玩家时显示 HUD 血条并进入决策）
var combat_started : bool = false

#追击手段（jump / dash）共用冷却的到期时间戳（毫秒）
var chase_next_use_msec : int = 0
#组合技冷却到期时间戳（毫秒）
var skill_next_use_msec : int = 0
```

### 5.2 新建 `bosses/scripts/boss_state.gd`

```gdscript
@icon( "res://general/icons/state.svg" )
class_name BossState extends Node

## BOSS 状态基类：每个状态一个脚本 + 场景节点（unique_name_in_owner = true）。
## 由 BossStateMachine 注册并驱动；状态之间不互相引用，
## 需要转移时统一走 boss.decision_engine 取目标状态，再交给 boss.state_machine 切换。

var state_machine : BossStateMachine
var boss : Boss
var blackboard : BossBlackboard


func enter() -> void:
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta : float ) -> void:
	pass
```

### 5.3 新建 `bosses/scripts/boss_state_machine.gd`

```gdscript
@icon( "res://general/icons/state_machine.svg" )
class_name BossStateMachine extends Node

var boss : Boss
var blackboard : BossBlackboard
var states : Array[ BossState ]

var current_state : BossState :
	get():
		return states.front()

var prev_state : BossState :
	get():
		return states.get( 1 )


func setup( b : Boss , bb : BossBlackboard ) -> void:
	blackboard = bb
	boss = b
	#子状态按场景中的顺序注册，第一个子节点即初始状态（必须为 BSIdle）
	for c in get_children():
		if c is BossState:
			c.blackboard = bb
			c.boss = b
			c.state_machine = self
			states.append( c )
	current_state.enter()
	pass


func change_state( new_state : BossState ) -> void:
	if not new_state:
		return

	#同一状态：只重入，不重播进入逻辑（与原实现 _change 的同状态早退等价）
	if new_state == current_state:
		current_state.re_enter()
		return

	if current_state:
		current_state.exit()

	states.push_front( new_state )
	current_state.enter()
	if boss and boss.decision_engine:
		boss.decision_engine.current_state = new_state
	states.resize( 2 )
	pass


func physics_update( delta : float ) -> void:
	if current_state:
		current_state.physics_update( delta )
	pass
```

### 5.4 新建 `bosses/scripts/boss_decision_engine.gd`

```gdscript
@icon( "res://general/icons/decision_engine.svg" )
class_name BossDecisionEngine extends Node

## BOSS 决策引擎：持有全部状态节点引用，并按当前阶段给出下一步行为。
## 状态脚本通过 boss.decision_engine 取目标状态，避免状态之间互相引用。

var boss : Boss
var current_state : BossState
var blackboard : BossBlackboard

@onready var bs_idle : BSIdle = %BSIdle
@onready var bs_decide : BSDecide = %BSDecide
@onready var bs_run : BSRun = %BSRun
@onready var bs_attack : BSAttack = %BSAttack
@onready var bs_jump : BSJump = %BSJump
@onready var bs_charge : BSCharge = %BSCharge
@onready var bs_dash : BSDash = %BSDash
@onready var bs_leap : BSLeap = %BSLeap
@onready var bs_skill_charge : BSSkillCharge = %BSSkillCharge
@onready var bs_slam : BSSlam = %BSSlam
@onready var bs_transition : BSTransition = %BSTransition
@onready var bs_death : BSDeath = %BSDeath


#按阶段决定下一步行为（等价于重构前的 _decide()）：近距离统一 attack，远距离按阶段分流
func decide() -> BossState:
	if not boss.has_target():
		return bs_idle

	boss.face_towards_target()

	if absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE:
		return bs_attack

	#jump / dash 共用 5 秒内置冷却：冷却未好时一律以 run 追击
	match blackboard.phase:
		1:
			#一阶段：跳跃快速接近
			return bs_jump if boss.chase_ready() else bs_run
		2:
			#二阶段：下蹲蓄力 → dash 冲刺 → attack 连招
			return bs_charge if boss.chase_ready() else bs_run
		_:
			#三阶段：组合技就绪则使用；否则冲刺连招；两者都不可用时以 run 追击
			if boss.skill_ready():
				return bs_leap
			elif boss.chase_ready():
				return bs_charge
			return bs_run
```

### 5.5 新建 `bosses/scripts/boss.gd`（根节点）

```gdscript
class_name Boss extends CharacterBody2D

## BOSS 根节点（模块化重构后与小怪同构）
## - 结构：Boss + BossStateMachine + BossState 子状态 + BossDecisionEngine + BossBlackboard
## - 数值与行为沿用重构前的 boss_01.gd：
##   阶段阈值每损失 8 点生命切换一次（共 24 血、三阶段）、阶段过场下蹲无敌、
##   一阶段 jump 追击 / 二阶段 crouch→dash→attack / 三阶段 skill_01 跃顶→skill_02 蓄力 2 秒
##   →砸地 npbh_enemy_ground_slam + 左右 npbh_enemy_wave（10 秒内置冷却），
##   jump/dash 共用 5 秒内置冷却，死亡动画，粒子/震屏过场。
## - 物理由各状态脚本自行处理（LEAP / SKILL_CHARGE 不调用 move_and_slide），与本体重构前一致。

#复用已有的 BOSS 专用特效场景（落地砸击 / 左右光波）
const GROUND_SLAM_SCENE : PackedScene = preload( "res://bosses/01/npbh_enemy_ground_slam.tscn" )
const WAVE_SCENE : PackedScene = preload( "res://bosses/01/npbh_enemy_wave.tscn" )

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
var damage_area : DamageArea

var state_machine : BossStateMachine
var decision_engine : BossDecisionEngine
var blackboard : BossBlackboard

var _facing : int = 1
var _hurt_tween : Tween

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
			return "第 三 阶 段 · 狂 暴"
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
	fx.global_position = global_position + Vector2( float( dir ) * 50.0 , -8.0 )
	#镜像整节点使光波朝向该侧（含判定形状一起镜像），波体据 scale.x 决定推进方向
	fx.scale.x = float( dir )
	aim_hazard_at_player( fx )
	play_child_animation( fx )
	#波体自身（npbh_enemy_wave.gd）持续向该侧推进，撞到墙壁后淡出销毁
	pass


#落地砸击：地面砸击特效 + 左右光波 + 吹尘 + 强震屏
func slam_impact() -> void:
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
	attack_area.set_activate( false )
	set_damage_invulnerable( true )
	pass
```

### 5.6 新建 12 个状态脚本 `bosses/scripts/states/bs_*.gd`

> 共同约定：`timer` 承接旧的 `_state_time`（进入时归零，逐帧累加）；状态**自行为理**重力与 `move_and_slide()`；转移统一用 `state_machine.change_state( boss.decision_engine.bs_xxx )`。

**`bs_idle.gd`**

```gdscript
class_name BSIdle extends BossState

## 待机：无锁定玩家时使用。原地缓慢刹停 + 重力，不做任何攻击行为。

func enter() -> void:
	boss.velocity = Vector2.ZERO
	boss.play_animation( "idle" )
	pass


#重复进入（无目标时 decide() 每帧仍返回待机）不再重播动画，保持 idle 循环不中断
func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	boss.velocity.x = move_toward( boss.velocity.x , 0.0 , 1600.0 * delta )
	boss.apply_gravity( delta )
	boss.move_and_slide()
	pass
```

**`bs_decide.gd`**

```gdscript
class_name BSDecide extends BossState

## 决策枢纽：停留 DECIDE_DELAY 秒后向决策引擎要下一步行为（旧的 _tick_decide）。

var timer : float = 0.0


func enter() -> void:
	boss.play_animation( "idle" )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = move_toward( boss.velocity.x , 0.0 , 1600.0 * delta )
	boss.apply_gravity( delta )
	boss.move_and_slide()
	if timer >= Boss.DECIDE_DELAY:
		state_machine.change_state( boss.decision_engine.decide() )
	pass
```

**`bs_run.gd`**

```gdscript
class_name BSRun extends BossState

## 追击兜底：jump / dash 冷却期间以 run 持续贴近玩家。
## 进入攻击距离直接开打；追击手段或组合技重新就绪则交回决策。

var timer : float = 0.0


func enter() -> void:
	boss.play_animation( "run" )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	var dir : int = boss.dir_to_target()
	boss.face( dir )
	boss.velocity.x = float( dir ) * Boss.RUN_SPEED
	boss.apply_gravity( delta )
	boss.move_and_slide()

	#起步缓冲，避免刚进入就立刻跳出
	if timer < Boss.RUN_MIN_TIME:
		return
	#已进入攻击距离 → 直接开打
	if absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE:
		state_machine.change_state( boss.decision_engine.bs_attack )
		return
	#追击手段或组合技重新就绪 → 交回决策，改用 jump / dash / 组合技
	if boss.chase_ready() or ( boss.blackboard.phase >= Boss.MAX_PHASE and boss.skill_ready() ):
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
```

**`bs_attack.gd`**

```gdscript
class_name BSAttack extends BossState

## 普通攻击：面向玩家播放 attack 动画，播完回到决策。

var timer : float = 0.0


func enter() -> void:
	boss.face_towards_target()
	boss.velocity.x = 0.0
	boss.play_animation( "attack" )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = 0.0
	boss.apply_gravity( delta )
	boss.move_and_slide()
	#普通攻击时长与 attack 动画等长，播完回到决策
	if timer >= boss.anim_length( "attack" ):
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
```

**`bs_jump.gd`**

```gdscript
class_name BSJump extends BossState

## 一阶段追击：跳跃贴近玩家（进入共用冷却）。落地后够近接普攻，否则回决策。

var timer : float = 0.0


func enter() -> void:
	#跳跃即视为一次追击，进入共用冷却
	boss.start_chase_cooldown()
	boss.play_animation( "jump" )
	boss.velocity = Vector2( float( boss.dir_to_target() ) * Boss.JUMP_SPEED_X , -Boss.JUMP_FORCE )
	VisualEffects.play_effect_row( 2 , boss.global_position + Vector2( 0 , -10 ) , 1.0 , false , 14.0 )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	var dir : int = boss.dir_to_target()
	boss.face( dir )
	boss.velocity.x = float( dir ) * Boss.JUMP_SPEED_X
	boss.velocity.y = minf( boss.velocity.y + Boss.GRAVITY * delta , Boss.MAX_FALL_SPEED )
	boss.move_and_slide()
	#落地且已离地一小段时间后重新决策（足够近则直接接普攻）
	if timer > Boss.JUMP_GRACE and boss.is_on_floor():
		if absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE:
			state_machine.change_state( boss.decision_engine.bs_attack )
		else:
			state_machine.change_state( boss.decision_engine.bs_decide )
	pass
```

**`bs_charge.gd`**

```gdscript
class_name BSCharge extends BossState

## 二阶段蓄力：下蹲 CHARGE_TIME 秒并散发能量粒子，随后进入 dash。

var timer : float = 0.0
var _fx_time : float = 0.0


func enter() -> void:
	boss.velocity = Vector2.ZERO
	boss.play_animation( "crouch" )
	timer = 0.0
	_fx_time = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = 0.0
	boss.apply_gravity( delta )
	boss.move_and_slide()
	#蓄力期间散发能量粒子
	_fx_time -= delta
	if _fx_time <= 0.0:
		_fx_time = 0.12
		VisualEffects.play_effect_row( 1 , boss.global_position + Vector2( 0 , -40 ) , 0.9 , false , 10.0 )
	if timer >= Boss.CHARGE_TIME:
		state_machine.change_state( boss.decision_engine.bs_dash )
	pass
```

**`bs_dash.gd`**

```gdscript
class_name BSDash extends BossState

## 二阶段冲刺：带残影高速冲向玩家（进入共用冷却），抵达或超时后衔接 attack。

var timer : float = 0.0
var _dash_dir : int = 1
var _afterimage_time : float = 0.0


func enter() -> void:
	#冲刺即视为一次追击，进入共用冷却
	boss.start_chase_cooldown()
	_dash_dir = boss.dir_to_target()
	boss.face( _dash_dir )
	boss.velocity.y = 0.0
	_afterimage_time = 0.0
	boss.play_animation( "dash" )
	VisualEffects.play_effect_row( 2 , boss.global_position + Vector2( 0 , -40 ) , 1.0 , false , 14.0 )
	timer = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	#冲刺全程以固定间隔生成残影（与玩家下落攻击同款残影）
	_afterimage_time -= delta
	if _afterimage_time <= 0.0:
		_afterimage_time = Boss.AFTERIMAGE_INTERVAL
		boss.spawn_afterimage()

	boss.velocity.x = float( _dash_dir ) * Boss.DASH_SPEED
	boss.apply_gravity( delta )
	boss.move_and_slide()

	#抵达玩家附近或超时后立刻衔接 attack
	if timer > Boss.DASH_MIN_TIME and absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE * 0.9:
		state_machine.change_state( boss.decision_engine.bs_attack )
		return
	if timer >= Boss.DASH_MAX_TIME:
		state_machine.change_state( boss.decision_engine.bs_attack )
	pass
```

**`bs_leap.gd`**

```gdscript
class_name BSLeap extends BossState

## 三阶段组合技第一步：skill_01 跃至屏幕正上方中心点（开始即进入 10 秒组合技冷却）。
## 位移由本状态持有的 Tween 驱动，期间铺残影；退出时销毁补间。

var timer : float = 0.0
var _afterimage_time : float = 0.0
var _tween : Tween


func enter() -> void:
	#技能组合开始即进入 10 秒内置冷却
	boss.blackboard.skill_next_use_msec = Time.get_ticks_msec() + Boss.SKILL_COOLDOWN_MSEC
	boss.velocity = Vector2.ZERO
	boss.face_towards_target()
	boss.play_animation( "skill_01" )
	VisualEffects.camera_shake( 5.0 , 0.3 )
	#技能释放瞬间：BOSS 头顶炸开一次粒子
	VisualEffects.play_effect_row( 0 , boss.ring_position() , 1.4 , false , 16.0 )

	if _tween:
		_tween.kill()
	_tween = boss.create_tween()
	_tween.set_trans( Tween.TRANS_CUBIC ).set_ease( Tween.EASE_OUT )
	#略早于 skill_01 播完到位，避免状态切换瞬间把未完成的位移补间销毁
	_tween.tween_property( boss , "global_position" , boss.screen_top_center() , boss.leap_duration() * 0.9 )

	timer = 0.0
	_afterimage_time = 0.0
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	#位置由 Tween 驱动到屏幕正上方中心点，期间铺残影
	_afterimage_time -= delta
	if _afterimage_time <= 0.0:
		_afterimage_time = Boss.AFTERIMAGE_INTERVAL
		boss.spawn_afterimage()
	if timer >= boss.leap_duration():
		state_machine.change_state( boss.decision_engine.bs_skill_charge )
	pass
```

**`bs_skill_charge.gd`**

```gdscript
class_name BSSkillCharge extends BossState

## 三阶段组合技第二步：悬停蓄力 SKILL_CHARGE_TIME 秒，持续喷发粒子并逐步增强震屏。

var timer : float = 0.0
var _fx_time : float = 0.0


func enter() -> void:
	boss.velocity = Vector2.ZERO
	boss.play_animation( "skill_02" )
	_fx_time = 0.0
	timer = 0.0
	VisualEffects.camera_shake( 3.0 , 0.3 )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	#悬停蓄力：不移动，持续喷发粒子并逐步增强震屏
	boss.velocity = Vector2.ZERO
	_fx_time -= delta
	if _fx_time <= 0.0:
		_fx_time = 0.16
		VisualEffects.play_effect_row( 1 , boss.global_position + Vector2( 0 , -36 ) , 1.4 , false , 12.0 )
		VisualEffects.play_effect_row( 0 , boss.global_position + Vector2( 0 , -36 ) , 1.1 , false , 10.0 )
	VisualEffects.camera_shake( 2.0 + 4.0 * clampf( timer / Boss.SKILL_CHARGE_TIME , 0.0 , 1.0 ) , 0.2 )
	if timer >= Boss.SKILL_CHARGE_TIME:
		state_machine.change_state( boss.decision_engine.bs_slam )
	pass
```

**`bs_slam.gd`**

```gdscript
class_name BSSlam extends BossState

## 三阶段组合技第三步：从屏幕顶端垂直砸向地面，落地触发砸击特效并回到决策。

func enter() -> void:
	boss.face_towards_target()
	boss.play_animation( "dash" )
	boss.velocity = Vector2( 0.0 , Boss.SLAM_SPEED )
	VisualEffects.camera_shake( 4.0 , 0.2 )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta : float ) -> void:
	#垂直砸向地面
	boss.velocity.x = 0.0
	boss.velocity.y = Boss.SLAM_SPEED
	boss.move_and_slide()
	if boss.is_on_floor():
		boss.slam_impact()
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
```

**`bs_transition.gd`**

```gdscript
class_name BSTransition extends BossState

## 阶段过场：crouch 下蹲 + 无敌 + 持续粒子/震屏，期间保持朝向玩家（锁定不丢失）。

var timer : float = 0.0
var _fx_time : float = 0.0


func enter() -> void:
	boss.blackboard.invulnerable = true
	boss.set_damage_invulnerable( true )
	boss.velocity.x = 0.0
	_fx_time = 0.0
	timer = 0.0
	boss.play_animation( "crouch" )
	#过场配套增强：开场爆发粒子 + 强力震屏 + HUD 横幅/闪光（由 boss_phase_changed 驱动）
	VisualEffects.play_effect_row( 0 , boss.global_position + Vector2( 0 , -40 ) , 1.9 , false , 16.0 )
	VisualEffects.play_effect_row( 1 , boss.global_position + Vector2( 0 , -40 ) , 1.6 , false , 14.0 )
	VisualEffects.camera_shake( 8.0 , 0.5 )
	Messages.boss_phase_changed.emit( boss.blackboard.phase , boss.phase_display_name() )
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	#阶段过场结束：解除无敌（死亡时保持无敌）
	if not boss.blackboard.dead:
		boss.blackboard.invulnerable = false
		boss.set_damage_invulnerable( false )
	pass


func physics_update( delta : float ) -> void:
	timer += delta
	boss.velocity.x = 0.0
	boss.apply_gravity( delta )
	boss.move_and_slide()
	#过场期间依然朝向玩家，保证锁定关系不丢失
	if boss.has_target():
		boss.face( boss.dir_to_target() )

	#下蹲无敌期间在 BOSS 周围持续生成粒子特效
	_fx_time -= delta
	if _fx_time <= 0.0:
		_fx_time = 0.07
		var offset := Vector2( randf_range( -46.0 , 46.0 ) , randf_range( -120.0 , -6.0 ) )
		var row : int = 0 if randf() < 0.5 else 1
		VisualEffects.play_effect_row( row , boss.global_position + offset , randf_range( 1.0 , 1.8 ) , false , 14.0 )
	VisualEffects.camera_shake( 4.0 , 0.12 )

	if timer >= Boss.TRANSITION_TIME[ clampi( boss.blackboard.phase , 0 , Boss.MAX_PHASE ) ]:
		state_machine.change_state( boss.decision_engine.bs_decide )
	pass
```

**`bs_death.gd`**

```gdscript
class_name BSDeath extends BossState

## 死亡：death 动画 → 广播 boss_defeated → 精灵与武器同步淡出 → 销毁整只 BOSS。

func enter() -> void:
	boss.blackboard.dead = true
	boss.blackboard.invulnerable = true
	boss.velocity = Vector2.ZERO
	boss.clear_hurt_tween()
	boss.sprite.modulate = Color.WHITE
	boss.attack_area.set_activate( false )
	boss.set_damage_invulnerable( true )
	boss.play_animation( "death" )
	VisualEffects.camera_shake( 10.0 , 0.6 )
	Messages.boss_defeated.emit()
	_death_sequence()
	pass


func re_enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update( _delta : float ) -> void:
	pass


func _death_sequence() -> void:
	await boss.animation_player.animation_finished
	var tw := boss.create_tween()
	tw.set_parallel( true )
	tw.tween_property( boss.sprite , "modulate:a" , 0.0 , 0.5 )
	tw.tween_property( boss.sprite_weapon , "modulate:a" , 0.0 , 0.5 )
	await tw.finished
	boss.queue_free()
	pass
```

### 5.7 修改 `bosses/01/boss_01.tscn`

1. 替换根脚本资源行：
   `[ext_resource type="Script" path="res://bosses/01/boss_01.gd" id="4_boss"]`
   → `[ext_resource type="Script" path="res://bosses/scripts/boss.gd" id="4_boss"]`
2. 新增 ext_resource（id 保持不与现有 `2_spr / 2_vd0h7 / 3_evsoo / 4_boss / 5_dmg` 冲突，用 `6_` 起）：
   - `6_bsm` → `res://bosses/scripts/boss_state_machine.gd`
   - `7_bde` → `res://bosses/scripts/boss_decision_engine.gd`
   - `8_*` ~ `19_*` → 12 个 `res://bosses/scripts/states/bs_*.gd`
3. 在文件末尾 `CollisionShape2D`（DamageArea 下）之后追加以下节点块。
   **注意：`BSIdle` 必须是 `BossStateMachine` 的第一个子节点**（`setup()` 用 `states.front()` 作为初始状态），其余顺序不限：

```
[node name="BossStateMachine" type="Node" parent="."]
script = ExtResource("6_bsm")

[node name="BSIdle" type="Node" parent="BossStateMachine"]
unique_name_in_owner = true
script = ExtResource("8_bsidle")

...（BSDecide / BSRun / BSAttack / BSJump / BSCharge / BSDash / BSLeap /
     BSSkillCharge / BSSlam / BSTransition / BSDeath 同样写法，各自换脚本 id）

[node name="BossDecisionEngine" type="Node" parent="."]
script = ExtResource("7_bde")
```

4. **不改动**：根节点 `uid="uid://ctxm262ufe5hl"`（`boss_arena.tscn` 依赖它）、`collision_layer=0` / `collision_mask=3`、`Sprite` / `Sprite/Sprite2D` / `AnimationPlayer` / `AttackArea`(layer 0, mask 16) / `DamageArea`(layer 32, mask 0) 及其形状、动画库。

### 5.8 删除

- `bosses/01/boss_01.gd`
- `bosses/01/boss_01.gd.uid`

### 5.9 注释同步（2 处，仅注释文字）

- `00_global/boss_hud/boss_hud.gd` 第 39 行：`须与 boss_01.gd 的 SKILL_COOLDOWN_MSEC 一致` → `须与 bosses/scripts/boss.gd 的 SKILL_COOLDOWN_MSEC 一致`
- `bosses/01/npbh_enemy_wave.gd` 第 4 行：`由生成方（boss_01.gd）设置的 scale.x` → `由生成方（bosses/scripts/boss.gd）设置的 scale.x`

## 六、假设与决策

1. **独立 BOSS 模块**：新建 `Boss` / `BossState` 等独立类，**不继承** `Enemy`，不共用 `EnemyState` / `Blackboard` / `DecisionEngineBasic*`；对小怪相关文件**零改动**。
2. **玩家锁定方式不变**：继续用 `get_tree().get_first_node_in_group( "Player" )`，已锁定则不主动丢弃（不用 `PlayerSensor`）。
3. **物理归属不变**：重力与 `move_and_slide()` 由各状态自行处理，`Boss` 根节点不做统一物理；`BSLeap` / `BSSkillCharge` 完全不调用 `move_and_slide`（与现状一致）。
4. **决策模型保留"显式转移"**：`BossDecisionEngine.decide()` 只做"按阶段返回下一步行为"这一件事，由 `BSDecide` 在 `DECIDE_DELAY` 之后调用；其余状态显式转移到 `boss.decision_engine` 提供的目标状态。这样既得到小怪式的模块拆分，又保证行为时序 1:1。
5. **数值零漂移**：所有常量（含 `SKILL_CHARGE_TIME = 2.0`）原样保留在 `Boss` 上，状态脚本通过 `Boss.XXX` 读取；不往场景里加 `@export` 参数。
6. **计时器语义**：旧的共享 `_state_time` 由每个状态自己的 `timer` 承接（进入时归零）；`_fx_time` / `_afterimage_time` 同样下沉到各自状态并在 `enter()` 归零。与旧实现的唯一差异是粒子/残影"首次触发时机"可能提前不超过 1 帧（≤0.07 秒），视觉不可辨。
7. **LEAP 位移补间**由 `BSLeap` 持有并在 `exit()` 中 kill——等价于旧的"任何状态退出都 kill 共享 `_tween`"（因为只有 LEAP 会创建补间）。
8. **不加** `@tool` / `_get_configuration_warnings()`：BOSS 无需编辑器预览，保持改动最小。
9. `BossBlackboard` 只保留真正被使用的字段（`target / max_hp / hp / phase / dead / invulnerable / combat_started / chase_next_use_msec / skill_next_use_msec`），不照抄小怪的 `can_decide / edge_detected / damage_source / dir` 等 BOSS 用不到的字段。

## 七、验证方式

本机无 Godot CLI，无法命令行编译校验，采用"编辑器实测 + 静态核对"：

1. **静态核对**
   - 用 Grep 确认旧实现的名字已无残留引用：`boss_01.gd`、`_change(`、`_tick_`、`State.`、`play_anim(`、`_apply_facing`。
   - 逐一比对第五节代码与旧 `boss_01.gd` 对应函数，尤其：`ATTACK_RANGE * 0.9`（DASH）、`JUMP_GRACE`（JUMP）、`DASH_MIN_TIME/DASH_MAX_TIME`、`TRANSITION_TIME[clampi(phase,0,MAX_PHASE)]`、`SKILL_CHARGE_TIME=2.0`、`CHASE_COOLDOWN_MSEC=5000`、`SKILL_COOLDOWN_MSEC=10000`。
   - 确认 `boss_01.tscn` 保留了场景 uid 与全部碰撞层设置。
2. **编辑器实测**（Godot 编辑器打开项目）
   - 先确认输出面板无解析错误；事件检查 `boss_01.tscn`：`BossStateMachine` 下有 12 个子状态（`BSIdle` 排第一、均 `unique_name_in_owner = true`），另有 `BossDecisionEngine` 节点。
   - `bosses/01/boss_arena.tscn` 目前未被任何关卡引用，直接 F6「运行当前场景」即可（该场景已含玩家出生点、地面与左右墙）。
   - 逐项验收：
     - 底部血条出现并随受击刷新；阶段横幅在 16/8 血时触发。
     - 一阶段：远距离 jump 追击，落地后够近接普攻；jump 后 5 秒内改为 run 追击。
     - 二阶段：远距离 crouch 蓄力 → dash（带残影）→ 贴身 attack；dash 同样进 5 秒冷却。
     - 三阶段：skill_01 跃至屏幕正上方中心 → skill_02 蓄力 2 秒（震屏渐强）→ 砸地：`npbh_enemy_ground_slam` + 左右 `npbh_enemy_wave` 持续向两侧加速推进（上限 300）并在撞墙后淡出（可多次触发，间隔 = 10 秒冷却）；HUD 左侧技能图标呈现"未解锁 / 回充中 / 就绪"三态。
     - 每次阶段切换：crouch 下蹲 + 无敌（期间打不掉血）+ 周围粒子 + 强震屏，过场结束恢复可受击，且全程朝向玩家。
     - hp 归零：death 动画 → `boss_defeated` → 精灵与武器淡出 → 节点销毁；HUD 血条隐藏。
     - 玩家死亡时：BOSS 冻结（物理停止、动画暂停、攻击判定关闭）。
     - 无锁定玩家时：BOSS 播 idle 待机且不移动、不显示血条。
