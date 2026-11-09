# Phase 3.5 OverlayBackend(macOS 27.2 / arm64)

本物のカーソルを隠し、最前面の透明ウィンドウに自前のカーソルを描いてマウスに追従させる方式(OverlayBackend)。CGSBackend が使えない OS 向けの非常用として実装した。前半が実現性の測定、後半が本実装の仕様と実機の結果。

合格基準(ユーザー決定): 遅延は非常用として許容し、目安は2フレーム以内でちらつきがないこと。自前カーソルを出せない場面は、その場面だけ標準カーソルに戻れば許容する(消える・二重に表示されるのは不可)。

## 測定用コード

`Sources/curstyle-overlay-probe`(配布しない)。生データとスクリプトは `.build/measure-P35/`。

```
curstyle-overlay-probe hide [--prop] [--cgs] [--rehide] [sec]   隠すだけ
curstyle-overlay-probe overlay [--mode layer|window] [--source event|link|tap] [--keep-real] [--no-tint] [--predict ms] [--pad] [sec]
curstyle-overlay-probe table                                     形の照合表
curstyle-overlay-probe watch [sec]                               現在の形を記録
curstyle-overlay-probe analyze <-C あり.png> <-C なし.png>        撮影結果の自動判定
```

自動判定は、マウス周囲を `screencapture -C`(カーソルを含める)とオプションなしの2回撮って比べる。2枚の差があれば本物のカーソルが描かれている。自前カーソルは形の中を純マゼンタで塗っておき、その画素数で写っているかを判定する。背景を固定するため、灰色の試験用ウィンドウ(`--pad`)を出す。場面はコマンドで起こす(`open -a "Mission Control"`、`screencapture -i`、System Events のキー送信、CGEvent で合成したマウス移動・クリック)。本物だけ・自前だけ・両方の3通りで判定が正しく出ることを確かめてから使った。

## M1 隠す

| 方法 | 結果 |
| --- | --- |
| `CGDisplayHideCursor` のみ | 裏で動くプロセスからは効かない |
| `SetsCursorInBackground` + `CGDisplayHideCursor` | 最初の数回は効いたが、途中から効かなくなった(原因は未特定) |
| `CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground", true)` + `CGSHideCursor(cid)` | 効く。`screencapture -C` にも本物が写らない |

隠した状態は次のきっかけで解ける。

- **アプリの切替**: 前面に来たアプリが表示し直す。`NSWorkspace.didActivateApplicationNotification` で隠し直すが、通知の後からまた表示し直すアプリがある(Claude は切替後 約20ms と 約50ms)。切替後1秒間だけ 10ms ごとに見張って隠し直すと、Finder・Claude・Safari・Chrome・Discord のどれに切り替えても隠れたままになった。
- **クリックなど、切替以外の操作**: 隠し直しを 100ms に1回までに抑えたうえで、マウスイベントや表示更新のたびに `CGCursorIsVisible` を確かめて隠し直す。
- **隠し直しても効かない場面**(Mission Control、`screencapture -i` の十字、Dock の上): 本物が表示されている間は自前のウィンドウを透明にして本物に任せる(yield)。こうすると二重表示にならず、その場面だけ標準カーソルになる。

`CGCursorIsVisible` は Swift からは unavailable 扱いだが、シンボルは残っているので dlsym で呼ぶ。

## M2 形の判定

`NSCursor.currentSystem` は本物を隠している間も、ほかのアプリが設定した現在の形を返す。変化は `CGSCurrentCursorSeed` で検知する。画像の照合は、大きさ・hotspot・最大解像度の画素(sRGB RGBA8 に描き直したもの)のハッシュで行う。照合表の出どころは次の2つ。

- AppKit の `NSCursor` ファクトリ。引数なしのクラスメソッドを runtime から集める(`_windowResize*`・`_helpCursor` などの非公開も含む)。`_moveCursor` は呼ぶと例外で落ちるので除外する。`arrowCursor` / `IBeamCursor` はメタクラスのメソッド一覧に出てこないので明示する。ただしプロセスによっては画像が空になる。
- CGSBackend のスナップショット(`~/Library/Application Support/Curstyle/snapshot/`)。ArrowS / IBeamS はここで当たる。

実機で正しく判定できた形: ArrowS、IBeamS、pointingHand、斜めと上下左右のウィンドウリサイズ、operationNotAllowed(ドラッグ中)。照合表にない形は次の3つで、どれも照合できなくても現在の画像をそのまま描けば標準の見た目になる。

- Chrome が文字入力中に設定する 1x1 の透明カーソル。
- `screencapture -i` の十字。座標の数字が入っているため、毎フレーム画像が変わる。
- アニメするカーソル(未確認)。

## M3 追従と遅延

