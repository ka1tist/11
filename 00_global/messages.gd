extends Node


@warning_ignore( "unused_signal" )
signal player_interacted( player : Player )

@warning_ignore( "unused_signal" )
signal player_healed( amount : float )

@warning_ignore( "unused_signal" )
signal input_hint_changed( hint : String )

@warning_ignore( "unused_signal" )
signal player_health_changed( hp : float , max_hp : float )

@warning_ignore( "unused_signal" )
signal back_to_title_screen()

#玩家死亡（hp归零/进入死亡状态）时只发射一次：敌人等对象据此立即冻结
@warning_ignore( "unused_signal" )
signal player_died()

@warning_ignore( "unused_signal" )
signal coin_collected( coin : int )

@warning_ignore( "unused_signal" )
signal diamond_collected( diamond : int )

#血瓶数量变化：HUD 据此实时刷新计数显示
@warning_ignore( "unused_signal" )
signal potion_changed( count : int )

#BOSS 血量变化：BossHud 据此刷新主血条与残影条
@warning_ignore( "unused_signal" )
signal boss_health_changed( hp : float , max_hp : float )

#BOSS 阶段切换：BossHud 据此播放全屏阶段横幅/刻度高亮
@warning_ignore( "unused_signal" )
signal boss_phase_changed( phase : int , phase_name : String )

#BOSS 被击败：BossHud 据此隐藏血条，竞技场据此写入持久化数据
@warning_ignore( "unused_signal" )
signal boss_defeated()

#BOSS 被玩家交互唤醒（起身演出开始）：入场音乐等据此开始播放（唤醒前不播放）
@warning_ignore( "unused_signal" )
signal boss_awakened()

#BOSS 组合技冷却：ratio 为回充进度(0→1)，ready 为是否可立即释放，
#unlocked 为是否已解锁（进入第三阶段才解锁）。BOSS 本体光环与 BossHud 冷却图标据此显示。
@warning_ignore( "unused_signal" )
signal boss_skill_cooldown( ratio : float , ready : bool , unlocked : bool )

#敌人受击：伤害数字/飘字据此在命中位置弹出数值
@warning_ignore( "unused_signal" )
signal enemy_damaged( pos : Vector2 , amount : float )
