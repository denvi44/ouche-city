extends SceneTree
## Exporte les sons synthétisés d'Ouche City en fichiers WAV pour les écouter ou les retravailler.
## Usage : godot --headless --path game -s ../audio/export_wav.gd -- --out=/chemin/vers/dossier
## Les paramètres de génération sont dans game/scripts/audio/synth.gd (une fonction par son).

const SOUNDS := ["klaxon", "engine_loop", "tractor_loop", "thud", "glass", "crate", "moo", "chime", "fail", "fanfare", "step", "radio_blip", "bell", "wind_loop", "bird", "music_pommier"]


func _initialize() -> void:
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out: String = args.get("out", "user://audio_export")
	DirAccess.make_dir_recursive_absolute(out)
	for n in SOUNDS:
		var samples: PackedFloat32Array = Callable(Synth, n).call()
		# Les boucles sont répétées 4 fois : plus facile à juger à l'oreille.
		if n.ends_with("_loop"):
			var rep := PackedFloat32Array()
			for i in 4:
				rep.append_array(samples)
			samples = rep
		var path := out.path_join(n + ".wav")
		Synth.to_stream(samples).save_to_wav(path)
		print("[export] ", path, "  ", "%.1f s" % (samples.size() / float(Synth.RATE)))
	quit(0)