| 方式 | イベント→移動の処理時間 p50 / p99 | CPU 平均(動かしている間) |
| --- | --- | --- |
| 画面全体の透明ウィンドウ + layer、グローバルイベントモニタ | 0.40 / 4.7 ms | 2.6〜3.2% |
| 同上、displayLink で毎フレーム位置を読む | — | 1.6〜4.2% |
| 小さいウィンドウを動かす、グローバルイベントモニタ | 0.62 / 5.6 ms | 4.5% |
| 同上、受信専用 CGEventTap | 0.29 / 2.4 ms | 2.1% |

- 自前側の処理時間はどれも1ms 未満で、遅れのほとんどは WindowServer の合成(ウィンドウの描画が画面に出るまで)にある。内蔵ディスプレイは 60Hz。
- **目視(ユーザー)**: 本物を出したまま重ねると、どの方式も「はっきり遅れる」。方式の差はほとんど分からない。**本物を隠した実際の使い方では「完璧に使えている」**。速度から先を予測して描く方式(16ms・33ms 先)でも、体感の差はなかった。
- 遅延を画面上で数値として測ってはいない(処理時間と体感だけ)。
- 落とし穴: `.accessory` の NSApplication を CLI から起動すると最前面のアプリになり、グローバルモニタにイベントが来なくなる。`.prohibited` にする。

## M4 場面

自動判定の結果(各場面3回撮影)。

| 場面 | 結果 |
| --- | --- |
| デスクトップ(Space)切替中・切替後 | 自前のまま。切替アニメ中の1回だけ本物と自前が両方写った(`CGCursorIsVisible` は非表示のまま)。ユーザーの目視では二重表示なし |
| Mission Control | yield。本物だけ |
| `screencapture -i`(Command+Shift+4 と同じ十字) | yield。本物だけ |
| フルスクリーンアプリ(TextEdit) | 自前のまま |
| Dock の上(合成したマウス移動) | yield。本物だけ |
| メニューバーの上・クリックしてメニューを開く | 自前のまま |
| セキュア入力中(`EnableSecureEventInput`)とその間の移動 | 自前のまま |
| ポインターサイズを拡大(`CGSSetCursorScale` 2.5) | **自前は拡大されない**。本実装では `CGSGetCursorScale` を掛ける必要がある |
| 画面収録・スクリーンショット | 自前はウィンドウなので写り、本物は写らない |

yield を入れる前の目視では、Mission Control・Command+Shift+4・メニューバーのクリック・Dock の上で、本物と自前が二重に見えた。

確認していない場面: ロック画面・ログイン画面(ヘルパーの外なので標準カーソルのはず)、外部ディスプレイ、フルスクリーンのゲーム、長時間の常駐、アニメするカーソル、システム設定から変えたポインターサイズ。

## M5 権限

probe(Claude アプリから起動した子プロセス)では、グローバルイベントモニタ・受信専用の CGEventTap・`CGSHideCursor`・ウィンドウの表示が、どれも許可ダイアログなしで動いた。ただし、これは親の Claude アプリの権限を引き継いでいたためとみられる。launchd から起動した場合は、グローバルモニタにも CGEventTap にもマウスイベントが届かない(後述の本実装で実測)。届いたのは、`NSEvent.mouseLocation` を読む方式だけだった。

## M6 安全性

隠している最中に `kill -9`(3回)や SIGTERM で終了させても、接続が切れた時点で WindowServer が本物を自動で表示に戻した。復元処理を別に持たなくても、プロセスが落ちればカーソルは戻る。

## 本実装

### 使い方

```
curstyle apply --backend overlay <theme-dir>   overlay 方式で適用する(描画はヘルパーが行う。`curstyle helper install` が要る)
curstyle restore                               overlay 方式なら描画を止める
curstyle make-theme <dir> --overlay-check      役割ごとに単色の検証用テーマ
```

自動では切り替えない(ユーザー決定)。CGSBackend が使えないと分かったときは、`diagnose` と CGS での `apply` の失敗時に overlay 方式を勧める。ポインター色のカスタマイズ中は、overlay でも適用を拒否する。

### 構成

- `Sources/CursorKit/Overlay/`
  - `OverlaySymbols`: 非公開シンボルを dlsym で解決する。1つでも欠ければ overlay は使えず、diagnose に出す。
  - `ShapeMatcher`: いまの形(`NSCursor.currentSystem`)が、どの登録名の標準画像かを引く。
  - `OverlayRenderer`: 本物を隠す・隠し直す・自前を引っ込める(yield)。ディスプレイごとの透明ウィンドウと layer、拡大率、アニメ。
  - `OverlayController`: ヘルパー側で、ジャーナルに合わせて描画を始める・止める。クラッシュの繰り返しの検知、一時停止、状態の保存。
  - `OverlayActivation`: CLI 側の適用。
