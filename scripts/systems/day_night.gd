extends CanvasModulate
## Day/night cycle. Tints the world and tells the game when night falls.

signal night_started
signal morning

## Real seconds for one full 24h day.
const DAY_LENGTH := 720.0
const NIGHT_START := 20.5
const NIGHT_END := 5.5

## Colour keyframes: [hour, colour]
const KEYS := [
	[0.0, Color(0.30, 0.34, 0.62)],
	[4.5, Color(0.32, 0.36, 0.64)],
	[6.0, Color(1.0, 0.78, 0.78)],
	[7.5, Color(1.0, 0.97, 0.92)],
	[9.0, Color(1, 1, 1)],
	[17.0, Color(1, 1, 1)],
	[18.5, Color(1.0, 0.86, 0.64)],
	[19.8, Color(0.98, 0.66, 0.56)],
	[21.0, Color(0.36, 0.38, 0.66)],
	[24.0, Color(0.30, 0.34, 0.62)],
]

var time_of_day: float = 8.0
var day: int = 1
var _was_night: bool = false


func _ready() -> void:
	_was_night = is_night()
	color = color_for(time_of_day)


func _process(delta: float) -> void:
	advance(delta * 24.0 / DAY_LENGTH)


func advance(hours: float) -> void:
	time_of_day += hours
	while time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1
	color = color_for(time_of_day)
	var night := is_night()
	if night and not _was_night:
		night_started.emit()
	elif not night and _was_night:
		morning.emit()
	_was_night = night


## Jump to the given hour, rolling over to the next day if needed.
func set_time(hour: float, next_day: bool) -> void:
	if next_day:
		day += 1
	time_of_day = hour
	color = color_for(time_of_day)
	var night := is_night()
	if _was_night and not night:
		morning.emit()
	_was_night = night


func is_night() -> bool:
	return time_of_day >= NIGHT_START or time_of_day < NIGHT_END


func is_evening() -> bool:
	return time_of_day >= 18.5 or time_of_day < NIGHT_END


## 0 at noon, 1 in deep night (used for light strength).
func darkness() -> float:
	var c: Color = color_for(time_of_day)
	return clampf((1.0 - (c.r + c.g + c.b) / 3.0) * 1.9, 0.0, 1.0)


func color_for(hour: float) -> Color:
	for i in range(KEYS.size() - 1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if hour >= a[0] and hour <= b[0]:
			var t: float = (hour - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			return (a[1] as Color).lerp(b[1] as Color, t)
	return Color.WHITE


func clock_text() -> String:
	var hh: int = int(time_of_day)
	var mm: int = int((time_of_day - hh) * 60.0)
	return "Day %d  %02d:%02d" % [day, hh, mm]
