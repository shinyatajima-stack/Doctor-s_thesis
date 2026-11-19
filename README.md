# 博士論文（.tex で書いて Typst で高速ビルド）

いつもどおり **LaTeX（.tex）で書く** だけで、裏で Typst に自動変換して一瞬で PDF を作ります。
同じ .tex は本物の LaTeX でもそのままコンパイルできるので、最終提出版は LaTeX で作ることもできます。

## VS Code（LaTeX Workshop）で使う ← 普段はこれ

このフォルダを VS Code で開けば、`.vscode/settings.json` により

- **保存するだけ** で Typst ビルド（約 0.2 秒）→ タブ内の PDF ビューアが自動更新
- 最終版を LaTeX で作るとき：サイドバーの TeX アイコン → *Build LaTeX project* →
  **Recipe: LuaLaTeX（最終版）** をクリック（約 12 秒）

どちらも出力は `thesis.pdf`（最後にビルドした方）。Typst 版は SyncTeX（PDF↔ソースのジャンプ）非対応です。

## コマンドラインで使う

| 方法 | コマンド | 出力 | 速さ（サンプル） |
|---|---|---|---|
| Typst で 1 回ビルド | `build.bat` | `thesis-typst.pdf` | 約 0.2 秒 |
| Typst で自動ビルド（保存するたび） | `watch.bat` | `thesis-typst.pdf` | 保存後 0.1 秒ほど |
| 本物の LaTeX（最終確認用） | `latexmk thesis.tex` | `thesis.pdf` | 約 12 秒 |

> PDF ビューアは **SumatraPDF** や VS Code など、ファイル更新を自動で読み直すものがおすすめ。
> Adobe Reader は PDF をロックするので、開いたままだと上書きできません。

## ファイル構成

```
thesis.tex          メイン（表紙情報・章の \include）
chapters/*.tex      各章
refs.bib            参考文献
figures/            図（PNG / JPG / PDF / SVG）
thesismeta.sty      表紙用コマンド（\degree など。LaTeX 用）
tex2typst/          変換システム本体
  build.py            ビルドスクリプト
  filter.lua          LaTeX→Typst の差分を吸収する Pandoc フィルタ
  thesis.typ          ★ Typst 版のレイアウト（余白・フォント・見出し等はここを編集）
_build/thesis.typ   自動生成された Typst ファイル（編集しない）
```

## 対応しているもの

- `\chapter` `\section` `\subsection`（`*` 付きは番号なし・目次に載らない。`\addcontentsline` で載る）
- `\label` / `\ref` / `\eqref` / `\pageref` / `\autoref` / `\cref` — 「第\ref{chap:x}章」の書き方でOK
- 数式全般（`equation`, `align`, `gather`, `\[ \]`, `*` 付き）、`\newcommand` の自作マクロ（自作 .sty 内も可）
- 図（`figure` + `\includegraphics`、拡張子省略可）、表（`table` + `tabular`, booktabs）
- `\cite` / `\citep` / `\citet`（`.bib` をそのまま利用）、`\bibliographystyle`（unsrt, plain, IEEEtran, apalike など）
- `\footnote`、`itemize` / `enumerate` / `description`、`\textbf` 等の装飾、`\url` / `\href`、`verbatim`
- `\tableofcontents` `\listoffigures` `\listoftables` `\appendix` `\mainmatter` `\clearpage` `\vspace` `\hspace`
- `\include` / `\input` / `\includeonly`（`\includeonly{chapters/method}` で一部の章だけビルド）
- 番号は章ごと：式 (2.1)、図 2.1、表 2.1、付録は A.1

## 制限（Typst 版プレビューでの違い）

- `align` など複数行の数式は **ブロック全体で 1 つの番号** になります（LaTeX は行ごと）。
  2 個目以降の `\label` は 1 個目と同じ番号を指します。
- TikZ、EPS 画像、独自の環境・複雑なマクロ（`\def`, `\if` 等）は変換できません。
  無視したものはビルド時に `[tex2typst] 警告:` として表示されます。EPS は同名の PDF/PNG があれば自動で使います。
- 未定義の `\ref` は **??**、`.bib` にない `\cite` は **[?key]** と表示されます（ビルドは止まりません）。
- 参考文献の書式は Typst 組み込みのスタイルで近似しています（LaTeX 版と細部は異なります）。
- 見た目は LaTeX 版と完全には一致しません。**執筆中は Typst 版、最終提出は LaTeX 版** という使い分けを想定しています。

## 初回セットアップ（別の PC で使う場合）

```
winget install Typst.Typst
winget install JohnMacFarlane.Pandoc
```
Python 3.8 以上が必要です。
