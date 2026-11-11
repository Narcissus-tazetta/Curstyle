# Curstyle

**macOS のカーソルを、お気に入りのテーマに。**

矢印、テキスト選択、リンク、ウィンドウのサイズ変更など、システムカーソルをまとめて差し替えるアプリです。Windows のカーソルテーマや Mousecape の `.cape` を取り込み、アニメーションのプレビューから編集・適用まで行えます。

> [!WARNING]
> 開発中のアプリです。macOS の非公開 API（SkyLight / HIServices / AccessibilityFoundation）を利用しているため、OS の更新で動作しなくなる可能性があります。動作確認済みの環境は **macOS 27.2 / Apple Silicon** です。

## できること

- **テーマを取り込む** — Windows の `.cur` / `.ani`、Mousecape の `.cape`、Curstyle の `theme.json` 形式に対応。
- **適用前に確かめる** — カーソルの役割ごとにアニメーションを再生。背景とホットスポット（クリック位置）も確認できます。
- **使いやすく調整する** — ホットスポット、大きさ、アニメの速さを編集。カーソルごとに GIF / PNG の画像へ差し替えられます。
- **すぐに切り替える** — アプリとメニューバーからテーマの適用・標準への復元ができます。
- **消えたテーマを入れ直す** — 常駐ヘルパーが、再ログインや再起動、ポインター設定の変更によるテーマの消失を検知して再適用します。
- **状態を調べる** — 設定画面から診断し、不具合報告用のレポートを書き出せます。

## ビルドして起動する

必要なものは、Swift 6 ツールチェーンを含む Xcode です。ビルド設定上の最低 OS は macOS 14 ですが、それ以降のすべての OS での動作を保証するものではありません。Intel Mac での動作は未確認です。

```bash
git clone https://github.com/Narcissus-tazetta/Curstyle.git
cd Curstyle
./make-app.sh
open "$HOME/Applications/Curstyle.app"
```

`make-app.sh` は release ビルドしたアプリと CLI をまとめ、ad-hoc 署名を付けて `~/Applications/Curstyle.app` に配置します。同じ場所にある既存の Curstyle.app は置き換えます。

## はじめて使う

1. カーソルテーマを用意し、必要ならアーカイブを展開します。
2. テーマのフォルダまたは `.cape` ファイルをウィンドウにドラッグします。「＋」（⌘O）や Dock アイコンへのドロップからも取り込めます。
3. プレビューで役割と大きさ、取り込まれないファイルを確認し、「ライブラリに追加」を押します。
4. テーマを選び、「このテーマを適用」を押します。

元に戻すときは、テーマ画面・サイドバー下端・メニューバーの「標準に戻す」を使います。

### 対応する形式

| 入力 | 渡すもの | 補足 |
| --- | --- | --- |
| Windows カーソル | `.cur` / `.ani` を含むフォルダ | INF の役割情報やファイル名から対応先を判定。同じ役割ではアニメ版を優先します |
| Mousecape | `.cape` ファイル | カーソル画像・アニメーション・ホットスポットを取り込みます |
| Curstyle | `theme.json` と画像を含むフォルダ | Curstyle のテーマをそのまま取り込めます |
| GIF / PNG | カーソルの編集画面で選択 | 個別のカーソル画像の差し替えに使います |

Windows テーマの大きさは、既定で **1 px = 1 pt** です。32 px の画像は 32 pt になります。小さく使いたい場合は、取り込み画面で「小さめ（2 px = 1 pt）」を選べます。macOS 側に対応先がない役割や、判定できないファイルは取り込まれません。

24コマを超えるアニメーションは、取り込み時に自動で24コマへ間引きます。1周の再生時間を保ちますが、動きの滑らかさは低下します。変換内容は取り込み画面・CLIに表示されます。GIF画像の差し替えも同じ扱いです。

### カーソルを編集する

テーマ画面のカーソルをクリックすると編集画面が開きます。ホットスポットはプレビュー上でクリック・ドラッグするか、数値で指定できます。アニメの速さはカーソルごとに変更でき、テーマの「…」メニューから全体の速さや大きさも一括で変えられます。

適用中のテーマを編集した場合、保存だけでは画面上のカーソルは変わりません。「変更を適用」で反映します。

### ログイン後も使う

設定の「テーマが消えたら自動で入れ直す」をオンにすると、常駐ヘルパーを登録します。macOS から承認を求められたら、システム設定の「ログイン項目」で Curstyle のバックグラウンド実行を許可してください。

「ログイン時にメニューバーに表示」は別の設定です。テーマの自動再適用だけなら、こちらをオンにする必要はありません。

## 制約と困ったとき

### 適用してもカーソルが変わらない

