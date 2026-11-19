# 本物の LaTeX（LuaLaTeX）で最終版を作るとき:  latexmk thesis.tex
# 中間ファイルは _latex/ に、PDF は thesis.pdf（このフォルダ）に出ます
$pdf_mode = 4;          # lualatex
$bibtex_use = 2;
$aux_dir = '_latex';
$out_dir = '.';
