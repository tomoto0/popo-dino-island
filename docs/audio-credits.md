# ステージBGMの出典とクレジット

## ライセンス

24ステージのBGMには、OpenGameArt の **[42 "Monster RPG 2" music tracks](https://opengameart.org/content/42-monster-rpg-2-music-tracks)** を使用しています。

- **出典ページ:** https://opengameart.org/content/42-monster-rpg-2-music-tracks
- **配布アーカイブ:** [Monster RPG 2 OGG Music - Revised.7z](https://opengameart.org/sites/default/files/Monster%20RPG%202%20OGG%20Music%20-%20Revised.7z)
- **ページ上の作者表記:** troutsneeze
- **原曲のゲーム:** Monster RPG 2 / Nooskewl Games
- **ライセンス:** [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/deed.ja)（パブリックドメイン）

OpenGameArt の配布ページでは、Monster RPG 2 の楽曲（`jungle_ambience` を除く）を CC0 として再ライセンスしていること、Nooskewl Games への謝辞は任意であることが説明されています。法的な表示義務はありませんが、本ゲームでは出典を明示します。

## 割り当て

各コースは別のOgg Vorbisファイルを再生します。ボス戦に入っても、そのコース専用曲を続けて再生します。

| ステージ | コース名 | 使用ファイル | ねらい |
| --- | --- | --- | --- |
| 1-1 | ポポのおさんぽ道 | `jungle.ogg` | 明るい草原の冒険の出発 |
| 1-2 | どんぐりの丘 | `beach.ogg` | ひだまりと水辺のある丘 |
| 1-3 | はらっぱブロック | `happtroll.ogg` | ブロック遊びに合う軽快さ |
| 1-4 | 草原のとりで | `battle.ogg` | 初めてのとりでの緊張感 |
| 2-1 | ひだまり坂 | `seaside_repaired.ogg` | 開放的な高原の道 |
| 2-2 | トゲトゲ野原 | `Flowey.ogg` | 少し不思議で慎重になる野原 |
| 2-3 | ゆらゆら丸太橋 | `loadsave.ogg` | 木橋を渡るリズミカルな場面 |
| 2-4 | 高原のとりで | `boss.ogg` | 高原のボス戦 |
| 3-1 | キラキラ洞くつ | `underground.ogg` | 地下の広がりと探索感 |
| 3-2 | コウモリの住みか | `moon.ogg` | 暗い洞くつの神秘感 |
| 3-3 | 大砲トンネル | `chase.ogg` | 大砲を避けて進むスピード感 |
| 3-4 | 洞くつのとりで | `fortress.ogg` | 岩のとりでの緊張感 |
| 4-1 | 雲の上のさんぽ | `mountains.ogg` | 高い空と遠くの景色 |
| 4-2 | くずれる雲の橋 | `moon2.ogg` | 不安定な足場を渡る浮遊感 |
| 4-3 | バネバネ空中庭園 | `shmup2.ogg` | 空中を連続で跳ねる疾走感 |
| 4-4 | 天空のとりで | `Muttrace.ogg` | 天空での対決に合う高揚感 |
| 5-1 | まよいの森の入口 | `forest.ogg` | 深い森へ入る探索感 |
| 5-2 | オバケの小道 | `shyzu.ogg` | オバケのいる夜道の不穏さ |
| 5-3 | ホネホネの谷 | `monastery.ogg` | 静かな谷と骨の敵の不気味さ |
| 5-4 | 森のとりで | `burned_village.ogg` | 暗い森のとりでの緊張感 |
| 6-1 | マグマの入口 | `volcano.ogg` | 溶岩地帯に入る熱気 |
| 6-2 | 炎の回廊 | `castle.ogg` | 城内を進む長い探索 |
| 6-3 | 大砲とマグマの間 | `title.ogg` | 最終城の重厚な盛り上がり |
| 6-4 | マグマゴーレムの城 | `final_boss.ogg` | 最終ボス戦 |

## ファイルと再現方法

実行時に使うファイルは `assets/game/audio/stages/w1_1.ogg` から `w6_4.ogg` です。いずれも上記アーカイブから未加工でコピーした Ogg Vorbis ファイルです。

再取り込みは、アーカイブを展開したディレクトリを指定して次のコマンドを実行します。

```sh
python3 tools/import_cc0_bgm.py "/path/to/Monster RPG 2 OGG Music - Revised"
```

曲の対応表は `tools/import_cc0_bgm.py` にも固定で記録されています。
