# Phase 0 実測結果(macOS 27.2 / arm64)

実測ツールは `swift run curstyle-probe <command>`(`Sources/curstyle-probe`)。

## シグネチャ(逆アセンブルで引数レジスタを確認、型の意味は戻り値で確認)

| 関数 | 所在 | シグネチャ |
| --- | --- | --- |
| `CGSRegisterCursorWithImages` | SkyLight(`SLS*` の別名) | `(cid, name, bool setGlobally, bool instantly, CGSize, CGPoint hotspot, uintptr frameCount, CGFloat frameDuration, CFArray images, int32* seed)`。中身は `SLSRegisterCursorWithImages2` に色引数 NULL で渡すだけ |
| `CGSCopyRegisteredCursorImages` | SkyLight | `(cid, name, CGSize*, CGPoint*, uintptr*, CGFloat*, CFArray*)` |
| `CGSRemoveRegisteredCursor` | SkyLight | `(cid, name, bool)`。`com.apple.coregraphics.*` は `err=1000` で拒否 |
| `CoreCursorCopyImages` | HIServices | `(cid, id, CFArray*, CGSize*, CGPoint*, uintptr*, CGFloat*)`。id 0→`coregraphics.Arrow`、1→`coregraphics.IBeam`、それ以外→`com.apple.cursor.<id>` を名前で引くだけ |
| `CoreCursorUnregisterAll` | HIServices | `(cid)`。`com.apple.cursor.0〜43` だけを削除する |
| `CGSCursorNameForSystemCursor` | SkyLight | `(id) -> const char*`。SkyLight 内の **11件の固定表**を引くだけ |

`seed` は常に `0xAAAAAAAA` が返り、意味のある値ではない。

## 識別子

- `CGSCursorNameForSystemCursor`: 0 Arrow, 1 IBeam, 2 IBeamXOR, 3 Alias, 4 Copy, 5 Move, 6 ArrowCtx, 7 Wait, 8 Empty, 100 ArrowS, 101 IBeamS。**実行時の自動発見には使えない**(OS 更新で Apple が表を足せば増える、という程度)。
- `com.apple.cursor.N` は N=0〜43(0, 1, 6 は欠番)。`CoreCursorUnregisterAll` のループ上限 44 と一致する。
- 別名(同一ピクセル): `Arrow = ArrowS = GlobalCurrent = ConnectionCurrent = core:0`、`IBeam = IBeamS = core:1`、`Wait = GlobalCurrentWait`、`cursor.7 = cursor.8`、`cursor.9 = cursor.10`。`Alias / ArrowCtx / Copy / IBeamXOR` は 8x8 のダミー。
- `com.apple.coregraphics.Arrow` の読み戻しは、`ArrowS` に登録された内容を返す(Arrow に登録しても読み戻しは変わらない)。

## 表示への反映(目視)

| 状態 | 登録した名前 | 読み戻し | 画面 |
| --- | --- | --- | --- |
| ポインター色「カスタマイズ済み」(`cursorIsCustomized=1`) | Arrow / ArrowS / IBeam / IBeamS / cursor.13 | ArrowS・IBeamS・cursor.13 は変わる | **何も変わらない**(リンク・テキスト欄・ウィンドウ境界も) |
| 色リセット後(`cursorIsCustomized=0`) | ArrowS のみ | 変わる | 矢印が変わる |
| 同上 | Arrow のみ | 変わらない | 変わらない |
| 同上 | IBeamS + cursor.13 | 変わる | テキスト欄・リンクで変わる |

- **読み戻しの一致は表示の証拠にならない**(カスタマイズ済み状態で確認)。
- macOS 27.2 で効く名前は `ArrowS` / `IBeamS` / `com.apple.cursor.N`。`Arrow` / `IBeam` への登録は表示にも読み戻しにも効かない。
- ポインター色がカスタマイズされていると、テーマは一切表示されない。値が標準とほぼ同じ(枠 0.976)でも起こる。リセットで解消。色の変更でシステムが全カーソルを登録し直す(ArrowS の画像ハッシュが変わることを確認)。
- 「画面の端でしか出ない」現象は再現しなかった(色リセット後は Claude.app 上で即座に反映)。

## 永続性と復元

- 登録は**登録したプロセスが終了しても残る**。別プロセスからも読み戻せる(グローバル)。
- `CoreCursorUnregisterAll` は `com.apple.cursor.N` しか戻さない。ArrowS / IBeamS / Move などは差し替わったまま残る。
- `CoreCursorCopyImages(0/1)` は登録中の ArrowS / IBeamS を返すため、標準画像の取得元にならない。Arrow / IBeam の標準画像は HIServices のリソース(`Resources/cursors/`)にも無い(SkyLight 内蔵)。
- `coregraphics.*` は削除不可。**一度上書きすると、事前に保存した画像がない限りアプリ側から標準へ戻す手段がない**。今回の実測で確認できた復旧手段は、ポインター色の変更→リセット(システムによる再登録)と再ログインの2つ。
- 再ログインで全カーソルが標準に戻る(上書きした Move も戻った)。ただし再ログイン後の標準画像は、色リセット直後の登録とピクセル・hotspot・size が異なる(ArrowS: hot 4.5,4 → 5,5、IBeamS: size 22x23 → 23x22)。「標準画像」は一意ではなく、誰がいつ登録したかで変わる。
- 何も登録していない状態では `com.apple.cursor.N` は未登録(`err=1007`)。ポインター色がカスタマイズされていると、システムが全カーソルを色付きで登録する。

## Phase 1 への申し送り

1. **適用前の標準画像スナップショットを必須にする**。初回適用の前に、全 `coregraphics.*` と `com.apple.cursor.N` の画像を読み、ディスクへ保存する。復元はそれを再登録する(`cursor.N` のうち元々未登録だったものは削除)。スナップショットはポインター色・サイズの状態や、ログイン時か色変更時かによっても異なる。状態も一緒に記録し、ハッシュの完全一致で「標準か」を判定しない。
2. 「適用中かどうか」の判定は、登録 API の戻り値ではなく、スナップショットとの比較で行う。
3. 診断で `cursorIsCustomized` を読み、1 なら「テーマが表示されない」と利用者に伝える。
4. 適用の対象は `ArrowS` / `IBeamS` / `com.apple.cursor.N`。`Arrow` / `IBeam` は別名として、テーマ定義上は同じものとして扱う。
5. 自動リセット(要調査): システム設定の色変更と同じ「システムによる再登録」をアプリから起こせるかを調べる。スナップショットが無い・壊れている場合の最終手段になる。

## 未確認

- ポインターの**サイズ**変更時の挙動。
- アニメーション(複数フレーム)と HiDPI の各解像度での表示。
- 再起動後に登録が残るか(再ログインでは消えることを確認)。
- 複数ディスプレイ。
- `Move` など、普段表示されないカーソルの目視。
