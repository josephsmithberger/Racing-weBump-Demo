extends SceneTree
## Exercises the same threaded resource load as Start Race, in a fresh process.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://scenes/main.tscn"
	var started := Time.get_ticks_msec()
	var error := ResourceLoader.load_threaded_request(path, "", true)
	if error != OK:
		quit(1)
		return
	var progress: Array = []
	while Time.get_ticks_msec() - started < 10000:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var scene := ResourceLoader.load_threaded_get(path) as PackedScene
			print("Threaded race load: PASS (%d ms)" % (Time.get_ticks_msec() - started))
			quit(0 if scene else 1)
			return
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			break
		await process_frame
	print("Threaded race load: FAIL; progress=", progress)
	quit(1)
