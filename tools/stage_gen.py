#!/usr/bin/env python3
"""Generate the 24 stage JSON files (6 worlds x 4 stages) with a rising difficulty curve.

Deterministic: the same seed always produces the same stages. Run from the project root:
    python3 tools/stage_gen.py
Coordinates: terrain rects are [left, top, width, height]; every other entry uses its centre x
and the y of the surface it rests on (walkers/items) or its centre (fliers/blocks).
Physics budget (config/tuning.json): jump apex ~183 px, full-speed jump distance ~280 px,
flutter adds ~110 px of horizontal reach. Gaps stay <= 240 px and rises <= 140 px.
"""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "stages"
GY = 620
BOTTOM = 900
BLOCK = 52

WORLDS = [
    {"name": "はじまりの草原", "theme": "grass", "music": "overworld", "enemies": ["acorn", "acorn", "beetle"],
     "stages": ["ポポのおさんぽ道", "どんぐりの丘", "はらっぱブロック", "草原のとりで"]},
    {"name": "ひだまり高原", "theme": "plains", "music": "overworld", "enemies": ["acorn", "beetle", "hedgehog", "bat"],
     "stages": ["ひだまり坂", "トゲトゲ野原", "ゆらゆら丸太橋", "高原のとりで"]},
    {"name": "クリスタル洞くつ", "theme": "cave", "music": "cave", "enemies": ["bat", "hedgehog", "beetle", "acorn"],
     "stages": ["キラキラ洞くつ", "コウモリの住みか", "大砲トンネル", "洞くつのとりで"]},
    {"name": "そよかぜ天空", "theme": "cloud", "music": "sky", "enemies": ["bat", "beetle", "acorn", "hedgehog"],
     "stages": ["雲の上のさんぽ", "くずれる雲の橋", "バネバネ空中庭園", "天空のとりで"]},
    {"name": "まよいの森", "theme": "forest", "music": "forest", "enemies": ["ghost", "bat", "hedgehog", "skeleton"],
     "stages": ["まよいの森の入口", "オバケの小道", "ホネホネの谷", "森のとりで"]},
    {"name": "マグマ城", "theme": "castle", "music": "castle", "enemies": ["skeleton", "hedgehog", "ghost", "bat"],
     "stages": ["マグマの入口", "炎の回廊", "大砲とマグマの間", "マグマゴーレムの城"]},
]
BOSS_HP = [2, 3, 4, 5, 6, 8]

# Chunk pools unlocked by world (index 0-based). Later worlds add harder chunks.
POOLS = {
    0: ["flat", "flat", "gap", "steps", "blocks", "hop"],
    1: ["flat", "gap", "steps", "blocks", "hop", "spikes", "moving"],
    2: ["flat", "flat", "gap", "blocks", "hop", "spikes", "moving", "cannon", "pillars"],
    3: ["flat", "gap", "hop", "moving", "falling", "cannon", "pillars", "blocks"],
    4: ["flat", "gap", "hop", "pillars", "spikes", "falling", "blocks", "moving"],
    5: ["gap", "pillars", "spikes", "falling", "cannon", "moving", "hop", "lava_pit"],
}


