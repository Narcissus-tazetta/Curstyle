const en = {
  lang: "en",
  locale: "en_US",
  title: "Curstyle — Make your macOS cursor your own",
  description:
    "Import Windows cursor themes or Mousecape .cape files, try them on real text and links, compare them side by side, and apply them to macOS. Free and open source.",
  nav: { features: "Features", install: "Install", faq: "FAQ", github: "GitHub" },
  switchLabel: "日本語",
  hero: {
    title: "Make your macOS cursor your own.",
    lead: "Import Windows cursor themes or Mousecape .cape files, try them on text, links, and click targets, compare them side by side, then apply.",
    meta: "macOS 14+ · Apple Silicon · Free and open source",
    primary: "Install",
    secondary: "GitHub",
  },
  stage: {
    label: "Try it",
    hint: "Move your pointer over the sample. The cursor changes with what is under it, just like in the app.",
    text: "The quick brown fox jumps over the lazy dog.",
    link: "View documentation",
    button: "Button",
    size: "Size",
    themes: { system: "System", amber: "Amber", neon: "Neon", ink: "Ink" },
    roles: { arrow: "Arrow", text: "Text", link: "Link" },
    note: "Demo cursors are drawn for this page. Real themes come from the files you import.",
  },
  features: {
    title: "Everything between “I found a theme” and “it’s my cursor”",
    items: [
      {
        id: "import",
        title: "Import themes",
        body: "Windows .cur / .ani files, Mousecape .cape files, or Curstyle’s own theme.json. Roles are detected for you.",
      },
      {
        id: "compare",
        title: "Try and compare",
        body: "Put up to four themes on the same text, links, buttons, and map sample, each with its own size control and a light or dark background.",
      },
      {
        id: "mix",
        title: "Mix and match",
        body: "Swap a single role with a cursor from another theme or a GIF / PNG, check Current against After, and add roles a theme lacks.",
      },
      {
        id: "tune",
        title: "Fine-tune",
        body: "Edit hotspots and animation speed. Undo saved edits one at a time with ⌘Z; history survives restarts.",
      },
      {
        id: "reapply",
        title: "Stays applied",
        body: "A background helper reapplies your theme after a restart, login, or pointer setting change, and pauses with a reason if it keeps failing.",
      },
      {
        id: "diagnose",
        title: "Diagnose and restore",
        body: "Restore the saved defaults from the app, the menu bar, or the CLI, even if the app can’t open. Export a diagnostic report from Settings.",
      },
    ],
  },
  showcase: {
    compareTitle: "Feel the difference before you apply.",
    compareBody:
      "Choose Try it next to the apply button. Add themes with +, move between the sample areas, and resize each one on its own. Your system cursor stays untouched until you decide.",
    compareAlt:
      "Two cursor themes side by side, with text, links, click targets, and independent size controls",
    replaceTitle: "Replace just one cursor.",
    replaceBody:
      "Click a cursor tile, pick a cursor from another library theme or a GIF / PNG file, and compare Current and After before saving.",
    replaceAlt:
      "Replacing a precision cursor with one from another library theme, with a before-and-after preview",
    credit: "Amber cursors shown: Bibata Modern Amber",
    creditUrl: "https://github.com/ful1e5/Bibata_Cursor",
  },
  install: {
    title: "Install",
    lead: "Apple Silicon only.",
    brew: "Homebrew",
    manual: "Manual",
    copy: "Copy",
    copied: "Copied",
    steps: [
      "Download the latest Curstyle-macos-vX.Y.Z.dmg from Releases.",
      "Open the DMG and move Curstyle.app to Applications.",
      "Launch Curstyle from Applications.",
    ],
    warningTitle: "First-launch warning",
    warning:
      "Curstyle is distributed without Apple notarization, so macOS may show a security warning. After attempting to launch it, open System Settings → Privacy & Security, choose Open Anyway for Curstyle, and follow the prompts.",
    releases: "Releases",
    latest: (version: string, date: string) => `Latest: v${version} · ${date}`,
  },
  faq: {
    title: "FAQ",
    items: [
      {
        q: "Is it safe? Can I get my normal cursor back?",
        a: "Yes. Curstyle saves your default cursors before applying anything. Choose Restore Defaults in the app or the menu bar, or run the bundled CLI’s restore command if the app won’t open. Curstyle also checks that the registered images match your theme and tries to restore the defaults if applying fails.",
      },
      {
        q: "Which Macs and macOS versions work?",
        a: "Releases are Apple Silicon only. The deployment target is macOS 14, but Curstyle uses private macOS APIs, so an OS update may break it. The tested environment is macOS 27.2 on Apple Silicon; Intel has not been tested.",
      },
      {
        q: "Why does macOS warn me when I open it?",
        a: "Curstyle is distributed without Apple notarization. Choose Open Anyway under System Settings → Privacy & Security after the first launch attempt. Updates are signed and verified before they replace the app.",
      },
      {
        q: "The cursor doesn’t change. What now?",
        a: "Reset pointer colors to their defaults under System Settings → Accessibility → Display → Pointer. Curstyle refuses to apply themes while custom pointer colors are on, and Diagnostics explains the state. Cursors that other apps register on their own, such as the ⌘⇧4 screenshot crosshair, can’t be replaced.",
      },
      {
        q: "Which formats can I import?",
        a: "A folder of Windows .cur / .ani files, a Mousecape .cape file, or a folder with Curstyle’s theme.json. GIF and PNG files can replace or add an individual cursor inside a theme.",
      },
    ],
  },
  footer: {
    github: "GitHub",
    releases: "Releases",
    license: "MIT License",
    note: "Apple and macOS are trademarks of Apple Inc. Curstyle is not affiliated with Apple.",
  },
};

