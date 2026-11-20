# Contrats

Schémas JSON (draft 2020-12) partagés entre agents. Source de vérité.

| Schéma | Version | Producteur | Consommateurs |
| --- | --- | --- | --- |
| `tile.schema.json` | 1 | cartographe (01) | assets-3d (04), level-designer (02), game |
| `poi.schema.json` | 2 | cartographe (01), level-designer (02) | gameplay (05), narration (07) |
| `mission.schema.json` | 1 | narration (07) | gameplay (05), réseau (12), qa (09) |
| `save.schema.json` | 1 | réseau (12) | lobby, qa (09) |
| `road_graph.schema.json` | 1 | cartographe (01) | ia-pnj-trafic (06), gameplay (05) |

Règle : toute modification = PR dédiée, `version` incrémentée, validée par l'orchestrateur. Validation : `python -m pytest qa/unit`.
