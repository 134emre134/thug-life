class_name CombatDirector
extends Node
## Hands out attack tokens in group fights (M2.7): only [member max_attackers]
## NPCs may attack at once, the others circle and wait. Grants are spaced out
## by [member grant_interval] so attacks come one after another, readable over
## the shoulder. NPCs find the director through the "combat_director" group.
##
## Shooters (M4b.4) draw from a separate pool: only [member max_shooters]
## ranged NPCs may aim and fire at once, so shots stay telegraphed one at a
## time. Melee attackers and shooters don't take each other's tokens.

@export var max_attackers: int = 2
## Minimum seconds between two grants.
@export var grant_interval: float = 0.6
## Seconds an NPC waits after returning a token before it can get another.
@export var reuse_cooldown: float = 1.4

@export_group("Shooters (M4b)")
## Ranged NPCs allowed to aim and fire at the same time.
@export var max_shooters: int = 1
## Minimum seconds between two shooter grants.
@export var shot_grant_interval: float = 0.8
## Seconds a shooter waits after returning its token before it can get another.
@export var shot_reuse_cooldown: float = 2.0
## Quiet seconds after a shooter is done before the next one may aim (a
## breather to move or close in).
@export var shot_rest_time: float = 1.0

## Most shooter tokens held at the same time so far (tests, debug).
var peak_shooters: int = 0

var _members: Array[Node] = []
var _holders: Array[Node] = []
var _cooldown_until: Dictionary = {}
var _time: float = 0.0
var _last_grant: float = -INF
var _shooters: Array[Node] = []
var _shot_cooldown_until: Dictionary = {}
var _last_shot_grant: float = -INF
var _last_shot_release: float = -INF


func _ready() -> void:
	add_to_group(&"combat_director")


func _physics_process(delta: float) -> void:
	_time += delta


func register(member: Node) -> void:
	if not _members.has(member):
		_members.append(member)


func unregister(member: Node) -> void:
	release_token(member)
	release_shot_token(member)
	_members.erase(member)
	_cooldown_until.erase(member.get_instance_id())
	_shot_cooldown_until.erase(member.get_instance_id())


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


## Asks for permission to aim and fire (ranged NPCs). True if
## [param requester] holds a shooter token.
func request_shot_token(requester: Node) -> bool:
	_prune()
	if _shooters.has(requester):
		return true
	if _shooters.size() >= max_shooters:
		return false
	if _time - _last_shot_grant < shot_grant_interval:
		return false
	if _shooters.is_empty() and _time - _last_shot_release < shot_rest_time:
		return false
	if _time < float(_shot_cooldown_until.get(requester.get_instance_id(), -INF)):
		return false
	_shooters.append(requester)
	_last_shot_grant = _time
	peak_shooters = maxi(peak_shooters, _shooters.size())
	return true


func release_shot_token(requester: Node) -> void:
	if _shooters.has(requester):
		_shooters.erase(requester)
		_shot_cooldown_until[requester.get_instance_id()] = _time + shot_reuse_cooldown
		_last_shot_release = _time


func has_shot_token(requester: Node) -> bool:
	return _shooters.has(requester)


func get_shooter_count() -> int:
	_prune()
	return _shooters.size()


func _prune() -> void:
	for i in range(_holders.size() - 1, -1, -1):
		if not is_instance_valid(_holders[i]):
			_holders.remove_at(i)
	for i in range(_shooters.size() - 1, -1, -1):
		if not is_instance_valid(_shooters[i]):
			_shooters.remove_at(i)
	for i in range(_members.size() - 1, -1, -1):
		if not is_instance_valid(_members[i]):
			_members.remove_at(i)
