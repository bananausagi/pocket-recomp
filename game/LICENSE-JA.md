# 日本語ROM対応版の配布構成・出典

Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC
(https://github.com/bryanthaboi/gen1recomp)

非公式の日本語ROM対応版です。本家や各権利者による配布・承認を示すものではありません。
この文書は同梱物の条件を案内するもので、原文のライセンスを変更したり、配布全体の適法性を保証したりするものではありません。

## エンジンと対応ソース

取り込み元は本家 `v0.2.66` / `d70ef7c40e4166b82ed8da692423f010f4406e1b` です。
エンジンの条件は `LICENSE.MD` に保存した GPLv3 と本家の追加条項を参照してください。
原作者の著作権表示・許諾文・必須の出典表示を維持します。
バイナリを再配布する際は、そのバイナリに対応する改変ソース、同梱依存物のソース、ビルド・インストール手順も受領者に提供してください。
ソースが古い版のものだったり、実際のバイナリを構成する変更が欠けていたりする状態では、対応ソースの提供にはなりません。

## 起動画面の置換

本版では新しい起動画面を実装し、従来の起動画面のコードの流用をやめています。
`LICENSE.MD` が本家専有ランチャーとして列挙する旧UIコード・画像は配布に含めません。
エンジンとの呼び出し互換性を維持するため、次の3モジュールには同じパスで本版の新しい実装を置いています。同名であっても本家の旧実装ではありません。

- `src/import/LauncherView.lua`：本版で新規実装
- `src/import/LauncherSettings.lua`：本版で新規実装
- `src/mods/LauncherMods.lua`：本版で新規実装

次の旧モジュール・画像ディレクトリは削除しています。

- `src/import/OnlinePanel.lua`
- `src/import/CartLabelArt.lua`
- `src/import/CartShape.lua`
- `assets/launcher/`、`assets/labels/`

`src/import/RomImporter.lua` は、上流が GPL 対象と明記した ROM 取り込み・検証・キャッシュ抽出処理を利用し、起動画面のUIを新規実装に置き換えています。
置換画面にも本家指定の英文クレジットを表示します。本家のロゴ・ブランド画像は使用しません。
`licenses/UPSTREAM-MIT-bdfac727.txt` は旧版由来コードの許諾履歴を残すための文書です。
本家の現行専有ランチャーを使用できるという説明や、今回のランチャーの根拠として扱うものではありません。

## 同梱 MOD

各 MOD の原文許諾は `vendor/jp-mods/<MOD>/LICENSE*` または `License`、日本語版の変更記録は同じディレクトリの `JP-ADAPTATION.md` を参照してください。
アプリ内の `assets/jp-mods/*.zip` にも各 MOD の許諾文を収録します。

| MOD | 作者 | 同梱物の条件 |
| --- | --- | --- |
| Dramaless Shape | Stahltier と各貢献者 | MIT。詳細な帰属は同梱 LICENSE・README を参照 |
| Running Shoes | MadeinTaly | コードは MIT。原作者のアートは **CC BY-NC-SA 4.0** |
| EriLab Bottomless Bag | EriLab | MIT |
| Shiny Pokemon | masterwebx | MIT |
| Access PC Anywhere | masterwebx | MIT |
| Controller Rumble | masterwebx | MIT |
| All Pokemon Catchable 151 | Wowabox (Darklinkduck) | MIT |

Running Shoes を「全体が MIT」「商用利用に制限なし」と案内しないでください。
原作者の `LICENSE-ART.md` は、スプライト・パターン・画像のほか、Lua の描画コードで生成するアートも対象にしています。
CC BY-NC-SA 4.0 の対象物は、作者・出典・ライセンス・変更の表示を維持し、非営利条件に従う必要があります。改変アートを共有する場合は同ライセンスまたは認められた互換条件を確認してください。
単に効果を OFF にしても、配布ファイルからアートを除いたことにはなりません。
原作者が別途指定する第三者アートが含まれる場合は、その個別条件が優先します。

- Running Shoes: https://github.com/MadeinTaly/gen1recomp-running-shoes
- CC BY-NC-SA 4.0: https://creativecommons.org/licenses/by-nc-sa/4.0/
- 条文: https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode.en

## フォント・スキン・ネイティブライブラリ

| 素材 | 作者・出典 | 条件 |
| --- | --- | --- |
| Noto Sans JP Regular | Adobe / Google Fonts | SIL OFL 1.1。可変フォントをウェイト400に固定して同梱。原文許諾・変更情報は `assets/fonts/noto/` |
| Plain Pixel Font 0.009 | Douglas Vautour (Burpy Fresh) | CC BY 4.0。フォント本体は未改変 |
| Latin 8×8 font / atlas | Daniel Hepper、Marcel Sondaar、IBM | Public Domain。`font8x8_basic.h` からアトラスを生成 |
| gb_anim、tv_crt スキン | libretro common-overlays の各貢献者 | CC BY 4.0。個別 README の出典・変更情報を保持 |

出典 URL・条件の詳細は `licenses/THIRD-PARTY-ASSETS.md` にまとめています。
CC BY 4.0 の素材も MIT や GPL に許諾を変更したわけではありません。
LÖVE とネイティブライブラリの全文許諾・著作権表示は `THIRD_PARTY_NOTICES.txt` および
`mobile/android/app/src/main/assets/THIRD_PARTY_NOTICES.txt`、各依存物のソース内に保存しています。

## ROM・ゲーム素材

配布物に元 ROM、ROM から抽出したキャッシュ、利用者のセーブ、署名秘密鍵を含めません。
ゲーム内容は利用者の端末で本人が用意した対応 ROM から読み込みます。
エンジンや MOD のライセンスは、ゲームの画像・音楽・名称・商標など第三者の権利について許諾を与えるものではありません。
