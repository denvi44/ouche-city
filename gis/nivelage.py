"""Nivellement des routes (agent 01, cartographe).

Le relief brut (IGN) suit le terrain naturel : une route posée dessus hérite de ses pentes, y compris latérales (dévers
jusqu'à 50 % mesurés rue des Fontaines), et les véhicules glissent, se couchent ou décollent. Une vraie route est
terrassée : profil en long lissé et borné, aucun dévers, talus de raccord avec le terrain.

Méthode, sur une grille globale de 5 m (51 points par tuile, bords partagés) :
  1. relief naturel échantillonné tous les 5 m ;
  2. pour chaque route carrossable, par priorité (grandes routes d'abord, les suivantes se calent sur ce qui est déjà
     nivelé aux carrefours) : profil en long lu sur la grille, lissé (±10 m) puis borné en pente (forward/backward) ;
  3. tous les nœuds de grille à moins de (demi-chaussée + trottoir + 0,8 m) de l'axe prennent la hauteur du profil
     (dévers nul), puis un talus de 7 m se raccorde au terrain (lissage cubique) ;
  4. écriture dans les tuiles (ground.resolution = 51).
Déterministe : aucun hasard, ordre de traitement fixé.
"""
from __future__ import annotations

import math

import numpy as np

RES = 51                                     # points par côté de tuile : un tous les 5 m
BLEND = 7.0                                  # m : largeur du talus de raccord
MARGE = 4.5                                  # m : accotement plat au-delà du trottoir (la grille de 5 m interpole : il faut de la marge)
ORDRE = ["primary", "secondary", "tertiary", "residential", "service", "track"]
PENTE_MAX = {"primary": 0.09, "secondary": 0.09, "tertiary": 0.10, "residential": 0.12, "service": 0.14, "track": 0.18}
PAS_PROFIL = 2.5                             # m : pas d'échantillonnage de l'axe


def _bilineaire(H: np.ndarray, x0: float, z0: float, pas: float, x: np.ndarray, z: np.ndarray) -> np.ndarray:
    nz, nx = H.shape
    gx = np.clip((x - x0) / pas, 0, nx - 1.001)
    gz = np.clip((z - z0) / pas, 0, nz - 1.001)
    i, j = gx.astype(int), gz.astype(int)
    fx, fz = gx - i, gz - j
    top = H[j, i] * (1 - fx) + H[j, i + 1] * fx
    bot = H[j + 1, i] * (1 - fx) + H[j + 1, i + 1] * fx
    return top * (1 - fz) + bot * fz


def _densifier(pts: np.ndarray, pas: float) -> np.ndarray:
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    if s[-1] < 1e-6:
        return pts[:1]
    n = max(int(math.ceil(s[-1] / pas)), 1)
    t = np.linspace(0.0, s[-1], n + 1)
    return np.stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], axis=1)


def _lisser(h: np.ndarray, rayon: int, passes: int = 2) -> np.ndarray:
    if len(h) < 3:
        return h
    k = np.ones(2 * rayon + 1) / (2 * rayon + 1)
    for _ in range(passes):
        pad = np.pad(h, rayon, mode="edge")
        h = np.convolve(pad, k, mode="valid")
    return h


def _borner_pente(h: np.ndarray, pas: float, pente: float) -> np.ndarray:
    """Limite |dh/ds| à `pente` : passes aller-retour qui rabotent les crêtes et comblent les creux."""
    h = h.copy()
    d = pente * pas
    for _ in range(4):
        for i in range(1, len(h)):
            h[i] = min(max(h[i], h[i - 1] - d), h[i - 1] + d)
        for i in range(len(h) - 2, -1, -1):
            h[i] = min(max(h[i], h[i + 1] - d), h[i + 1] + d)
    return h


def _profil_contraint(h_nat: np.ndarray, epingles: np.ndarray, pente: float, pas: float) -> np.ndarray:
    """Profil en long lissé et borné en pente, en respectant les points épinglés (carrefours avec une route déjà nivelée).
    Entre deux épingles, le profil est le relief naturel lissé raccordé aux extrémités ; si l'écart d'altitude demande plus que
    la pente maximale, le profil est linéaire (la route monte ce qu'il faut, le carrefour prime)."""
    n = len(h_nat)
    idx = [i for i in range(n) if not np.isnan(epingles[i])]
    h = _lisser(h_nat, 4)
    if not idx:
        return _borner_pente(h, pas, pente)
    out = h.copy()
    bornes = [0] + idx + [n - 1]
    bornes = sorted(set(bornes))
    for a, b in zip(bornes[:-1], bornes[1:]):
        ha = epingles[a] if not np.isnan(epingles[a]) else h[a]
        hb = epingles[b] if not np.isnan(epingles[b]) else h[b]
        m = b - a
        if m <= 0:
            continue
        lin = np.linspace(ha, hb, m + 1)
        if abs(hb - ha) >= pente * pas * m * 0.98:
            out[a:b + 1] = lin
            continue
        # relief lissé, recalé linéairement sur les extrémités, puis borné en pente avec extrémités fixes
        seg = h[a:b + 1] - np.linspace(h[a], h[b], m + 1) + lin
        d = pente * pas
        for _ in range(4):
            for i in range(1, len(seg)):
                seg[i] = min(max(seg[i], seg[i - 1] - d), seg[i - 1] + d)
            for i in range(len(seg) - 2, -1, -1):
                seg[i] = min(max(seg[i], seg[i + 1] - d), seg[i + 1] + d)
            seg[0], seg[-1] = ha, hb
        out[a:b + 1] = seg
    return out


