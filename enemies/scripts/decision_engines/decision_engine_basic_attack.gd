class_name DecisionEngineBasicAttack extends DecisionEngine


#meta-name : DecisionEngine
#meta-description : Boilerplate decision engine script
#mata-default : true

#Included in DecisionEngine:
#var enemy : Enemy
#var current_state : EnemyState
#var blackboard : Blackboard
@export var attack_state : ESAttack
@export var chase_state : EnemyState
@export var focus_state : EnemyState

@onready var es_walk: ESWalk = %ESWalk
@onready var es_stun: ESStun = %ESStun
@onready var es_death: ESDeath = %ESDeath

#本次“发现玩家”是否已播放过 focus：仅在 target 从无到有时聚焦一次，
#target 丢失（离开 PlayerSensor 搜索计时结束）后重置，下次发现再播。
#不能用 current_state is ESWalk 判断——部分敌人的 chase_state 本身就是 ESWalk，会导致追击/聚焦来回切换
var _focused : bool = false


func _ready() -> void:
	await super() 
	pass

func decide() -> EnemyState:
	if blackboard.damage_source:
		if blackboard.health <= 0:
			return es_death
		else:
			return es_stun
	
	if current_state is ESDeath or not blackboard.can_decide:
		return null
	
	if blackboard.target:
		#发现玩家后先播一遍 focus 聚焦动画（即使已贴脸；播放期间 can_decide=false 不会被攻击打断）
		#聚焦仅一次，播完本场目标存续期内进入追击/攻击循环，不再重复触发
		if focus_state and not _focused:
			_focused = true
			return focus_state
		if attack_state.can_attack():
			return attack_state
		return chase_state
	#丢失目标：重置聚焦标志并回到巡逻，下次进入 PlayerSensor 会再聚焦一次
	_focused = false
	return es_walk
		
