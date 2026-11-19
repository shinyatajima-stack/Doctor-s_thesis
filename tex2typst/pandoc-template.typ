// このファイルは tex2typst/build.py が自動生成します。直接編集しないでください。
#import "$tex2typst-template$": *

#show: thesis.with(
$if(maketitle)$
  maketitle: true,
$endif$
$if(title)$
  title: [$title$],
$endif$
$if(entitle)$
  entitle: [$entitle$],
$endif$
$if(author)$
  author: [$author$],
$endif$
$if(date)$
  date: [$date$],
$endif$
$if(degree)$
  degree: [$degree$],
$endif$
$if(university)$
  university: [$university$],
$endif$
$if(department)$
  department: [$department$],
$endif$
$if(conferral)$
  conferral: [$conferral$],
$endif$
)

$body$
