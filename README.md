# ポケットリコンプ — BoundaryFix

日本語版を含む対応ゲームを、利用者が用意したROMから取り込んで動かすPocket Recompのソースsnapshotです。jp.65 Crystal betaの実配布物を基準に修正しています。

**公開準備中の候補です。** OS選択・通知・一般I/Oと混在UIを独自adapterへ置換しました。ROM backendの残存一致は明示的allowlist、短い定義/API呼出しは別分類です。元ゲームの権利まで保証するものではありません。

Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)

## 使い方

公開後は、このrepoのReleasesにあるAPKを使用してください。Androidのarm64-v8a / x86_64を対象としています。ROM・抽出済みゲーム素材・セーブ・個人設定は同梱していません。

1. 大切なセーブを先に書き出して保管してください。
2. APKをインストールし、起動画面から対応するROMを選択して取り込みます。対応版はROMのhashで判別します。
3. MOD、設定、保存スロットは起動画面から操作できます。今回のcache変更で再取込を要求された場合も、元のセーブを削除する必要はありません。

登録対象は英語版Red / Blue / Yellow / Gold / Silver、日本語版の赤・金・銀・クリスタルです。英語CrystalとFireRedはこの配布範囲に含みません。全登録版・全機種での動作を確認したものではありません。

候補APKの識別値:

```text
SHA256 c42b65cf7cbdba9e7744886b7922e6321a92aea0148cc727783d3b603266dad2
applicationId org.gen1recomp.japanese.preview.audit.stage29
versionCode 68
versionName 0.2.68-jp.65-audit.stage29
```

レビュー用の署名を使用しています。既存版と署名が異なる場合、上書きインストールはできません。セーブの書出し・移行を確認してから利用してください。

## このsnapshotの内容

履歴を含めない、当該APKに対応する7,135ファイルです。元の私有repo全体を公開するものではありません。

| 配置 | 内容 |
| --- | --- |
| `runtime/` | `game.love`に対応するLua・同梱MOD・必要素材・通知 |
| `android-source/` | Android wrapper、nativeソース、Gradle設定と固定検証情報 |
| `mod-source/` | 同梱MODのpreferred source |
| `dependencies/` | 対応依存のsources JAR / POM |
| `dialogue-build/` | runtime再構築、依存取得、APK構築、自己署名の手順 |
| `lgpl-replacement/` | LGPLライブラリ差替えの補助資料 |
| `notices/` | 元projectのライセンス（第三者通知は `runtime/licenses/`） |

各ファイルのSHA256・容量・component・ライセンス分類は [SOURCE-MANIFEST.json](SOURCE-MANIFEST.json) にあります。`.gitattributes`で改行変換とfilterを無効にし、最終配布ソースのバイトを維持しています。LFSは使用しません。

```sh
python3 VERIFY-SOURCE.py
```

この検証はソースのバイト一致を確認するもので、再配布許諾や法的安全を証明するものではありません。

## 再ビルド

詳細は [再ビルド・差替え手順](dialogue-build/PUBLIC-SOURCE-README-JA.txt) を参照してください。Linux / WSL、JDK 17、Python 3、make / gcc / clang、LuaJIT、unzip / zipを使用します。Android SDKの固定入力はplatform 36、Build Tools 35.0.0、NDK 30.0.16248370です。

```sh
export JAVA_HOME=/path/to/jdk17
export PATH="$JAVA_HOME/bin:$PATH"
export SDK=/path/to/android-sdk
export SOURCE_ROOT="$PWD"
export NEW_GRADLE_HOME=/path/to/new-gradle-cache

bash dialogue-build/FETCH-DEPENDENCIES.sh "$SDK" "$NEW_GRADLE_HOME"
export GRADLE_USER_HOME="$NEW_GRADLE_HOME"
bash dialogue-build/BUILD-FROM-SOURCE.sh "$SDK" /path/to/new-luajit-scratch
```

scratchは存在しない新規パスを指定します。ビルドは1ワーカー・低優先度で動き、署名やインストールは行いません。出力は `android-source/mobile/android/app/build/outputs/apk/embedNoRecord/release/` 以下です。

**新規依存cacheの注意:** 依存取得taskだけではAAPT2 `8.9.2-12782657` のLinux用ツールが不足する場合があります。上記の詳細手順末尾に、native出力を保持し、固定checksumのstrict検証を維持してonlineで組立を再開する正確なコマンドを記載しています。checksum検証の無効化・検証情報の自動更新で回避しないでください。

runtimeだけの再構築:

```sh
python3 dialogue-build/BUILD-RUNTIME.py runtime runtime-rebuilt.love
```

