extends Control
## Simple procedural crosshair, drawn at the control's centre.

@export var color: Color = Color(1, 1, 1, 0.9)
@export var gap: float = 4.0
@export var length: float = 8.0
@export var thickness: float = 2.0
@export var dot_radius: float = 1.5


func _draw() -> void:
	var c := size * 0.5
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * gap, c + dir * (gap + length), color, thickness, true)
	draw_circle(c, dot_radius, color)
