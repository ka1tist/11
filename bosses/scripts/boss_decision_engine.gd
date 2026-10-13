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

	#普通攻击内置 1 秒冷却：冷却期间视为暂无出手机会，改走常规追击
	if boss.attack_ready() and absf( boss.dx_to_target() ) <= Boss.ATTACK_RANGE:
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
