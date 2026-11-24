extends RefCounted
## Emits the two streamed columns rendered per 32 pixels of forward camera travel.

var task := 0
var column := 24
var _scroll := 0
var _previous_left := 0


func reset(camera_left: int) -> Vector2i:
	var first := floori(camera_left / 256.0) * 16
	column = first + 24
	task = 0
	_scroll = 0
	_previous_left = camera_left
	return Vector2i(first, column)


func advance(camera_left: int) -> int:
	_scroll += maxi(0, camera_left - _previous_left)
	_previous_left = camera_left
	if task == 0 and _scroll >= 32:
		_scroll -= 32
		task = 8
	var reached := column if task in [8, 4] else -1
	if task in [5, 1]:
		column += 1
	if task > 0:
		task -= 1
	return reached
