# Phase 3 自動復旧ヘルパー(macOS 27.2 / arm64)

再ログイン・再起動・ポインター設定の変更で OS がテーマを消しても、常駐ヘルパーが入れ直す。仕様と、実機で確かめた結果をまとめる。

## CLI

```
curstyle helper install     LaunchAgent として登録し、起動する
curstyle helper uninstall   止めて登録を消す
curstyle helper status      登録状態・停止理由・直近のログ
curstyle helper resume      回数上限などで止まったヘルパーを再開する
curstyle helper run         ヘルパー本体(launchd から起動される)
```

## 構成

- `~/Library/LaunchAgents/io.github.narcissus-tazetta.curstyle.helper.plist`: `RunAtLoad`、`KeepAlive={SuccessfulExit=false}`、`ThrottleInterval=30`、`LimitLoadToSessionType=Aqua`、`ProcessType=Background`。
- 実行ファイルは `install` が `~/Library/Application Support/Curstyle/bin/curstyle` に写し、plist はその写しを指す。~/Desktop などの保護フォルダにある実行ファイルを launchd から起動すると、TCC の許可ダイアログが出て、それを待つ間 dyld が止まる(実測)。CLI を更新したら `install` し直す。
- ヘルパーは Dock に出ない設定(`NSApplication` の `.prohibited`)で常駐する。`RunLoop.main.run()` だけでは `CGDisplayRegisterReconfigurationCallback` が呼ばれなかった(外部ディスプレイの抜き差しで実測)。
- 置き場所 `~/Library/Application Support/Curstyle/`:
  - `active-theme/`: 最後に `apply` したテーマの写し。ヘルパーはこれを入れ直す。
  - `helper.json`: 再適用の時刻・停止理由・直近の結果。ヘルパーが再起動しても回数上限と停止の状態が残るよう、ディスクに置く。
  - `helper.log`: 1MB を超えると `helper.log.1` に退避する。
  - `helper.stderr.log`: クラッシュしたときの出力用。

## 拾うイベント

| きっかけ | 取り方 |
| --- | --- |
| ログイン(ヘルパー起動) | 起動時、起動から 10 秒後、40 秒後 |
| スリープ復帰 | `NSWorkspace.didWakeNotification` |
| ユーザー切替から戻る | `NSWorkspace.sessionDidBecomeActiveNotification` |
| ディスプレイ構成の変更 | `CGDisplayRegisterReconfigurationCallback`(変更の終了だけ拾う) |
| ポインターのサイズ・色の変更 | `~/Library/Preferences/com.apple.universalaccess.plist` の書き換えを kqueue で待つ |

ポインターのサイズ・色の変更は、distributed notification では取れない(名前を指定しない購読で何も届かなかった)。設定ファイルは cfprefsd が書き出すので、設定を変えてから最大 8 秒ほど遅れて書き換わる。色の変更とリセットが1回の書き出しにまとまると、ファイル上の値は変わらないのにテーマは消えている(実測)。そのため、値が変わったかどうかは見ず、書き換えのたびに確かめる。

ポーリングはしない。例外は、universalaccess の設定ファイルがまだ無い場合だけで、30 秒ごとに開き直す。

## 判断(`AutoReapply`)

どのイベントでも「確かめて、消えていれば入れ直す」だけ。イベントは 2 秒の debounce でまとめる。

1. ジャーナルが `clean` なら何もしない(`restore` 後や、テーマを入れていないとき)。`applying` なら通知して何もしない。
2. ジャーナルの適用内容と読み戻しを比べる。テーマが全部残っていれば何もしない。
3. ポインター色のカスタマイズ中は入れ直さず、通知する。色をリセットすると設定ファイルが書き換わり、そこで入れ直す。
4. 回数上限:
   - ポインターのサイズ・色の変更で見つかった消失は、OS の仕様どおりなので数えない。
   - それ以外(OS や他アプリとの競り合い)は、10 分に 3 回入れ直してもまた消えるなら止める。
   - 全体の上限は 1 時間に 20 回。
   - 止めたら通知する。`helper resume` か、利用者の `apply` / `restore`(ジャーナルが停止後に更新される)で再開する。
