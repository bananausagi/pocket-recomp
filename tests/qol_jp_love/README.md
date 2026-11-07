# 原版 Quality of Life 1.3.0 の日本語環境テスト

作者の未改変 ZIP を外部から指定する ROM-free の実 LÖVE テストです。
作者の MOD ソース・ZIP は配布ソースに含めません。
固定配布 URL と SHA-256 は `fixture.json` の `qol` 欄に記録しています。

```sh
python3 tools/run_qol_jp_qa.py --love /path/to/love \
  --qol-zip /outside/source/quality_of_life-1.3.0.zip \
  --output /outside/source/verification/qol
```

Linux の画面なし環境では `SDL_VIDEODRIVER=offscreen LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null` を指定します。
展開した LÖVE AppImage を使う場合は、その `lib` ディレクトリを `LD_LIBRARY_PATH` に指定します。

通常の対象は `fixture.json` でハッシュを固定した **jp.5由来の6MOD＋原版QoL** です。
現在の同梱catalogに他のMODが増えても、追加MODは自動では試験へ入りません。
手書きマップ・ポケモン定義・公開フォントのテスト用画像だけを使用します。

**jp.6のAll151＋原版QoLを含む8MOD共存** は `--with-catchable` を追加し、
出力先を別ディレクトリにします。All151も版番号・SHA-256・現catalogとの一致を確認します。

```sh
python3 tools/run_qol_jp_qa.py --love /path/to/love \
  --qol-zip /outside/source/quality_of_life-1.3.0.zip \
  --with-catchable --output /outside/source/verification/qol-with-catchable
```

2026-09-20: 54チェック成功。ロード、game.ready、XP計算と描画、捕獲済マーク、
設定のON/OFF、設定画面、日本語地名、既存3D地形描画、原版全11ファイルのバイト一致を確認しました。
XP・捕獲済マーク・地名は初期OFFです。設定ラベルは主に英語のままです。

同日: All151を追加した8MODで57チェック成功。同じ描画・設定・地名テストに加え、
QoLの戦闘イベント後もAll151の進化・道具変更が保たれることを確認しました。

実ROM・Android実機、全HM/釣り操作、長時間プレイ、
3D戦闘HUDの全配置は未検証です。原版の専用HUD連携探索は `DRAMATIC_SHAPE` のみを名指しします。
テスト成功はMODの再配布許諾を示すものではありません。
