"""Lecture de gis/config/emprise.toml."""
from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path

GIS_DIR = Path(__file__).resolve().parent
CONFIG_PATH = GIS_DIR / "config" / "emprise.toml"


@dataclass(frozen=True)
class Emprise:
    centre_lat: float
    centre_lon: float
    demi_cote_m: float
    taille_tuile_m: float
    rayon_centre_m: float
    poc_rue: str
    poc_rayon_m: float


def charger(path: Path = CONFIG_PATH) -> Emprise:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    ville = data["ville"]
    return Emprise(
        centre_lat=float(ville["centre"][0]),
        centre_lon=float(ville["centre"][1]),
        demi_cote_m=float(ville["demi_cote_m"]),
        taille_tuile_m=float(ville["taille_tuile_m"]),
        rayon_centre_m=float(data["zones"]["centre_medieval"]["rayon_m"]),
        poc_rue=str(data["poc"]["rue"]),
        poc_rayon_m=float(data["poc"]["rayon_m"]),
    )
