class_name CombatDirector
extends Node
## Hands out attack tokens in group fights (M2.7): only [member max_attackers]
## NPCs may attack at once, the others circle and wait. Grants are spaced out
## by [member grant_interval] so attacks come one after another, readable over
## the shoulder. NPCs find the director through the "combat_director" group.

@export var max_attackers: int = 2
## Minimum seconds between two grants.
@export var grant_interval: float = 0.6
## Seconds an NPC waits after returning a token before it can get another.
@export var reuse_cooldown: float = 1.4

var _members: Array[Node] = []
var _holders: Array[Node] = []
var _cooldown_until: Dictionary = {}
var _time: float = 0.0
var _last_grant: float = -INF


func _ready() -> void:
	add_to_group(&"combat_director")


func _physics_process(delta: float) -> void:
	_time += delta


func register(member: Node) -> void:
	if not _members.has(member):
		_members.append(member)


func unregister(member: Node) -> void:
	release_token(member)
	_members.erase(member)
	_cooldown_until.erase(member.get_instance_id())


## NPCs taking part in fights (for spacing around a target).
func get_members() -> Array[Node]:
	_prune()
	return _members


## Asks for permission to attack. True if [param requester] holds a token.
func request_token(requester: Node) -> bool:
	_prune()
	if _holders.has(requester):
		return true
	if _holders.size() >= max_attackers:
		return false
	if _time - _last_grant < grant_interval:
		return false
	if _time < float(_cooldown_until.get(requester.get_instance_id(), -INF)):
		return false
	_holders.append(requester)
	_last_grant = _time
	return true


func release_token(requester: Node) -> void:
	if _holders.has(requester):
		_holders.erase(requester)
		_cooldown_until[requester.get_instance_id()] = _time + reuse_cooldown


func has_token(requester: Node) -> bool:
	return _holders.has(requester)


func get_attacker_count() -> int:
	_prune()
	return _holders.size()


func _prune() -> void:
	for i in range(_holders.size() - 1, -1, -1):
		if not is_instance_valid(_holders[i]):
			_holders.remove_at(i)
	for i in range(_members.size() - 1, -1, -1):
		if not is_instance_valid(_members[i]):
			_members.remove_at(i)
