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

#受击连锁：1 秒内被玩家连砍两刀时触发受击退避（hurt 状态）
var hit_chain : int = 0
var last_hit_msec : int = 0

#二/三阶段专属技能：贴近玩家完成的普通攻击计数与状态锁
var pb_attack_count : int = 0
var pb_skill_locked : bool = false
#冲刺连招收尾的那记普攻标记：冲刺结束时置位，由 bs_attack 读取后清除，不计入触发计数
var skip_next_attack_count : bool = false