5. `active-theme` を読み、ジャーナルの適用内容とハッシュが一致することを確かめる。食い違えば止める。
6. 既存の `CursorEngine.apply` で入れ直す。手順は「スナップショット取り直し → 適用」。再ログイン直後に変わった ArrowS / IBeamS の標準も、ここで取り込まれる。ロックが取れなければ 5 秒後にやり直す。
7. 入れ直した 5 秒後と 30 秒後にもう一度確かめる。

通知は osascript の `display notification` で出す。LaunchAgent はバンドルを持たないので UNUserNotificationCenter は使えず、送信元は「スクリプトエディタ」と表示される。

## 再ログイン後の ArrowS / IBeamS の判定

再ログインで ArrowS / IBeamS の標準は別物に変わる(Phase 2 の測定 A)。スナップショットがログインより前に取ったもので、現状がスナップショットとも適用内容とも違う名前は、「不明」ではなく「標準(ログイン時に OS が登録し直した)」とする。`diagnose` は警告にはせず、`restore` の前に `snapshot` で取り直すよう案内する。

- ログイン時刻は utmpx のコンソールのログイン記録(`last` と同じ)から取る。WindowServer の起動時刻は使えない。再ログインの前後で WindowServer の pid は変わらず(421 のまま)、変わるのは loginwindow だった(2026-11-09 18:33 の再ログインの記録で確認)。
- 制約: ログイン前に他のカーソルアプリが書き換えた分も、同じ扱いになる。

## 実機で確かめたこと(2026-11-09)

| 試験 | 結果 |
| --- | --- |
| `cursor.13` を消してからヘルパーを起動 | 起動時の確認で入れ直した |
| 原因不明の消失を 4 回続ける | 4 回目で停止し、通知が出た(目視)。再起動後も停止のまま。`resume` で再開した |
| `restore` 後に起動 | 「テーマ未適用」で何もしない |
| ポインターのサイズ 1→大→1(2 回) | そのたびに cursor.N 41 件を入れ直した(目視で番号入り)。サイズを戻した直後に OS がもう一度消すことがあり、5 秒後の確認で入れ直した |
| ポインターの色を変更 | 入れ直さず、通知が出た |
| 色をリセット | 3 秒後に ArrowS / IBeamS / cursor.13 を入れ直した(目視で番号入り) |
| スリープ(蓋閉じ)からの復帰 | テーマは残っていた(`didWake` で確認) |
| 外部ディスプレイの抜き差し | `.prohibited` の NSApplication にした後は `display` で確認が走った。テーマは残っていた |
| 再ログイン | ログインから約 20 秒後(launchd 起動の 7 秒後)に 43 件(ArrowS / IBeamS / cursor.N 41 件)を入れ直した。5 秒後・10 秒後・40 秒後の確認でも適用中のまま。目視でも番号入り。`diagnose` は警告なし(新しい ArrowS / IBeamS は取り直したスナップショットに入った) |
| 再起動 | 起動の 4 秒後に 43 件を入れ直し、その後 40 秒まで適用中のまま。目視でも番号入り。`diagnose` は警告なし |
| ログイン前のスナップショットで ArrowS / IBeamS が違う状態(manifest の取得時刻を書き換えて再現) | 「ログイン時に OS が登録し直した」と表示され、不明警告は出なかった |

## 確かめていないこと

- ログイン直後に OS が ArrowS / IBeamS を登録し直すのが、ヘルパーの適用より後になる場合の競り合い。今回の再ログイン・再起動では起きなかった。起きた場合は 10 秒後・40 秒後と入れ直し後の確認で拾う想定。
- ユーザー切替。