type Dict = typeof en;

const ja: Dict = {
  lang: "ja",
  locale: "ja_JP",
  title: "Curstyle — Mac のカーソルを自分好みに",
  description:
    "Windows のカーソルテーマや Mousecape の .cape を取り込み、実際の文字やリンクで試して、並べて比べて、macOS に適用できるオープンソースアプリ。",
  nav: { features: "機能", install: "インストール", faq: "FAQ", github: "GitHub" },
  switchLabel: "English",
  hero: {
    title: "Mac のカーソルを、自分好みに。",
    lead: "Windows のカーソルテーマや Mousecape の .cape を取り込み、文字・リンク・クリック対象で試し、並べて比べてから適用できます。",
    meta: "macOS 14 以降 · Apple Silicon · 無料・オープンソース",
    primary: "インストール",
    secondary: "GitHub",
  },
  stage: {
    label: "試してみる",
    hint: "サンプルの上でポインターを動かしてください。アプリと同じように、下にあるものに合わせてカーソルが変わります。",
    text: "The quick brown fox jumps over the lazy dog.",
    link: "ドキュメントを見る",
    button: "ボタン",
    size: "大きさ",
    themes: { system: "標準", amber: "アンバー", neon: "ネオン", ink: "インク" },
    roles: { arrow: "矢印", text: "テキスト", link: "リンク" },
    note: "ここのカーソルはこのページ用に描いたものです。実際のテーマは取り込んだファイルから作られます。",
  },
  features: {
    title: "テーマを見つけてから、自分のカーソルになるまで",
    items: [
      {
        id: "import",
        title: "テーマを取り込む",
        body: "Windows の .cur / .ani、Mousecape の .cape、Curstyle の theme.json に対応。役割は自動で判別します。",
      },
      {
        id: "compare",
        title: "試して比べる",
        body: "最大4つのテーマを同じ文字・リンク・ボタン・地図サンプルに並べて比較。大きさはテーマごとに調整でき、背景も明暗で切り替えられます。",
      },
      {
        id: "mix",
        title: "混ぜて組み合わせる",
        body: "ほかのテーマや GIF / PNG のカーソルで1つの役割だけ差し替え。変更前後を見比べ、足りない役割も追加できます。",
      },
      {
        id: "tune",
        title: "細かく整える",
        body: "ホットスポットとアニメーション速度を編集。保存した編集は ⌘Z で1回ずつ取り消せ、再起動後も履歴が残ります。",
      },
      {
        id: "reapply",
        title: "適用したままに",
        body: "再起動・ログイン・ポインター設定の変更で戻ってしまっても、バックグラウンドのヘルパーが再適用。失敗が続くときは理由を示して一時停止します。",
      },
      {
        id: "diagnose",
        title: "診断と復元",
        body: "保存済みの標準カーソルへ、アプリ・メニューバー・CLI から戻せます。アプリが開かなくても大丈夫。診断レポートは設定から書き出せます。",
      },
    ],
  },
  showcase: {
    compareTitle: "適用する前に、違いを体感する。",
    compareBody:
      "適用ボタンの隣の「試してみる」から、+ でテーマを足して、サンプル領域を行き来して比べます。大きさもテーマごとに調整でき、決めるまでシステムのカーソルは変わりません。",
    compareAlt:
      "2つのカーソルテーマを左右に並べ、文字・リンク・クリック対象・個別の大きさ調整を表示している画面",
    replaceTitle: "1つのカーソルだけ差し替える。",
    replaceBody:
      "カーソルのタイルをクリックし、ほかのライブラリのテーマや GIF / PNG から選びます。保存前に「現在」と「変更後」を見比べられます。",
    replaceAlt:
      "Precision カーソルをほかのテーマのものへ差し替え、変更前後をプレビューしている画面",
    credit: "表示中のアンバーのカーソル: Bibata Modern Amber",
    creditUrl: "https://github.com/ful1e5/Bibata_Cursor",
  },
  install: {
    title: "インストール",
    lead: "Apple Silicon のみ対応です。",
    brew: "Homebrew",
    manual: "手動",
    copy: "コピー",
    copied: "コピーしました",
    steps: [
      "Releases から最新の Curstyle-macos-vX.Y.Z.dmg をダウンロードします。",
      "DMG を開き、Curstyle.app を「アプリケーション」へ移動します。",
      "「アプリケーション」から Curstyle を起動します。",
    ],
    warningTitle: "初回起動時の警告",
    warning:
      "Curstyle は Apple の公証を受けずに配布しているため、macOS がセキュリティ警告を出すことがあります。起動を試みたあと、システム設定 → プライバシーとセキュリティで Curstyle の「このまま開く」を選び、案内に従ってください。",
    releases: "Releases",
    latest: (version: string, date: string) => `最新: v${version} · ${date}`,
  },
  faq: {
    title: "FAQ",
    items: [
      {
        q: "安全ですか?元のカーソルに戻せますか?",
        a: "はい。適用の前に標準のカーソルを保存します。アプリやメニューバーの「標準に戻す」、アプリが開かないときは同梱 CLI の restore で戻せます。適用に失敗したときは、登録された画像がテーマと一致するかを確認し、標準の復元も試みます。",
      },
      {
        q: "対応する Mac と macOS は?",
        a: "配布版は Apple Silicon のみです。デプロイ対象は macOS 14 ですが、macOS の非公開 API を使うため、OS の更新で動かなくなる可能性があります。動作確認は Apple Silicon の macOS 27.2 で、Intel は未確認です。",
      },
      {
        q: "開くときに macOS が警告するのはなぜ?",
        a: "Apple の公証を受けずに配布しているためです。初回の起動を試みたあと、システム設定 → プライバシーとセキュリティで「このまま開く」を選んでください。アップデートは署名を検証してから置き換えられます。",
      },
      {
        q: "カーソルが変わりません。",
        a: "システム設定 → アクセシビリティ → ディスプレイ → ポインターで、ポインターの色を初期状態に戻してください。色をカスタマイズ中は適用を拒否し、診断画面で状態を説明します。⌘⇧4 のスクリーンショット用十字など、ほかのアプリが独自に登録するカーソルは置き換えられません。",
      },
      {
        q: "取り込める形式は?",
        a: "Windows の .cur / .ani を含むフォルダ、Mousecape の .cape、Curstyle の theme.json を含むフォルダです。GIF / PNG は、テーマ内の個別カーソルの差し替えや追加に使えます。",
      },
    ],
  },
  footer: {
    github: "GitHub",
    releases: "Releases",
    license: "MIT ライセンス",
    note: "Apple および macOS は Apple Inc. の商標です。Curstyle は Apple とは無関係です。",
  },
};

export const dictionaries = { ja, en } as const;
export type Lang = keyof typeof dictionaries;
export type { Dict };

export const repo = "https://github.com/Narcissus-tazetta/Curstyle";
export const brewCommand = "brew install --cask narcissus-tazetta/tap/curstyle";
export const siteUrl = "https://curstyle.prason.dev";
