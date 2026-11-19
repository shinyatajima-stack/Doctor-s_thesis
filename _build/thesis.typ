// このファイルは tex2typst/build.py が自動生成します。直接編集しないでください。
#import "/tex2typst/thesis.typ": *

#show: thesis.with(
  maketitle: true,
  title: [〇〇〇〇に関する研究],
  entitle: [A Study on XXXX],
  author: [総研　太郎],
  degree: [博士（〇〇）],
  university: [総合研究大学院大学],
  department: [先端学術院　〇〇コース],
  conferral: [2027年3月],
)

#heading(level: 1, numbering: none, outlined: false)[要旨]
本論文では，〇〇〇〇について研究する．
第#ref(label("chap:intro"), supplement: none);章で背景を述べ，第#ref(label("chap:method"), supplement: none);章で提案手法を示す．

#outline()
#show: mainmatter
= 序論
<chap:intro>
== 研究背景
<sec:background>
近年，〇〇の研究が盛んである#cite(label("einstein1905"));#cite(label("knuth1984"));．
特に#strong[太字]や#emph[イタリック]，#emph[強調]，`等幅`も使える．
脚注も書ける#footnote[これは脚注です．]．

=== 箇条書き
- 一つ目の項目

- 二つ目の項目

  + 入れ子の番号付き

  + もう一つ

== 本論文の構成
本論文の構成は以下のとおりである．
第#ref(label("chap:method"), supplement: none);章の式#ref(label("eq:euler"), supplement: none);と図#ref(label("fig:sample"), supplement: none);，表#ref(label("tab:result"), supplement: none);を参照．
節#ref(label("sec:background"), supplement: none);も参照できる．

= 提案手法
<chap:method>
== 数式
インライン数式 $E = m c^2$ や $bold(x) in bb(R)^n$ が書ける．
別行立て数式：
$ e^(i pi) + 1 = 0 $<eq:euler>
複数行の数式：
$ f\(x\) & = sum_(k = 0)^oo frac(x^k, k !)\
frac(upright(d) f, upright(d) x) & = f\(x\) $<eq:exp>
番号なし：
#[#set math.equation(numbering: none)
$ integral_0^1 x^2 thin upright(d) x = 1 / 3 $
]
式#ref(label("eq:exp"), supplement: none);は指数関数である．

== 図と表
#figure([#box(image("/figures/sample.png", width: 50.0%))],
  caption: [
    サンプル図
  ]
)
<fig:sample>

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,center,center,),
    table.header([手法], [精度], [時間 \[s\]],),
    table.hline(),
    [従来手法], [0.85], [12.3],
    [提案手法], [#strong[0.92]], [8.1],
  )]
  , caption: [実験結果]
  , kind: table
  )
<tab:result>

= 結論
<chap:conclusion>
本論文では，〇〇を提案した．式#ref(label("eq:euler"), supplement: none);が重要である#cite(label("einstein1905"));．

#bibliography(("/refs.bib",), style: "elsevier-with-titles")
#show: appendix
= 補足資料
<chap:appendix>
ここに付録を書く．
