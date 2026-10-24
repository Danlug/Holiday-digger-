#!/usr/bin/env python3
"""walls_deep.py — перерисованные стены-фоны подземного параллакса (ветка «walls»).

Контракт (читает tools/gen_tiles_deep.py; запись перекрывает встроенный paint_wall):

  WALLS = {"roots": fn, "caves": fn, "crystal": fn, "bedrock": fn, "ruins": fn, "hell": fn, "void": fn, "heaven": fn}
      fn() -> numpy float64 (96, 96, 3), RGB 0..255: БЕСШОВНАЯ по обоим краям плитка фона 96x96, тёмная
      (за ней играют, она не должна спорить с руды и героем), по поясу: имя = поле "wall" в data/world_layers.json.
Результат: art/env/deep/wall_<имя>.png.
"""

WALLS = {}
