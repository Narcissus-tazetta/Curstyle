# Curstyle

macOS のシステムカーソル(矢印・Iビーム・指差しなど)を、テーマ単位で差し替える軽量アプリ。現在はエンジン(`CursorKit`)と CLI(`curstyle`)だけを提供しており、GUI はまだない。

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
swift build -c release
```

実行ファイルは `.build/release/curstyle` にできる。

## 使い方

```bash
curstyle diagnose                         # 自己診断。問題があれば終了コード 1
curstyle status                           # 名前ごとの状態(標準 / テーマ適用中 / 不明)
curstyle apply --test [arrow,ibeam,link]  # テスト画像を適用する(--animated でアニメ版)
curstyle apply <theme-dir>                # theme.json のテーマを適用する
curstyle restore                          # 保存しておいた標準画像に戻す
curstyle reset-system                     # 保存画像を使わずに OS の標準へ戻す(最終手段)
curstyle report [file]                    # 不具合報告用の診断レポートを書き出す(- で標準出力)
curstyle make-theme <dir> [--labels]      # テスト画像をテーマとして書き出す(--labels は cursor.N に番号を描く)
```

- 初めて適用するときに、標準画像のスナップショットを `~/Library/Application Support/Curstyle/` に保存する。macOS には差し替えた矢印・Iビームの標準画像を取り出す手段がないので、`restore` はこのスナップショットを使って戻す。
- 「システム設定 > アクセシビリティ > ディスプレイ > ポインタ」で色を変えていると、テーマは表示されない。この状態では `apply` / `snapshot` / `reset-system` は実行を拒否し、`diagnose` も問題として知らせる。
- スクリーンショット(Command+Shift+4)の十字など、アプリが独自に登録するカーソルは変えられない。
- 何をしても戻らない場合は、ログアウトしてログインし直せば標準に戻る。

## ドキュメント

- [docs/PLAN.md](docs/PLAN.md): 開発計画、安定性の定義、設計原則
- [docs/PHASE0.md](docs/PHASE0.md): 非公開 API の実測結果(シグネチャ・識別子・表示への反映・復元)
- [docs/PHASE1.md](docs/PHASE1.md): エンジンと CLI の仕様、実機で確かめた結果
- [docs/PHASE2.md](docs/PHASE2.md): 実テーマ・ポインター色・cursor.N の実機確認と診断レポート

## 構成

| パス | 内容 |
| --- | --- |
| `Sources/CCursorBridge` | 非公開 API の C ブリッジ。シンボルは `dlsym` で解決する |
| `Sources/CursorKit` | エンジン本体(適用・スナップショット・復元・診断) |
| `Sources/curstyle` | CLI |
| `Sources/curstyle-probe` | 非公開 API の実測用ツール |

## ライセンス

[MIT](LICENSE)
