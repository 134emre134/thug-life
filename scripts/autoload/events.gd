extends Node
## Global signal bus. Only for cross-cutting, fire-and-forget events
## (UI notifications, later: crime events). Gameplay components should
## prefer direct signals between nodes that know each other.

## Short on-screen message for the player (e.g. "Picked up: Cash").
signal notification_requested(text: String)


func notify(text: String) -> void:
	notification_requested.emit(text)