- ジャーナルの `backend`(`cgs` / `overlay`)で方式を記録する。overlay では `intended` は空で、登録はしない。
- CLI は apply / restore / reset-system の後に distributed notification(`io.github.narcissus-tazetta.curstyle.changed`)を送る。ヘルパーはそれを受けてジャーナルを読み直す。CLI は `helper.json` の `overlay` で、ヘルパーが描画を始めた(止めた)ことを最大5秒待って確かめる。
- overlay で適用するとき、CGSBackend のテーマが残っていれば先に標準へ戻す(`NSCursor.currentSystem` が標準画像を返すようにするため)。CGS が使えればスナップショットも取り直す。

### 振る舞い

- **位置**: 動いている間は displayLink で毎フレーム `NSEvent.mouseLocation` を読む。約0.5秒止まったら、毎秒15回に間引く。間引いている間も、形と本物の表示状態を確かめ、1秒ごとにポインターの拡大率も確かめる。
- **形**: 照合元は、CGS で読んだ現在の標準 → スナップショット → AppKit のファクトリの順(先に入れたものを優先)。照合できない形や、テーマにない形は、いま OS が出している画像をそのまま描く。マウスが動いた後は、50 / 150 / 400ms 後にも形を確かめ直す(下のアプリは少し遅れてカーソルを設定するため)。
- **隠す**: アプリの切替から1秒間は 10ms ごとに見張る。それ以外は、位置を読むたびに確かめる(隠し直しは 100ms に1回まで、yield 中は1秒に1回まで)。隠し直しても表示のままなら、自前のウィンドウを透明にする(yield)。
- **一時停止**: 画面ロック(`com.apple.screenIsLocked` / `screenIsUnlocked`)、スクリーンセーバー(`com.apple.screensaver.didstart` / `didstop`)、セッションが非アクティブの間は、描画を止めて本物に任せる。ロック画面の上には自前が出ないので、本物を隠したままだとカーソルが消える(実機で確認)。
- **止める**: `CGSHideCursor` を呼んだ回数だけ `CGSShowCursor` を呼ぶ。0.5秒待っても本物が表示に戻らなければ、ヘルパーを終了して(exit 1、launchd が起動し直す)WindowServer に戻させる。
- **クラッシュの繰り返し**: ヘルパーの起動で overlay を始めた回数が10分に4回になったら、描画を止めて通知する。apply し直すか `helper install` で再開する。
- **ポインター色**: カスタマイズされたら描画を止めて通知し、リセットされたら再開する。

### 実機の結果

自動判定(`.build/measure-P36/`)。マウスの移動は CGEvent で合成し、撮影の判定は `curstyle-overlay-probe analyze` で行った。

| 確認 | 結果 |
| --- | --- |
| 形ごとの色(Safari で CSS の cursor を指定したグリッド: default / text / pointer / col-resize / grab / not-allowed / crosshair / help) | 3周 27回すべて期待どおり |
| 場面(デスクトップ切替・Mission Control(止めたまま/動かす)・`screencapture -i`・Dock・メニューバー・アプリ切替) | 32回中31回合格。不合格はデスクトップ切替アニメ中の1回だけで、本物と自前が両方写った(Phase 3.5 と同じ) |
| ヘルパーを kill -9 | launchd が起動し直し、overlay が再開した |
| kill -9 を繰り返す | 10分に4回目の起動で止まり、本物に戻った。diagnose に「問題」で出た |
| ポインターの拡大率 1 → 2 → 1(`CGSSetCursorScale`) | 自前の面積が 4倍 → 元に戻った |
| CGS で apply ↔ overlay で apply | どちらの向きでも、前の方式は止まるか標準へ戻る |
| restore | 描画が止まり、本物が表示に戻った。diagnose は警告なし |
| 待機 CPU / 移動中 CPU | 約 0% / 平均 0.85%(`ps`) |
| メモリ | footprint 21MB(`top`)。RSS は overlay なしで 60MB、ありで 77MB |
| 目視: 画面ロック → 解除 | ロック画面では標準カーソルが見え、解除後は番号入りに戻った |

確認していない場面: 再ログイン(起動時の経路は kill -9 で確かめたもの)、外部ディスプレイ、フルスクリーンのゲーム、長時間の常駐、アニメするテーマ、システム設定から変えたポインターサイズ、セッション切替。

既知の制約:

- デスクトップ切替のアニメ中に、一瞬だけ二重に表示されることがある。
- 動き始めは、間引き中の読み取り(最大約 70ms)の分だけ遅れる。
- ヘルパーを入れ直すたびに、macOS が「バックグラウンドで実行できます」という通知を出す。