「システム設定 → アクセシビリティ → ディスプレイ → ポインタ」で、ポインターの色を標準に戻してください。色をカスタマイズしている間はテーマを適用できず、診断でもその状態を知らせます。

また、スクリーンショット（⌘⇧4）の十字など、アプリが独自に登録するカーソルは差し替えられません。

### 再ログインや設定変更でテーマが消える

macOS がカーソルをリセットするためです。自動で戻したい場合は、常駐ヘルパーを有効にしてください。

再適用してもすぐに消える状態が繰り返されると、ヘルパーは自動再適用を停止して通知します。設定画面で停止理由を確認し、「再開」できます。

### 標準のカーソルに戻したい

アプリの「標準に戻す」を使います。アプリが開けない場合は、ターミナルからも復元できます。

```bash
"$HOME/Applications/Curstyle.app/Contents/MacOS/curstyle" restore
```

それでも戻らない場合は、保存画像を使わずに OS の標準へ戻すコマンドがあります。ポインターの色は標準にしてから実行してください。

```bash
"$HOME/Applications/Curstyle.app/Contents/MacOS/curstyle" reset-system
```

ログアウトしてログインし直すことでも標準に戻ります。常駐ヘルパーが有効な場合はテーマを再適用するため、先に自動再適用をオフにしてください。

### 診断や保存データを確認したい

設定の「診断」から状態を確認し、「レポートを書き出す」で診断レポートを保存できます。

データの保存先は `~/Library/Application Support/Curstyle/` です。`themes/` に取り込んだテーマを保存し、標準カーソルのスナップショットや適用記録、ヘルパーのログもこの保存先で管理します。標準に戻す際に使うため、テーマ適用中にスナップショットを削除しないでください。

## CLI

アプリには同じエンジンを使う CLI を同梱しています。以下は、リポジトリで CLI だけをビルドして使う例です。

```bash
swift build -c release --product curstyle

.build/release/curstyle diagnose
.build/release/curstyle import /path/to/windows-theme /path/to/converted-theme
.build/release/curstyle apply /path/to/converted-theme
.build/release/curstyle restore
```

アプリ同梱版を使う場合は、`.build/release/curstyle` を `"$HOME/Applications/Curstyle.app/Contents/MacOS/curstyle"` に置き換えてください。CLI は自動では `PATH` に追加されません。

| コマンド | 用途 |
| --- | --- |
| `diagnose` | 自己診断。問題があれば終了コード 1 |
| `status` | カーソル名ごとの適用状態を表示 |
| `import <source> <theme-dir> [--scale N] [--name NAME]` | Windows のカーソルフォルダ・`.cape` を Curstyle 形式に変換 |
| `apply <theme-dir>` | `theme.json` のテーマを適用 |
| `restore` | 保存した標準画像に戻す |
| `reset-system` | 保存画像を使わず、OS の標準に戻す |
| `report [file]` | 診断レポートを保存。`-` で標準出力 |
| `helper install / uninstall / status / resume` | CLI から常駐ヘルパーを管理 |
| `make-theme <dir> [--labels \| --overlay-check]` | 動作確認用のテーマを書き出す |

アプリの設定からヘルパーを有効にすると、`helper install` で登録したヘルパーはアプリ同梱版に置き換わります。

<details>
<summary>代替の描画方式（OverlayBackend）</summary>

通常はシステムカーソルの画像を直接差し替える CGSBackend を使います。CGSBackend が使えない OS 向けに、本物のカーソルを隠して自前で描画する OverlayBackend も用意しています。切り替えは手動で、描画には常駐ヘルパーが必要です。

```bash
.build/release/curstyle helper install
.build/release/curstyle apply --backend overlay /path/to/theme
.build/release/curstyle restore
```

OverlayBackend でも、ポインターの色をカスタマイズしている間は適用できません。

</details>

## 開発

Swift Package Manager で構成しています。

| パス | 内容 |
| --- | --- |
| `Sources/CurstyleApp` | SwiftUI アプリ |
| `Sources/CursorKit` | テーマの取り込み・編集・適用・復元・診断・自動再適用 |
| `Sources/CursorKit/Overlay` | OverlayBackend |
| `Sources/CCursorBridge` | 非公開 API の C ブリッジ。シンボルは `dlsym` で解決 |
| `Sources/curstyle` | CLI と常駐ヘルパー |
| `Sources/curstyle-probe` / `Sources/curstyle-overlay-probe` | 非公開 API・描画方式の測定ツール |
| `Tests/CursorKitTests` | カーソルの取り込み・アニメーション変換のテスト |
| `Support` / `make-app.sh` | アプリのバンドル設定と組み立て |

```bash
swift build
swift test
```

## ライセンス

Curstyle のソースコードのライセンスは [MIT License](LICENSE) です。外部から取り込むカーソルテーマや画像の利用条件は、それぞれの配布元を確認してください。
