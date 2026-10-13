class_name DamageNumber extends Node2D

## 世界空间伤害数字：在命中位置放大弹入 → 上浮 → 淡出，结束后自动销毁。
## 由 VisualEffects.spawn_damage_number() 创建；负数按治疗显示为 "+N"。

const RISE : float = 20.0
const TOTAL_TIME : float = 0.8
const FADE_TIME : float = 0.3
const NORMAL_SIZE : int = 12
const BIG_SIZE : int = 20
const BOX_WIDTH : float = 64.0
const OUTLINE_COLOR := Color( 0.06 , 0.03 , 0.08 , 1.0 )
const NORMAL_COLOR := Color( 1.0 , 0.95 , 0.6 )
const BIG_COLOR := Color( 1.0 , 0.45 , 0.35 )


#amount 数值（负值显示为回血 +N）；big=true 用于阶段切换/暴击等大号强调
func setup( amount : float , big : bool = false ) -> void:
	var value : int = int( round( absf( amount ) ) )
	var text : String = str( value )
	if amount < 0.0:
		text = "+" + text
	var label := Label.new()
	label.text = text
	#不依赖字体测量：用固定宽度文本框 + 居中对齐，让数字围绕节点原点居中
	label.size = Vector2( BOX_WIDTH , float( BIG_SIZE ) + 6.0 )
	label.position = Vector2( -BOX_WIDTH * 0.5 , -( float( BIG_SIZE ) + 6.0 ) * 0.5 )
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var settings := LabelSettings.new()
	settings.font_size = BIG_SIZE if big else NORMAL_SIZE
	settings.font_color = BIG_COLOR if big else NORMAL_COLOR
	settings.outline_size = 4 if big else 3
	settings.outline_color = OUTLINE_COLOR
	label.label_settings = settings
	add_child( label )
	_start( big )
	pass


func _start( big : bool ) -> void:
	z_index = 20
	scale = Vector2.ONE * ( 0.5 if big else 0.6 )
	var pop := create_tween()
	pop.set_parallel( true )
	pop.tween_property( self , "scale" , Vector2.ONE , 0.18 if big else 0.14 ) \
		.set_trans( Tween.TRANS_BACK ).set_ease( Tween.EASE_OUT )
	pop.tween_property( self , "position:y" , position.y - RISE , TOTAL_TIME ) \
		.set_trans( Tween.TRANS_SINE ).set_ease( Tween.EASE_OUT )
	var fade := create_tween()
	fade.tween_property( self , "modulate:a" , 0.0 , FADE_TIME ).set_delay( TOTAL_TIME - FADE_TIME )
	fade.tween_callback( queue_free )
	pass