class Builder:
    def __init__(self, world: int, index: int, d: float, rng: random.Random):
        self.w = world
        self.i = index
        self.d = d
        self.rng = rng
        self.x = 0
        self.floor = GY
        self.data = {k: [] for k in ["grounds", "platforms", "stumps", "blocks", "coins", "medals", "items",
                                      "springs", "enemies", "spikes", "lava", "moving", "falling", "cannons"]}
        self.medal_spots = []
        self.safe_until = 520  # no enemies near spawn
        self.lava_world = world == 5

    # ---- primitives ---------------------------------------------------------------------
    def ground(self, width: int, top: int | None = None):
        top = self.floor if top is None else top
        self.data["grounds"].append([self.x, top, width, BOTTOM - top])
        x0 = self.x
        self.x += width
        return x0, x0 + width, top

    def pit(self, width: int):
        x0 = self.x
        if self.lava_world:
            self.data["lava"].append([x0 - 4, GY + 50, width + 8, BOTTOM - GY - 50])
        self.x += width
        return x0, x0 + width

    def coin_line(self, x0: float, y: float, count: int, spacing: int = 44):
        for k in range(count):
            self.data["coins"].append([round(x0 + k * spacing), round(y)])

    def coin_arc(self, x0: float, x1: float, base_y: float, height: float, count: int = 5):
        for k in range(count):
            t = k / max(1, count - 1)
            x = x0 + (x1 - x0) * t
            y = base_y - height * 4 * t * (1 - t)
            self.data["coins"].append([round(x), round(y)])

    def enemy_type(self):
        pool = WORLDS[self.w]["enemies"]
        # Early stages of a world lean on the world's first enemy types.
        limit = max(1, min(len(pool), 1 + self.i + (1 if self.w > 0 else 0)))
        return self.rng.choice(pool[:limit])

    def place_walkers(self, x0: int, x1: int, top: int, count: int):
        usable = x1 - x0 - 120
        if usable < 120 or count <= 0:
            return
        for k in range(count):
            x = x0 + 60 + usable * (k + 0.5) / count + self.rng.randint(-30, 30)
            if x < self.safe_until:
                continue
            kind = self.enemy_type()
            if kind in ("bat", "ghost"):
                self.data["enemies"].append([kind, round(x), round(top - self.rng.randint(110, 170))])
            else:
                self.data["enemies"].append([kind, round(x), top])

    def density_count(self, length: int) -> int:
        per_1000 = 2.6 + 2.4 * self.d
        expected = length / 1000 * per_1000
        n = int(expected)
        if self.rng.random() < expected - n:
            n += 1
        return n

    def gap_width(self) -> int:
        lo = int(90 + 85 * self.d)
        hi = int(130 + 105 * self.d)
        return self.rng.randint(lo, min(hi, 235))

    # ---- chunks ---------------------------------------------------------------------------
    def chunk_flat(self):
        length = self.rng.randint(420, 720)
        x0, x1, top = self.ground(length)
        self.place_walkers(x0, x1, top, self.density_count(length))
        if self.rng.random() < 0.7:
            self.coin_line(x0 + 80, top - 70, self.rng.randint(4, 6))

    def chunk_gap(self):
        self.ground(self.rng.randint(160, 260))
        g = self.gap_width()
        gx0, gx1 = self.pit(g)
        self.coin_arc(gx0 - 20, gx1 + 20, self.floor - 70, 110, 5)
        if self.d > 0.35 and self.rng.random() < 0.45:
            self.data["enemies"].append(["bat", round((gx0 + gx1) / 2), self.floor - 150])
        if self.lava_world and self.rng.random() < 0.8:
            self.data["enemies"].append(["fire_spirit", round((gx0 + gx1) / 2), GY + 60])
        x0, x1, top = self.ground(self.rng.randint(260, 420))
        self.place_walkers(x0, x1, top, self.density_count(x1 - x0))

    def chunk_steps(self):
        base = self.floor
        steps = self.rng.randint(2, 3)
        rise = self.rng.choice([52, 60, 68])
        for s in range(steps):
            self.floor = max(420, self.floor - rise)
            self.ground(self.rng.randint(130, 170))
        x0, x1, top = self.ground(self.rng.randint(220, 320))
        self.coin_line(x0 + 40, top - 70, 4)
        self.place_walkers(x0, x1, top, 1)
        if self.rng.random() < 0.5:
            g = self.gap_width()
            self.pit(g)
        self.floor = base

    def chunk_blocks(self):
        length = self.rng.randint(540, 700)
        x0, x1, top = self.ground(length)
        count = self.rng.randint(4, 6)
        row_y = top - 146
        start = x0 + (length - count * BLOCK) / 2 + BLOCK / 2
        item_slot = self.rng.randrange(count)
        roll = self.rng.random()
        content = "egg" if roll < 0.35 else "heart" if roll < 0.62 else "coins" if roll < 0.85 else "apple" if roll < 0.95 else "star"
        for k in range(count):
            bx = round(start + k * BLOCK)
            if k == item_slot:
                self.data["blocks"].append([bx, row_y, "item", content])
            elif k % 2 == 0 and self.rng.random() < 0.5:
                self.data["blocks"].append([bx, row_y, "item", "coin"])
            else:
                self.data["blocks"].append([bx, row_y, "brick", ""])
        self.coin_line(start, row_y - 80, count, BLOCK)
        self.medal_spots.append([round(start + (count - 1) * BLOCK / 2), row_y - 190])
        self.place_walkers(x0, x1, top, self.density_count(length))

    def chunk_hop(self):
        self.ground(self.rng.randint(160, 240))
        span_platforms = self.rng.randint(2, 4)
        y = self.floor
        for p in range(span_platforms):
            g = self.rng.randint(int(80 + 50 * self.d), int(120 + 80 * self.d))
            self.pit(g)
            w = self.rng.randint(int(170 - 50 * self.d), int(210 - 50 * self.d))
            y = max(360, min(GY - 30, y - self.rng.randint(-60, 110)))
            px = self.x
            self.data["platforms"].append([px + w / 2, y, w])
            self.coin_line(px + w / 2 - 44, y - 60, 3)
            if self.d > 0.5 and self.rng.random() < 0.35:
                self.data["enemies"].append(["bat", round(px + w / 2), y - 150])
            self.pit(w)
        self.medal_spots.append([round(self.x - 100), y - 170])
        self.pit(self.rng.randint(80, int(120 + 60 * self.d)))
        x0, x1, top = self.ground(self.rng.randint(260, 380))
        self.place_walkers(x0, x1, top, self.density_count(x1 - x0))

    def chunk_moving(self):
        self.ground(self.rng.randint(180, 260))
        span = self.rng.randint(480, int(560 + 200 * self.d))
        w = self.rng.randint(150, 190)
        x0 = self.x
        vertical = WORLDS[self.w]["theme"] in ("cave", "castle") and self.rng.random() < 0.4
        if vertical:
            # Lift that rises from below the floor to a higher ledge.
            self.pit(span)
            self.data["moving"].append([x0 + span / 2, self.floor - 20, w, 0, -140, round(3.2 - self.d, 2)])
            self.floor = max(460, self.floor - 100)
        else:
            self.pit(span)
            self.data["moving"].append([x0 + w / 2 + 30, self.floor - 30, w, span - w - 60, 0, round(3.6 - 0.8 * self.d, 2)])
        self.coin_line(x0 + 80, self.floor - 150, 6, 60)
        if self.d > 0.45:
            self.data["enemies"].append(["bat", round(x0 + span / 2), self.floor - 190])
        x0g, x1g, top = self.ground(self.rng.randint(260, 380))
        self.place_walkers(x0g, x1g, top, 1 if self.d > 0.3 else 0)
        self.floor = GY if self.floor < 520 and self.rng.random() < 0.5 else self.floor

    def chunk_falling(self):
        self.ground(self.rng.randint(160, 240))
        count = self.rng.randint(3, 5)
        for k in range(count):
            self.pit(self.rng.randint(80, int(110 + 60 * self.d)))
            w = 150
            y = self.floor - self.rng.randint(0, 40)
            self.data["falling"].append([self.x + w / 2, y, w])
            self.data["coins"].append([round(self.x + w / 2), y - 60])
            self.pit(w)
        self.pit(self.rng.randint(80, 130))
        x0, x1, top = self.ground(self.rng.randint(260, 360))
        self.place_walkers(x0, x1, top, self.density_count(x1 - x0))

    def chunk_spikes(self):
        length = self.rng.randint(620, 820)
        x0, x1, top = self.ground(length)
        strips = 2 + (1 if self.d > 0.5 else 0)
        for k in range(strips):
            w = self.rng.randint(64, int(96 + 60 * self.d))
            cx = x0 + length * (k + 1) / (strips + 1)
            self.data["spikes"].append([round(cx), top, w])
            self.coin_arc(cx - w / 2 - 50, cx + w / 2 + 50, top - 60, 90, 4)
        if self.d > 0.4:
            self.data["enemies"].append(["bat", round(x0 + length / 2), top - 170])

    def chunk_pillars(self):
        self.ground(self.rng.randint(160, 240))
        count = self.rng.randint(3, 4)
        top = self.floor
        for k in range(count):
            self.pit(self.rng.randint(int(90 + 40 * self.d), int(130 + 70 * self.d)))
            top = max(400, min(GY - 20, top - self.rng.randint(-70, 100)))
            w = 96
            self.data["stumps"].append([self.x + w / 2, top, BOTTOM - top, w])
            self.data["coins"].append([round(self.x + w / 2), top - 60])
            if self.lava_world and self.rng.random() < 0.5:
                self.data["enemies"].append(["fire_spirit", round(self.x - 50), GY + 60])
            self.pit(w)
        self.medal_spots.append([round(self.x - 48), top - 200])
        self.pit(self.rng.randint(90, 140))
        x0, x1, top = self.ground(self.rng.randint(260, 380))
        self.place_walkers(x0, x1, top, self.density_count(x1 - x0))

    def chunk_cannon(self):
        length = self.rng.randint(620, 800)
        x0, x1, top = self.ground(length)
        cx = x0 + length - 120
        # Cannon rests on a two-crate stack so its balls fly at jump/duck height.
        self.data["blocks"].append([round(cx), top - BLOCK / 2, "crate", ""])
        self.data["cannons"].append([round(cx), top - BLOCK, round(3.8 - 1.8 * self.d, 2)])
        self.place_walkers(x0, cx - 120, top, 1 if self.d > 0.4 else 0)
        self.coin_line(x0 + 120, top - 150, 5)

    def chunk_lava_pit(self):
        self.ground(self.rng.randint(160, 220))
        g = min(235, self.gap_width() + 20)
        gx0, gx1 = self.pit(g)
        self.data["enemies"].append(["fire_spirit", round((gx0 + gx1) / 2), GY + 60])
        self.coin_arc(gx0 - 20, gx1 + 20, self.floor - 70, 120, 5)
        x0, x1, top = self.ground(self.rng.randint(280, 420))
        self.place_walkers(x0, x1, top, 1)

    def chunk_spring(self):
        length = self.rng.randint(520, 640)
        x0, x1, top = self.ground(length)
        sx = x0 + 160
        self.data["springs"].append([sx, top])
        ledge_y = top - 330
        self.data["platforms"].append([sx + 150, ledge_y, 240])
        self.coin_line(sx + 60, ledge_y - 60, 5)
        self.medal_spots.append([sx + 240, ledge_y - 70])

    def chunk_checkpoint(self):
        x0, x1, top = self.ground(460)
        self.data["checkpoint"] = [x0 + 230, top]

    def run(self, target_width: int, boss: bool):
        rng = self.rng
        x0, x1, top = self.ground(760)  # safe start runway
        self.data["spawn"] = [150, top]
        self.coin_line(360, top - 70, 5)
        pool = POOLS[self.w]
        mid = target_width * 0.5
        checkpoint_done = False
        spring_done = False
        last = ""
        while self.x < target_width:
            if not checkpoint_done and self.x >= mid:
                self.chunk_checkpoint()
                checkpoint_done = True
                continue
            if not spring_done and self.x >= target_width * (0.3 if boss else 0.62):
                self.chunk_spring()
                spring_done = True
                continue
            kind = rng.choice(pool)
            if kind == last and kind != "flat":
                kind = "flat" if self.w in (0, 1, 4) else rng.choice(pool)
            last = kind
            getattr(self, "chunk_" + kind)()
            self.floor = GY if self.floor > GY else self.floor
            if self.floor < GY and rng.random() < 0.5:
                self.floor = min(GY, self.floor + 60)
        if not checkpoint_done:
            self.chunk_checkpoint()
        if not spring_done:
            self.chunk_spring()
        self.floor = GY
        if boss:
            self.ground(360)
            arena_x = self.x
            arena_w = 1500
            self.ground(arena_w, GY)
            # Tall walls keep the fight inside the arena (the entry wall is a low step).
            self.data["grounds"].append([arena_x + arena_w, -400, 200, BOTTOM + 400])
            self.data["boss"] = {"x": arena_x + arena_w * 0.62, "y": GY, "hp": BOSS_HP[self.w],
                                 "arena": [arena_x, arena_x + arena_w]}
            self.data["goal"] = [arena_x + arena_w - 170, GY]
            self.data["world_width"] = arena_x + arena_w + 200
            self.medal_spots.append([arena_x + 180, GY - 220])
        else:
            x0, x1, top = self.ground(820)
            self.data["goal"] = [x0 + 520, top]
            self.data["world_width"] = x1
        # Three medals per stage, spread out along the course.
        spots = sorted(self.medal_spots, key=lambda p: p[0])
        if len(spots) < 3:
            extra = [[round(target_width * f), 380] for f in (0.25, 0.55, 0.8)]
            spots = sorted(spots + extra[: 3 - len(spots)], key=lambda p: p[0])
        picks = [spots[0], spots[len(spots) // 2], spots[-1]] if len(spots) >= 3 else spots
        seen = set()
        medals = []
        for p in picks:
            key = tuple(p)
            if key in seen:
                continue
            seen.add(key)
            medals.append([round(p[0]), round(p[1])])
        k = 0
        while len(medals) < 3:
            k += 1
            medals.append([round(target_width * (0.2 + 0.2 * k)), 360])
        self.data["medals"] = medals[:3]


def build_stage(world: int, index: int) -> dict:
    n = world * 4 + index
    d = n / 23.0
    rng = random.Random(1000 + n * 7919)
    b = Builder(world, index, d, rng)
    boss = index == 3
    stage_id = f"w{world + 1}_{index + 1}"
    width = int(5200 + 3600 * d)
    if boss:
        width = int(width * 0.62)
    b.run(width, boss)
    data = b.data
    for key in ("coins",):
        data[key] = [c for c in data[key] if 0 < c[0] < data["world_width"]]
    time_limit = 300 if data["world_width"] < 8000 else 350
    stage = {
        "id": stage_id,
        "world": world + 1,
        "index": index + 1,
        "label": f"{world + 1}-{index + 1}",
        "name": WORLDS[world]["stages"][index],
        "world_name": WORLDS[world]["name"],
        "theme": WORLDS[world]["theme"],
        # Every course has its own source track, including each fortress course.
        "music": stage_id,
        "difficulty": round(d, 3),
        "enemy_speed": round(1.0 + 0.45 * d, 3),
        "time": time_limit,
    }
    stage.update(data)
    return stage


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.json"):
        old.unlink()
    index = []
    for w in range(6):
        for s in range(4):
            stage = build_stage(w, s)
            (OUT / f"{stage['id']}.json").write_text(json.dumps(stage, ensure_ascii=False, separators=(",", ":")))
            index.append(stage["id"])
            print(stage["id"], stage["name"], "width", stage["world_width"], "enemies", len(stage["enemies"]),
                  "coins", len(stage["coins"]), "time", stage["time"])
    (OUT / "index.json").write_text(json.dumps({"stages": index, "worlds": [
        {"name": w["name"], "theme": w["theme"]} for w in WORLDS]}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
