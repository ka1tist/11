#class_name DecisionEngineName
extends DecisionEngine


#meta-name : DecisionEngine
#meta-description : Boilerplate decision engine script
#mata-default : true

#Included in DecisionEngine:
#var enemy : Enemy
#var current_state : EnemyState
#var blackboard : Blackboard

func _ready() -> void:
	await super() 
	pass

func decide() -> EnemyState:
	#Example decisions
	#if blackboard.damage_source:
		#if blackboard.health <= 0:
			#return es_death
		#else:
			#return es_stun
	
	#if current_state is ESDeath or not blackboard.can_decide:
		#return null
	
	#if blackboard.target:
		#if blackboard.distance_to_target < 40:
			#return attack_state?
		#return chase_state?
	return null
		
