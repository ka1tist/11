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