監査対象runtimeのSHA256は `e8465b655ca6237dbf4e8a10c579391e428d7d7e2442e1e11bf6612e5d79ce47` です。意図してLuaを変更した場合は、その変更を確認してmanifest/layoutを自分の版に更新してください。

## ライブラリの変更・差替えと自己署名

`android-source/mobile/android/love/src/jni/mpg123-1.17.0/`、`openal-soft/` 等を変更し、上記手順で再構築できます。関連するLICENSE / COPYINGとヘッダーを保持してください。

```sh
bash dialogue-build/SIGN-OWN-KEY.sh "$SDK" "$UNSIGNED_APK" "$YOUR_KEYSTORE" "$NEW_OUTPUT_APK"
```

自分の鍵を使用してください。署名秘密鍵は提供していません。このスクリプトは16KB配置と署名検証を行い、端末のアプリを削除・インストールしません。

## ライセンス・帰属

- [元projectのGPLv3と追加条件](notices/LICENSE.MD)、[nativeの第三者通知](runtime/licenses/NATIVE-THIRD-PARTY-NOTICES.txt)、[フォント・スキン・MODアートの通知](runtime/licenses/THIRD-PARTY-ASSETS.md)、各componentのLICENSE / COPYINGを参照してください。
- 元projectのLauncher UIはGPLの対象から除外されています。OS選択・通知・一般I/O・混在UIを独自adapterへ置換し、保持するROM検証・抽出/cache処理を [boundary-evidence.json](dialogue-build/boundary-evidence.json) のallowlistで明示しています。独自launcherでも上記の帰属表示が必要です。
- 7MODのMITコードと、Running Shoesの独自アートに適用されるCC BY-NC-SA 4.0を区別しています。アートの非営利・帰属・同条件の条件を含め、全体を一律に商用再配布自由とは説明していません。
- LÖVE / SDL、LuaJIT、mpg123、OpenAL、フォント等はそれぞれの条件に従います。個別通知を削除しないでください。
- このprojectのライセンスは、元ゲームのコード・素材・名称・商標の権利を付与するものではありません。公開disassemblyやROM取込方式だけで原権利者の許諾があるとは判断していません。
- APKを再配布する場合は、対応ソースの取得方法も提供してください。

## 同梱通知の旧参照先と現在の配置

既存の許諾文・帰属を保ったままソースを配置しています。同梱通知が旧パスを示す場合は、以下の現配置を参照してください。

| 旧参照先 | このsnapshotの配置 |
| --- | --- |
| `vendor/jp-mods/<MOD>/` | [mod-source/](mod-source/) 内の各MOD（LICENSE・変更記録を含む） |
| `THIRD_PARTY_NOTICES.txt` | [nativeの第三者通知](runtime/licenses/NATIVE-THIRD-PARTY-NOTICES.txt) |
| `mobile/android/app/src/main/assets/THIRD_PARTY_NOTICES.txt` | [Android同梱通知](android-source/mobile/android/app/src/main/assets/THIRD_PARTY_NOTICES.txt) |
| `corresponding-source-file-list.json` | [SOURCE-MANIFEST.json](SOURCE-MANIFEST.json) |

`runtime/licenses/LAUNCHER-PROVENANCE.txt`の12＋6メソッドは前段の置換履歴です。BoundaryFixの最終範囲は [boundary-evidence.json](dialogue-build/boundary-evidence.json) のallowlistと独自adapterの記録を参照してください。既存ライセンス文書の権利条項・帰属は変更していません。

## 検証と未検証事項

前版LauncherFixで構築・検証した両ABIのnativeとDEXをバイト一致で維持し、今回のruntimeを再構築しました。APKの署名v1/v2/v3、APK配置とELFの16KB対応、runtimeの一致を確認しました。日本語赤・金銀の重点操作、ROM取込、保存復帰、日本語設定、実7MODの削除・再取込と設定保存、picker系6試験、controller契約13項目を確認しています。

旧upstream由来のZIP/影MOD fixture試験2本は旧候補でも同じ失敗です。これらを全通過とは扱っていません。Android実機、英語金銀実ROM、日本語金銀1.1実ROMでの操作は未検証です。Crystalの描画・男女進行等は前段階の検証結果を引き継ぎます。

検証は互換性や法的安全の保証ではありません。

BoundaryFix追加検証: 新規adapter18項目、picker6系列、controller13項目、日本語金の新規ROM取込/通常導入/戦闘/保存復帰、日本語赤の重点回帰、7MOD再取込・設定14往復・日本語ラベル100件。Android実機および実OS chooserの対話操作は未実施です。
