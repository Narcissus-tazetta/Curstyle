# Phase 1 エンジン(macOS 27.2 / arm64)

`CursorKit`(ライブラリ)と `curstyle`(CLI)の仕様と、実機で確かめた結果。

## 構成

| ファイル | 役割 |
| --- | --- |
| `Sources/CursorKit/CGSBackend.swift` | `CursorBackend` プロトコルと非公開 API 経路(`CCursorBridge` の dlsym)。失敗注入用の `FaultInjectingBackend` |
| `Sources/CursorKit/CursorCatalog.swift` | 対象の名前の表、テーマのキー → 登録名の解決、別名 |
| `Sources/CursorKit/CursorRep.swift` | 1カーソルの内容(size / hotspot / フレーム / 解像度別画像)、内容ハッシュ、テーマ画像の検証 |
| `Sources/CursorKit/CursorTheme.swift` | テーマ(`theme.json` + PNG)の読み込みと、適用計画の解決 |
| `Sources/CursorKit/Snapshot.swift` | 標準画像のスナップショットとジャーナルのディスク保存、排他ロック |
| `Sources/CursorKit/Engine.swift` | トランザクション適用(`CursorEngine`)と、独立した復元経路(`Recovery`) |
| `Sources/CursorKit/SystemReset.swift` | スナップショットを使わずに OS の標準へ戻す最終手段 |
| `Sources/CursorKit/Diagnostics.swift` | 自己診断 |
| `Sources/curstyle/` | CLI と目視確認用のテストテーマ |

保存先は `~/Library/Application Support/Curstyle/`(`snapshot/manifest.json` と PNG、`journal.json`、`lock`)。環境変数 `CURSTYLE_HOME` で変えられる(試験用)。

## CLI

```
curstyle diagnose                 自己診断。問題があれば終了コード 1
curstyle status                   名前ごとの状態(標準 / テーマ適用中 / 不明)
curstyle snapshot                 現在の標準画像を取り込む(適用はしない)
curstyle apply --test [arrow,ibeam,link] [--animated]
curstyle apply <theme-dir>
    --fail-after N                N 回の登録の後、次の登録を1回だけ失敗させる
    --kill-after N                N 回の登録の後、SIGKILL する
curstyle restore                  スナップショットから標準へ戻す
curstyle reset-system             スナップショットを使わずに OS の標準へ戻す
```

## 対象の名前

- スナップショット・復元: `com.apple.coregraphics.{ArrowS, IBeamS, Move, Wait, IBeamXOR, Alias, Copy, ArrowCtx, Empty}` と `com.apple.cursor.0〜43` の53件。
  - `Arrow` / `IBeam` は読み戻すと `ArrowS` / `IBeamS` の内容が返り、登録しても効かないので含めない。
  - `GlobalCurrent` / `ConnectionCurrent` は「いま表示中のカーソル」を返す動的な値なので含めない。
- テーマのキー: `arrow` → `ArrowS`、`ibeam` → `IBeamS`、`pointingHand` / `link` → `cursor.13`(この3つは目視で確認済み)。`cursor.N`、および `CursorCatalog.roleNames` の役割名(`OpenHand` / `ResizeLeftRight` など)も受け付ける。役割名は AccessibilityFoundation の `+[_AXFMouseCursorGenerator _nameForCursor:]` が返す対応表と、AppKit の各 `NSCursor` ファクトリに `-_coreCursorType` を問い合わせた結果から取った。重なる番号はすべて一致する。目視では確かめていない。
- 標準画像がピクセル単位で同一の `cursor.7 = 8`、`cursor.9 = 10` は、片方だけ定義されても両方に当てる。
- `CGSCursorNameForSystemCursor` の表が macOS 27.2 と変わったら、診断で警告する。表に無い名前は標準のまま残る。

## スナップショットとジャーナル

- 適用の前に必ずスナップショットを更新する。名前ごとに「現在の内容が、前回自分が適用した内容(ジャーナルの `intended`)と同じなら、前のスナップショットを残す。違えば現在の内容を新しい標準として取り込む」。標準画像はログイン時と色変更時で異なるため、ハッシュの完全一致で「標準か」を判定しない。
- 自分の適用内容のままなのにスナップショットが無い名前があれば、適用を拒否する(テーマを標準として取り込まないため)。
- 他のカーソルアプリが書き換えた状態は区別できない(既知の制約)。
- 画像は sRGB RGBA8 に描き直して PNG で保存し、保存後に読み直してハッシュが一致しなければ置き換えない。取得時の OS バージョン・`cursorIsCustomized`・ポインターサイズも名前ごとに残す。
- ジャーナルは登録の前に `applying` と登録予定のハッシュを書き、完了で `applied`、標準へ戻れば `clean` にする。強制終了で `applying` のまま残ると、診断が `restore` を促す。
- 内容ハッシュは size・hotspot・フレーム数・フレーム間隔・全画像のピクセルから作る。フレーム間隔は WindowServer が Float32 で保持する(0.1 を登録すると 0.10000000149 が返る)ので、Float32 に丸めてから比べる。

