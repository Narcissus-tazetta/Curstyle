# Curstyle

macOS のシステムカーソル(矢印・Iビーム・指差しなど)を、テーマ単位で差し替える軽量アプリ。エンジン(`CursorKit`)、CLI(`curstyle`)、アプリ(`Curstyle.app`)からなる。

> [!WARNING]
> macOS の非公開 API(SkyLight / HIServices / AccessibilityFoundation)を使っている。OS の更新で動かなくなる可能性がある。動作を確認しているのは macOS 27.2 / Apple Silicon だけ。

## 方針

非公開 API を使う以上、「OS が更新されても必ず動く」とは約束できない。代わりに次の4点を守る。

1. **壊さない**: どんな失敗の後でも、標準のカーソルへ戻せる。
2. **壊れたら気づく**: 適用後に読み戻して検証し、問題を診断で伝える。
3. **壊れ方が小さい**: 知らない識別子があっても全体は止めず、その識別子だけ標準のまま残す。
4. **直せる**: 診断レポートで OS ごとの違いを素早く見つけられるようにする。

## 必要なもの

- macOS 27.2 以降(Apple Silicon で確認済み)
- Swift 6 ツールチェーン(Xcode)

## ビルド

```bash
./make-app.sh
```

`~/Applications/Curstyle.app` ができる。CLI だけなら `swift build -c release` で `.build/release/curstyle` にできる(アプリの中の `Contents/MacOS/curstyle` も同じもの)。

## アプリ

- サイドバーにテーマの一覧、右にテーマごとのプレビュー(アニメも再生)。ツールバーで背景とホットスポットの表示を切り替えられる。
- 取り込み: Windows のカーソルテーマ(.ani / .cur)のフォルダ・.cape ファイル・theme.json のフォルダを、「＋」(⌘O)・ウィンドウへのドロップ・Dock アイコンへのドロップで渡す。取り込む前にプレビューと大きさを確かめられる。
- 編集: カーソルのタイルを押すと、ホットスポット・1コマの秒数を変えたり、画像を GIF / PNG に差し替えたりできる。テーマ全体のアニメの速さは「…」メニューから一括で変える。適用中のテーマを編集してもカーソルは書き換えず、「変更を適用」で反映する。
- 適用・標準に戻すは、テーマの画面・サイドバー下端・メニューバーから。
- 設定の「テーマが消えたら自動で入れ直す」で常駐ヘルパーを登録する(`curstyle helper install` で入れたものは置き換える)。
- 診断画面から不具合報告用のレポートを書き出せる。

## 使い方

```bash
curstyle diagnose                         # 自己診断。問題があれば終了コード 1
curstyle status                           # 名前ごとの状態(標準 / テーマ適用中 / 不明)
curstyle apply --test [arrow,ibeam,link]  # テスト画像を適用する(--animated でアニメ版)
curstyle apply <theme-dir>                # theme.json のテーマを適用する
curstyle apply --backend overlay <theme-dir>  # 本物を隠して自前で描く方式で適用する(CGSBackend が使えない OS 向け。ヘルパーが要る)
curstyle restore                          # 保存しておいた標準画像に戻す(overlay 方式なら描画を止める)
curstyle reset-system                     # 保存画像を使わずに OS の標準へ戻す(最終手段)
curstyle report [file]                    # 不具合報告用の診断レポートを書き出す(- で標準出力)
curstyle import <source> <theme-dir> [--scale N]  # .cape か Windows のカーソルフォルダをテーマに変換する(Windows は既定 1 px = 1 pt)
curstyle make-theme <dir> [--labels]      # テスト画像をテーマとして書き出す(--labels は cursor.N に番号を描く、--overlay-check は役割ごとに単色)
curstyle helper install                   # ログイン時に自動で再適用するヘルパーを登録する(uninstall / status / resume)
```

- 初めて適用するときに、標準画像のスナップショットを `~/Library/Application Support/Curstyle/` に保存する。macOS には差し替えた矢印・Iビームの標準画像を取り出す手段がないので、`restore` はこのスナップショットを使って戻す。
- 「システム設定 > アクセシビリティ > ディスプレイ > ポインタ」で色を変えていると、テーマは表示されない。この状態では `apply` / `snapshot` / `reset-system` は実行を拒否し、`diagnose` も問題として知らせる。
- スクリーンショット(Command+Shift+4)の十字など、アプリが独自に登録するカーソルは変えられない。
- 再ログイン・再起動・ポインターのサイズや色の変更で、OS はテーマを消す。`helper install` しておくと、常駐ヘルパーが消えたことを検知して入れ直す。入れ直してもすぐ消える状態が続いたら止まって通知するので、`curstyle helper status` で理由を確かめる。
- 何をしても戻らない場合は、ログアウトしてログインし直せば標準に戻る。

## ドキュメント

- [docs/PLAN.md](docs/PLAN.md): 開発計画、安定性の定義、設計原則
- [docs/PHASE0.md](docs/PHASE0.md): 非公開 API の実測結果(シグネチャ・識別子・表示への反映・復元)
- [docs/PHASE1.md](docs/PHASE1.md): エンジンと CLI の仕様、実機で確かめた結果
- [docs/PHASE2.md](docs/PHASE2.md): 実テーマ・ポインター色・cursor.N の実機確認と診断レポート
- [docs/PHASE3.md](docs/PHASE3.md): 自動再適用ヘルパーの仕様と実機の結果
- [docs/PHASE3_5.md](docs/PHASE3_5.md): OverlayBackend の実現性測定・仕様・実機の結果
- [docs/PHASE5.md](docs/PHASE5.md): アプリの仕様と実機の結果

## 構成

| パス | 内容 |
| --- | --- |
| `Sources/CCursorBridge` | 非公開 API の C ブリッジ。シンボルは `dlsym` で解決する |
| `Sources/CursorKit` | エンジン本体(適用・スナップショット・復元・診断)。`Overlay/` は OverlayBackend |
| `Sources/curstyle` | CLI(常駐ヘルパーも兼ねる) |
| `Sources/CurstyleApp` | アプリ(SwiftUI)。`make-app.sh` で `Support/` の plist と一緒にバンドルにする |
| `Sources/curstyle-probe` | 非公開 API の実測用ツール |
| `Sources/curstyle-overlay-probe` | OverlayBackend の実測・自動判定用ツール |

## ライセンス

[MIT](LICENSE)
