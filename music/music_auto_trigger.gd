@icon( "res://general/icons/music_trigger.svg" )
class_name MusicAutoTrigger extends Node


@export var track : AudioStream
@export var reverb : Audio.REVERB_TYPE = Audio.REVERB_TYPE.NONE
#默认进场即播放；关闭后改为等 Messages.boss_awakened（BOSS 被玩家交互唤醒）再播放，
#用于 BOSS 战：交互开战之前不要放战斗音乐
@export var auto_play : bool = true



func _ready() -> void:
	if auto_play:
		play()
	else:
		#开场不放（BOSS 战）：进场时先停掉上一关残留的曲子——Audio 是 autoload、播放器不随场景销毁，
		#不主动停的话从别的关卡进本关会一直听到上一关的音乐
		Audio.stop_music()
		Messages.boss_awakened.connect( play )
	pass


#播放本节点配置的曲子并应用混响（auto_play 关闭时由交互唤醒触发）
func play() -> void:
	if track == null:
		return
	Audio.play_music( track )
	Audio.set_reverb( reverb )
	pass
