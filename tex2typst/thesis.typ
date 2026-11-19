// =============================================================
//  博士論文 Typst テンプレート（tex2typst 用）
//  余白・フォント・見出しの見た目などを変えたいときはここを編集します。
// =============================================================

// 欧文は Computer Modern、和文は游明朝／游ゴシック（無ければ Noto, MS にフォールバック）
#let serif-fonts = ("New Computer Modern", "Yu Mincho", "Noto Serif JP", "MS Mincho")
#let sans-fonts = ("New Computer Modern", "Yu Gothic", "Noto Sans JP", "MS Gothic")
#let mono-fonts = ("DejaVu Sans Mono", "MS Gothic")

#let in-appendix = state("tex2typst-appendix", false)

// 章番号（本文: 1, 2, ... / 付録: A, B, ...）
#let chapter-num() = {
  let ch = counter(heading).get().at(0, default: 0)
  if in-appendix.get() { numbering("A", ch) } else { str(ch) }
}

// 「章.番号」形式（図 1.2、式 (1.2) など）
#let per-chapter(n) = chapter-num() + "." + str(n)

// \appendix 以降
#let appendix(body) = {
  in-appendix.update(true)
  counter(heading).update(0)
  set heading(numbering: "A.1")
  body
}

// 本文（ページ番号をアラビア数字 1 から）
#let mainmatter(body) = {
  set page(numbering: "1")
  counter(page).update(1)
  body
}

#let cover(title, entitle, author, degree, university, department, conferral) = page(numbering: none, {
  set align(center)
  set par(first-line-indent: 0pt, justify: false)
  v(3cm)
  if title != none { text(size: 22pt, font: sans-fonts, weight: "bold", title) }
  if entitle != none { v(1.2em); text(size: 15pt, entitle) }
  v(1fr)
  if author != none { text(size: 18pt, author) }
  v(1fr)
  if degree != none { text(size: 16pt, degree) }
  v(1.5cm)
  text(size: 16pt, {
    if university != none { university; linebreak() }
    if department != none { department }
  })
  v(1.5cm)
  if conferral != none { text(size: 16pt, conferral) }
  v(2cm)
})

#let thesis(
  maketitle: false,
  title: none,
  entitle: none,
  author: none,
  date: none,
  degree: none,
  university: none,
  department: none,
  conferral: none,
  body,
) = {
  set document(title: title)
  set page(paper: "a4", margin: (x: 30mm, top: 30mm, bottom: 30mm), numbering: none)
  set text(font: serif-fonts, size: 11pt, lang: "ja", region: "JP")
  set par(justify: true, leading: 0.95em, spacing: 0.95em,
          first-line-indent: (amount: 1em, all: true))

  // 太字の和文はゴシックに（LaTeX の jsclass と同じ流儀）
  show strong: set text(font: sans-fonts)
  show raw: set text(font: mono-fonts, size: 1.1em)
  show link: set text(fill: rgb("#1a4d8f"))

  // ---- 見出し ----
  set heading(numbering: "1.1")
  show heading: set text(font: sans-fonts, weight: "bold")
  show heading: set par(first-line-indent: 0pt)
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    counter(math.equation).update(0)
    counter(figure.where(kind: image)).update(0)
    counter(figure.where(kind: table)).update(0)
    v(2.5em)
    block(width: 100%, below: 2.5em, {
      if it.numbering != none {
        text(size: 15pt, context {
          if in-appendix.get() [付録 #chapter-num()] else [第 #chapter-num() 章]
        })
        v(0.4em)
      }
      text(size: 22pt, it.body)
    })
  }
  show heading.where(level: 2): set text(size: 14pt)
  show heading.where(level: 2): set block(above: 2em, below: 1.1em)
  show heading.where(level: 3): set text(size: 12pt)
  show heading.where(level: 3): set block(above: 1.6em, below: 0.9em)

  // ---- 数式（章ごとの番号 (1.1)）----
  set math.equation(numbering: n => "(" + per-chapter(n) + ")", supplement: none)

  // ---- 図表（章ごとの番号 図 1.1）----
  set figure(numbering: n => per-chapter(n), gap: 0.9em)
  set figure.caption(separator: [#h(1em)])
  show figure.caption: set text(size: 0.95em)
  show figure.where(kind: table): set figure.caption(position: top)
  show figure: set block(breakable: false, above: 1.8em, below: 1.8em)

  // booktabs 風の表（上下に太線、ヘッダ下に細線）
  set table(stroke: none, inset: (x: 0.8em, y: 0.45em))
  set table.hline(stroke: 0.5pt)
  show table: t => block(stroke: (top: 1pt, bottom: 1pt), inset: (y: 0.15em), t)

  // ---- 参考文献（LaTeX の unsrt 等と同じく英語表記: vol., pp. など）----
  set bibliography(title: [参考文献])
  show bibliography: set text(lang: "en", region: none)
  show bibliography: set par(first-line-indent: 0pt)

  // ---- 目次 ----
  show outline.entry.where(level: 1): it => {
    v(0.9em, weak: true)
    strong(it)
  }

  // ---- 箇条書き ----
  set list(indent: 1em)
  set enum(indent: 1em)

  if maketitle {
    cover(title, entitle, author, degree, university, department, conferral)
  }

  // 前付け（要旨・目次）はローマ数字
  set page(numbering: "i")
  counter(page).update(1)
  body
}