## 適用(トランザクション)

1. テーマを検証する(フレーム数 1〜24、size 1〜256pt、hotspot が size の内側、画像寸法が size の整数倍 × フレーム数、倍率の重複なし、1x か 2x が必須)。1つでも不正なら何も登録しない。
2. スナップショットを更新し、ジャーナルを `applying` にする。
3. 名前ごとに登録 → 読み戻し → ハッシュ照合。
4. 1つでも失敗したら、ジャーナルにある全名前(前のテーマの分も含む)をスナップショットへ戻す。前のテーマと今回の途中までが混ざった状態は残さない。
5. 前のテーマにあって今回のテーマに無い名前は標準へ戻す。
6. 読み戻しの一致は表示の証拠ではないので、CLI は目視確認を促す。

`cursorIsCustomized=1` のときは、手順 2 のスナップショット更新で拒否し、何も登録しない(`snapshot` コマンドも同じ)。この状態ではテーマが表示されないうえ、色付きの画像を標準として取り込み、色をリセットするとシステムが `ArrowS` / `IBeamS` / `cursor.13` を上書きするため(docs/PHASE2.md)。

## 復元

- `restore` はテーマのコードを通らない。現状がスナップショットと同じ名前には触らない。1つ失敗しても残りは続け、名前ごとに結果を返す。全件成功でジャーナルを `clean` にする。
- スナップショットで未登録だった `cursor.N` は、削除したうえで `CoreCursorSet` を呼び、HIServices に標準画像で登録し直させる。削除だけだと、そのカーソルをすでに使ったアプリは名前で設定し続け、矢印になる(指差しで実測)。未登録の `cursor.N` はアプリが初めて使うときに HIServices が登録するものなので、状態表示では標準として扱う。

## reset-system(スナップショットなしの最終手段)

ポインター色を標準に戻したときにシステムが行う再登録を、設定を書き換えずに呼び出す。

1. AccessibilityFoundation の `AXFCursorUnregisterAll()` を呼ぶ。同フレームワーク内蔵の標準画像を `Arrow` / `ArrowS` / `IBeam` / `IBeamS` に登録し、`com.apple.accessibility.cursor.*` と `com.apple.cursor.13` を削除する。引数なしで、設定は読み書きしない(逆アセンブルで確認)。
2. `CoreCursorUnregisterAll` で `cursor.0〜43` を消し、`CoreCursorSet(cid, N)` で HIServices に標準画像を登録し直させる。リセット前に登録されていた名前が登録し直せなければ、失敗として報告する。
3. `cursorIsCustomized=1` のときは実行しない(標準色の画像を登録し、利用者の色設定と食い違うため)。

戻る `ArrowS` / `IBeamS` は「色リセット直後の標準」で、ログイン時の標準(SkyLight 内蔵)とは少し異なる。`cursor.N` は HIServices の同じ画像なので、ログイン時と完全に一致した。

## 実機で確かめたこと(2026-11-08、ユーザーの目視つき)

| 試験 | 読み戻し | 目視 |
| --- | --- | --- |
| Arrow・IBeam・指差しにテスト画像を適用 | 3件一致 | 3つとも変わった |
| `restore` | 53件すべてスナップショットと一致 | 標準に戻った |
| アニメ版(8フレーム・0.1秒、1x/2x)を適用 | 初回は不一致で自動ロールバック(フレーム間隔の Float32 丸め)。修正後は一致 | 静止中も動き続け、形も正常 |
| アニメ適用中に静止版を適用し、3件目で失敗を注入 | ロールバックで53件すべて標準 | 標準に戻った |
| 2件目の登録の後に SIGKILL | ジャーナルが `applying` のまま残り、診断が検知 | 矢印と I だけ変わり、指差しは標準(想定どおり) |
| その後 `restore` | 53件すべて一致 | 標準に戻った |
| 不正なテーマ5種(hotspot 範囲外・画像寸法不一致・30フレーム・未知のキー・同じ名前への二重指定) | すべて登録前に拒否、状態は変化なし | — |
| テスト画像適用 → `reset-system`(初版、`cursor.N` を削除したまま) | `cursor.N` が未登録 | **指差しが矢印になった** → `restore` で復旧 |
| テスト画像適用 → `reset-system`(修正版) | `cursor.N` 48件がスナップショットと一致、`ArrowS` / `IBeamS` は色リセット時の標準 | 3つとも標準 |
| スナップショットで `cursor.13` を未登録にした複製で、指差しを適用 → `restore` | HIServices の標準で登録し直され、本来のスナップショットと一致 | 標準の指差し |

## 確かめていないこと

- `apply <theme-dir>`・`cursorIsCustomized=1` の拒否・`cursor.13` 以外の `cursor.N` は Phase 2 で確かめた(docs/PHASE2.md)。
- 再起動後、スリープ復帰後、ポインターのサイズ変更時、複数ディスプレイ。
- `reset-system` がスナップショット取得後に OS 側の画像が変わった場合でも正しいか(ログイン後に1回だけ試した)。
