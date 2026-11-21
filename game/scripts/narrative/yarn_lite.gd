class_name YarnLite
extends RefCounted
## Lecteur d'un sous-ensemble de Yarn (agent 07) pour les dialogues de Frouch City (narrative/dialogues/*.yarn).
##
## Un fichier contient des nœuds :
##     title: m01_intro
##     ---
##     Gégé: Alors, mon petit, vingt-quatre bouteilles ! #line:m01_intro_01 #onoma:HMPF
##     Ginette: Et pas une de cassée ! #line:m01_intro_02
##     <<jump m01_suite>>
##     ===
## Réplique = « Locuteur: texte », suivie d'étiquettes `#clé:valeur` (obligatoire : `#line:` identifiant stable, pour le
## sous-titrage et la traduction ; facultatif : `#onoma:TEXTE` onomatopée en bulle au-dessus du locuteur, `#wait:secondes`).
## Commandes : `<<jump nœud>>` (enchaîne), `<<end>>`. Les lignes vides et celles qui commencent par `//` sont ignorées.
## Pas de choix ni de variables : les dialogues sont des « aboiements » et des scènes sans blocage (jeu en ligne).

## Résultat : { nœud: {"lines": [ {speaker, text, id, tags{}} ], "jump": nœud suivant ou ""} }
static func parse(source: String) -> Dictionary:
	var nodes := {}
	var title := ""
	var in_body := false
	var cur := {"lines": [], "jump": ""}
	for raw in source.split("\n"):
		var line := raw.strip_edges()
		if line == "":
			continue
		if not in_body:
			if line.begins_with("title:"):
				title = line.substr(6).strip_edges()
			elif line == "---":
				in_body = true
				cur = {"lines": [], "jump": ""}
			continue
		if line == "===":
			if title != "":
				nodes[title] = cur
			title = ""
			in_body = false
			continue
		if line.begins_with("//"):
			continue
		if line.begins_with("<<"):
			var cmd := line.trim_prefix("<<").trim_suffix(">>").strip_edges()
			if cmd.begins_with("jump "):
				cur.jump = cmd.substr(5).strip_edges()
			continue
		var colon := line.find(":")
		if colon <= 0:
			continue
		var speaker := line.substr(0, colon).strip_edges()
		var rest := line.substr(colon + 1).strip_edges()
		var tags := {}
		var text := rest
		var hash_at := rest.find(" #")
		if hash_at >= 0:
			text = rest.substr(0, hash_at).strip_edges()
			for tag in rest.substr(hash_at).split(" #", false):
				var t := tag.strip_edges().trim_prefix("#")
				var c := t.find(":")
				if c > 0:
					tags[t.substr(0, c)] = t.substr(c + 1).strip_edges()
		cur.lines.append({"speaker": speaker, "text": text, "id": str(tags.get("line", "")), "tags": tags})
	return nodes


## Durée d'affichage d'une réplique (s) : lecture confortable, 1,6 s au minimum, ou `#wait:` s'il est donné.
static func duration_of(line: Dictionary) -> float:
	if line.tags.has("wait"):
		return float(line.tags.wait)
	return clampf(1.2 + float(str(line.text).length()) * 0.055, 1.6, 7.0)
