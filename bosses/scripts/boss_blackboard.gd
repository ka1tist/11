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

#普通攻击冷却到期时间戳（毫秒）
var attack_next_use_msec : int = 0
#追击手段（jump / dash）共用冷却的到期时间戳（毫秒）
var chase_next_use_msec : int = 0
#组合技冷却到期时间戳（毫秒）
var skill_next_use_msec : int = 0
