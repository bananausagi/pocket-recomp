# ポケットリコンプ（個人用ビルド）

海外の非公式リコンパイル作品 [gen1recomp](https://github.com/bryanthaboi/gen1recomp)（作者 bryanthaboi / BOIS CLUB GAMES）を、日本語版 ROM で遊べるようにした Android 向けの個人用ビルドです。LÖVE 11.5（Lua）製で、ゲーム本体は APK 内の `assets/game.love` です。

これまで jp.57〜jp.91-preview2 と続いてきた「jp 系列」を引き継ぎ、最後の配布版（jp.91-preview2）に未ビルドだった作業分を統合して、単一のビルドラインに作り直しました。今後の更新はこのリポジトリの Releases から配ります。

## 特徴

- 日本語版 ROM 対応（第1世代・第2世代の取り込みとプレイ）
- ランチャーや設定まわりの日本語表示
- タッチ操作、上画面のみ表示するモード
- オプションの 3D 表示（同梱 MOD「DRAMALESS_SHAPE」によるボクセル描画。3D 戦闘背景を含む）
- 起動時の更新チェック（新しい版が出ていればランチャーにバナーで知らせます）

## 入れ方

1. [Releases](https://github.com/bananausagi/pocket-recomp/releases) から `PocketRecomp-personal.apk` をダウンロードします。
2. Android にインストールします（提供元不明アプリのインストール許可が必要です）。
3. 起動して、自分の手持ちの ROM をアプリから取り込みます。

**ROM は同梱・配布していません。** 遊ぶには、利用者自身が用意した ROM が必要です。

## 更新の仕組み

- 新しい版はこのリポジトリの Releases で配布します（APK と `version.json`）。
- アプリは起動時に Releases の `version.json` を確認し、新しい versionCode があればランチャーにバナーを表示します。バナーをタップすると Releases ページが開くので、そこから新しい APK をダウンロードしてインストールしてください（自動で入れ替わることはありません）。

## 注意

- **署名鍵は jp 系列と同じものです。** jp.91-preview2 など旧版の上に、そのまま上書きインストールして更新できます（セーブもそのまま引き継がれます）。本ビルド以降も同じ鍵で署名するので、上書きで更新できます。
- 本ビルドは実機での動作確認をしていません。WIP だった作業分を含むため、問題があれば教えてください。
- 個人で楽しむためのビルドです。

## 開発者向け：構成とビルド

```text
game/        ゲーム本体のソース一式（game.love の中身）
tests/       テスト一式（*_test.lua が 887 本）
tools/       テストゲート（setup_tb.py / run_tests.sh / gate.sh / base.tsv）
mods_src/    同梱 MOD のソース（DRAMALESS_SHAPE 改修版など）
build_deps/  repack_controls.py（AndroidManifest 書換え）
build.py     ビルドスクリプト（個人用の新規鍵で署名する旧版）
build_resign.py 配布用ビルドスクリプト（元の jp 系列の鍵で署名）
version.json 現在の最新版の情報（Releases にも同じものを添付）
```

ビルドは「jp.90 の APK を土台に、game.love だけ差し替えて再署名する」方式です。

```sh
python3 build_resign.py
```

必要なもの： Python 3、JDK 17、Android SDK build-tools（34.0.0 で確認）、土台になる jp.90 の APK（`../base/Pocket-Recomp-jp90-20261022.apk` に配置。SHA-256 はスクリプト内で照合します。リポジトリには含めていません）、署名鍵（元の jp 系列の鍵を `../signing-original/` に保管。リポジトリには含めていません）。

- build.py は game.love を作る際に、ROM・セーブ・署名鍵などのファイルや、ROM から生成されたキャッシュが混入していないことを必ず確認します。
- 16 KB ページアラインは build.py 内蔵のアライナで行います（zipalign -P 16 相当）。
- テスト： `bash tools/gate.sh`（luajit が必要）。tools/base.tsv に記録された既知の失敗（887 本中 100 本）と比べて、新規の失敗がゼロなら合格です。

## ライセンス

エンジンは GPLv3 ＋ 上流の追加条項です。全文は `game/LICENSE.MD` と `game/LICENSE-JA.md` を参照してください。同梱 MOD やフォント等の個別ライセンスも各ファイルに含まれています。