def _lisse_cubique(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def niveler(tuiles: dict, T: float, sol) -> dict:
    """Remplace le relief de chaque tuile par une grille de RES×RES points avec routes nivelées. Renvoie des statistiques."""
    if not tuiles:
        return {}
    txs = [k[0] for k in tuiles]
    tys = [k[1] for k in tuiles]
    tx0, ty0 = min(txs), min(tys)
    ntx, nty = max(txs) - tx0 + 1, max(tys) - ty0 + 1
    pas = T / (RES - 1)
    nx, nz = ntx * (RES - 1) + 1, nty * (RES - 1) + 1
    x0, z0 = tx0 * T, ty0 * T
    H = np.empty((nz, nx))
    verrou = np.zeros((nz, nx), dtype=bool)      # nœuds de chaussée déjà nivelés : une route suivante ne les modifie plus
    for j in range(nz):
        for i in range(nx):
            H[j, i] = sol(x0 + i * pas, z0 + j * pas)

    routes = []
    for t in tuiles.values():
        for r in t["roads"]:
            if r["kind"] in PENTE_MAX and len(r["points"]) >= 2:
                routes.append(r)
    routes.sort(key=lambda r: (ORDRE.index(r["kind"]), r["id"], r["points"][0]))
    nivelees = 0
    deja: list = []        # axes déjà nivelés : (points, demi-largeurs)
    for r in routes:
        axe = _densifier(np.array(r["points"], dtype=float), PAS_PROFIL)
        if len(axe) < 2:
            continue
        h = _bilineaire(H, x0, z0, pas, axe[:, 0], axe[:, 1])
        # Carrefours : les points de l'axe collés à une route déjà nivelée gardent la hauteur de cette route.
        epingles = np.full(len(axe), np.nan)
        if deja:
            autres = np.concatenate([a[0] for a in deja])
            larg = np.concatenate([a[1] for a in deja])
            for i, p in enumerate(axe):
                d = np.hypot(autres[:, 0] - p[0], autres[:, 1] - p[1])
                if d.min() < 1.5:                 # vrai carrefour : les deux axes se touchent
                    epingles[i] = h[i]
        h = _profil_contraint(h, epingles, PENTE_MAX[r["kind"]], PAS_PROFIL)
        coeur = float(r["width"]) / 2.0 + float(r.get("sidewalk", 0.0)) + MARGE
        reach = coeur + BLEND
        minx, maxx = axe[:, 0].min() - reach, axe[:, 0].max() + reach
        minz, maxz = axe[:, 1].min() - reach, axe[:, 1].max() + reach
        i0 = max(int(math.floor((minx - x0) / pas)), 0)
        i1 = min(int(math.ceil((maxx - x0) / pas)), nx - 1)
        j0 = max(int(math.floor((minz - z0) / pas)), 0)
        j1 = min(int(math.ceil((maxz - z0) / pas)), nz - 1)
        if i1 < i0 or j1 < j0:
            continue
        gi, gj = np.meshgrid(np.arange(i0, i1 + 1), np.arange(j0, j1 + 1))
        px = x0 + gi * pas
        pz = z0 + gj * pas
        best_d = np.full(px.shape, np.inf)
        best_h = np.zeros(px.shape)
        for k in range(len(axe) - 1):
            a, b = axe[k], axe[k + 1]
            ab = b - a
            l2 = float(ab @ ab)
            if l2 < 1e-9:
                continue
            t = np.clip(((px - a[0]) * ab[0] + (pz - a[1]) * ab[1]) / l2, 0.0, 1.0)
            qx, qz = a[0] + t * ab[0], a[1] + t * ab[1]
            d = np.hypot(px - qx, pz - qz)
            mieux = d < best_d
            best_d = np.where(mieux, d, best_d)
            best_h = np.where(mieux, h[k] * (1 - t) + h[k + 1] * t, best_h)
        w = np.where(best_d <= coeur, 1.0, _lisse_cubique(1.0 - (best_d - coeur) / BLEND))
        w = np.where(np.isfinite(best_d), w, 0.0)
        fen = H[j0:j1 + 1, i0:i1 + 1]
        lock = verrou[j0:j1 + 1, i0:i1 + 1]
        w = np.where(lock, 0.0, w)
        H[j0:j1 + 1, i0:i1 + 1] = fen * (1 - w) + best_h * w
        verrou[j0:j1 + 1, i0:i1 + 1] = lock | (best_d <= coeur)
        deja.append((axe, np.full(len(axe), float(r["width"]) / 2.0)))
        nivelees += 1

    # Écriture dans les tuiles (les bords partagés ont les mêmes valeurs).
    for (tx, ty), t in tuiles.items():
        base = t["ground"].get("baseAltitude", 0.0)
        ox, oz = (tx - tx0) * (RES - 1), (ty - ty0) * (RES - 1)
        bloc = H[oz:oz + RES, ox:ox + RES]
        t["ground"] = {"resolution": RES, "baseAltitude": base, "heights": [round(float(v), 2) for v in bloc.reshape(-1)]}
    return {"routes_nivelees": nivelees, "pas_m": pas}
