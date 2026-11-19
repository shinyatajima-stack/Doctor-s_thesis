#!/usr/bin/env python3
"""tex2typst — .tex を書いたまま Typst で高速に PDF を作るビルドスクリプト.

    python tex2typst/build.py thesis.tex           # 1回ビルド
    python tex2typst/build.py thesis.tex --watch   # 保存するたびに自動ビルド

処理の流れ:
  1. \\input / \\include を展開し、コメントを除去（\\includeonly にも対応）
  2. 表紙情報・参考文献・数式番号などを Pandoc が扱える形に前処理
  3. Pandoc (+ filter.lua) で LaTeX → Typst に変換  → _build/<name>.typ
  4. Typst でコンパイル                              → <name>-typst.pdf
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent

# 表紙に使う情報（プリアンブルの \title{...} などから読み取る）
META_KEYS = ["title", "entitle", "author", "date", "degree", "university",
             "department", "conferral"]

# 番号付きになる数式環境（* 付きは番号なし）
NUMBERED_MATH_ENVS = ["equation", "align", "gather", "multline", "flalign",
                      "eqnarray", "alignat"]

# LaTeX の bibliographystyle → Typst の組み込みスタイル
#   番号順で [1,2] のようにまとまるものは elsevier-with-titles を使う
#   （Typst の ieee スタイルは [1], [2] と分かれるため）
NUMERIC = "elsevier-with-titles"
BIBSTYLE_MAP = {
    "unsrt": NUMERIC, "unsrtnat": NUMERIC, "junsrt": NUMERIC, "plain": NUMERIC,
    "jplain": NUMERIC, "abbrv": NUMERIC, "splncs04": NUMERIC,
    "ieeetr": "ieee", "IEEEtran": "ieee",
    "alpha": "alphanumeric", "apalike": "apa", "apa": "apa", "jecon": "apa",
    "plainnat": "apa", "abbrvnat": "apa", "chicago": "chicago-author-date",
}

for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def log(msg: str) -> None:
    print(f"[tex2typst] {msg}", flush=True)


# --------------------------------------------------------------------------
# ツール探索（winget で入れた直後は PATH が未反映なことがあるので直接探す）
# --------------------------------------------------------------------------
def find_tool(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    la = os.environ.get("LOCALAPPDATA", "")
    cands: list[str] = []
    if name == "typst":
        cands += glob.glob(os.path.join(la, "Microsoft", "WinGet", "Packages",
                                        "Typst.Typst*", "**", "typst.exe"), recursive=True)
        cands += [os.path.join(la, "Microsoft", "WinGet", "Links", "typst.exe")]
    elif name == "pandoc":
        cands += [os.path.join(la, "Pandoc", "pandoc.exe"),
                  r"C:\Program Files\Pandoc\pandoc.exe"]
    for c in cands:
        if os.path.isfile(c):
            return c
    sys.exit(f"[tex2typst] {name} が見つかりません。インストールしてください: "
             f"winget install {'Typst.Typst' if name == 'typst' else 'JohnMacFarlane.Pandoc'}")


# --------------------------------------------------------------------------
# 1. ファイル展開
# --------------------------------------------------------------------------
VERBATIM_ENVS = ("verbatim", "Verbatim", "lstlisting", "minted", "comment")


def strip_comments(text: str) -> str:
    """% コメントを除去（LaTeX と同じく、行末の改行もコメントの一部として消す）."""
    out: list[str] = []
    in_verb = None
    for line in text.splitlines(keepends=True):
        if in_verb:
            out.append(line)
            if re.search(r"\\end\{" + re.escape(in_verb) + r"\}", line):
                in_verb = None
            continue
        m = re.search(r"\\begin\{(" + "|".join(VERBATIM_ENVS) + r")\}", line)
        if m:
            in_verb = m.group(1)
            out.append(line)
            continue
        c = re.search(r"(?<!\\)%", line)
        if c:
            before = line[: c.start()]
            # 行全体がコメントなら行ごと消す。途中からなら改行も食う（LaTeX と同じ）
            out.append("" if before.strip() == "" else before)
        else:
            out.append(line)
    return "".join(out)


class Expander:
    INC = re.compile(r"\\(input|include|subfile)\s*\{([^}]*)\}")

    def __init__(self, root: Path):
        self.root = root
        self.files: list[Path] = []
        self.includeonly: set[str] | None = None

    def resolve(self, name: str) -> Path | None:
        for cand in (name, name + ".tex"):
            p = (self.root / cand)
            if p.is_file():
                return p
        return None

    def expand(self, path: Path, depth: int = 0) -> str:
        if depth > 20:
            sys.exit("[tex2typst] \\input の入れ子が深すぎます（循環していませんか？）")
        self.files.append(path)
        text = strip_comments(path.read_text(encoding="utf-8-sig"))
        if depth == 0:
            m = re.search(r"\\includeonly\s*\{([^}]*)\}", text)
            if m:
                self.includeonly = {s.strip() for s in m.group(1).split(",") if s.strip()}
                text = text[: m.start()] + text[m.end():]

        def rep(m: re.Match) -> str:
            kind, name = m.group(1), m.group(2).strip()
            if kind == "include" and self.includeonly is not None and name not in self.includeonly:
                return ""
            p = self.resolve(name)
            if p is None:
                log(f"警告: {name} が見つかりません（{path.name}）")
                return ""
            body = self.expand(p, depth + 1)
            return f"\n{body}\n" if kind == "include" else body

        return self.INC.sub(rep, text)


# --------------------------------------------------------------------------
# 2. 前処理
# --------------------------------------------------------------------------
def brace_arg(text: str, pos: int) -> tuple[str, int] | None:
    """text[pos] が '{' のとき、対応する '}' までの中身と終了位置を返す."""
    if pos >= len(text) or text[pos] != "{":
        return None
    depth = 0
    for i in range(pos, len(text)):
        ch = text[i]
        if ch == "\\":
            continue
        if ch == "{" and (i == 0 or text[i - 1] != "\\"):
            depth += 1
        elif ch == "}" and text[i - 1] != "\\":
            depth -= 1
            if depth == 0:
                return text[pos + 1: i], i + 1
    return None


def pop_command(text: str, name: str) -> tuple[str, list[str]]:
    """\\name{arg} をすべて取り除き、(残りのテキスト, 引数のリスト) を返す."""
    args: list[str] = []
    pat = re.compile(r"\\" + name + r"(?![A-Za-z@])\s*(\[[^\]]*\])?\s*")
    pos = 0
    out = []
    while True:
        m = pat.search(text, pos)
        if not m:
            break
        a = brace_arg(text, m.end())
        if a is None:
            out.append(text[pos: m.end()])
            pos = m.end()
            continue
        out.append(text[pos: m.start()])
        args.append(a[0])
        pos = a[1]
    out.append(text[pos:])
    return "".join(out), args


def preprocess(src: str) -> tuple[str, list[str]]:
    pre, sep, body = src.partition("\\begin{document}")
    if not sep:
        sys.exit("[tex2typst] \\begin{document} が見つかりません")

    # 表紙用パッケージは Pandoc に読ませない（\maketitle を再定義しているため）
    pre = re.sub(r"\\usepackage(\[[^\]]*\])?\{thesismeta\}", "", pre)

    # 自作 .sty（同じフォルダにあるもの）は中身を展開して \newcommand を有効にする
    def sty_rep(m: re.Match) -> str:
        keep, inline = [], []
        for name in (n.strip() for n in m.group(2).split(",")):
            p = Path.cwd() / (name + ".sty")
            (inline if name and p.is_file() else keep).append(name)
        out = "".join(strip_comments(p.read_text(encoding="utf-8-sig")) + "\n"
                      for p in (Path.cwd() / (n + ".sty") for n in inline))
        if keep:
            out = f"\\usepackage{m.group(1) or ''}{{{','.join(keep)}}}\n" + out
        return out

    pre = re.sub(r"\\usepackage(\[[^\]]*\])?\{([^}]*)\}", sty_rep, pre)

    meta: dict[str, str] = {}
    for key in META_KEYS:
        pre, args = pop_command(pre, key)
        if args:
            meta[key] = args[-1]

    # 参考文献
    src_all = pre + body
    style = NUMERIC
    _, styles = pop_command(src_all, "bibliographystyle")
    pre, _ = pop_command(pre, "bibliographystyle")
    body, _ = pop_command(body, "bibliographystyle")
    if styles:
        name = styles[-1].strip()
        if name.endswith(".csl") and (Path.cwd() / name).is_file():
            style = "/" + name                     # 自前の CSL ファイルも使える
        else:
            style = BIBSTYLE_MAP.get(name, NUMERIC)
    bibfiles: list[str] = []
    pre, resources = pop_command(pre, "addbibresource")          # biblatex
    bibfiles += [r.strip() for r in resources]

    def bib_rep(m: re.Match) -> str:
        files = [f.strip() for f in m.group(1).split(",") if f.strip()]
        files = [f if f.endswith(".bib") else f + ".bib" for f in files]
        bibfiles.extend(files)
        return "\n\n\\typstbibliography{" + ";".join(files) + "}{" + style + "}\n\n"

    body = re.sub(r"\\bibliography\s*\{([^}]*)\}", bib_rep, body)
    body = re.sub(r"\\printbibliography(\[[^\]]*\])?",
                  lambda m: "\n\n\\typstbibliography{" + ";".join(resources) + "}{" + style + "}\n\n",
                  body)

    # 番号付き数式に目印を付ける（Pandoc は \[ \] と equation を区別しないため）
    env_re = r"\\begin\{(" + "|".join(NUMBERED_MATH_ENVS) + r")\}"
    body = re.sub(env_re, lambda m: m.group(0) + r"\typstnum ", body)

    # 表紙
    if re.search(r"\\maketitle(?![A-Za-z])", body):
        body = re.sub(r"\\maketitle(?![A-Za-z])", "", body)
        meta["maketitle"] = "true"

    def clean(v: str) -> str:
        v = re.sub(r"\\qquad(?![A-Za-z])\s*", "\u3000\u3000", v)
        return re.sub(r"\\quad(?![A-Za-z])\s*", "\u3000", v)

    head = "".join(f"\n\\typstmeta{{{k}}}{{{clean(v)}}}\n" for k, v in meta.items())
    return pre + sep + "\n" + head + "\n" + body, bibfiles


# --------------------------------------------------------------------------
# 3, 4. 変換とコンパイル
# --------------------------------------------------------------------------
class Builder:
    def __init__(self, main: Path, pdf: Path):
        self.main = main
        self.root = main.parent
        self.pdf = pdf
        self.build_dir = self.root / "_build"
        self.build_dir.mkdir(exist_ok=True)
        self.typ = self.build_dir / (main.stem + ".typ")
        self.pandoc = find_tool("pandoc")
        self.typst = find_tool("typst")
        try:
            rel = HERE.relative_to(self.root).as_posix()
        except ValueError:
            sys.exit("[tex2typst] tex2typst フォルダはメインの .tex と同じフォルダ（以下）に置いてください")
        self.template_import = f"/{rel}/thesis.typ"

    def convert(self) -> bool:
        t0 = time.perf_counter()
        os.chdir(self.root)
        exp = Expander(self.root)
        src = exp.expand(self.main)
        src, bibfiles = preprocess(src)
        cmd = [
            self.pandoc, "-f", "latex+raw_tex-auto_identifiers", "-t", "typst",
            "--wrap=preserve",
            "--template", str(HERE / "pandoc-template.typ"),
            "--lua-filter", str(HERE / "filter.lua"),
            "-M", "tex2typst-bibfiles=" + ";".join(bibfiles),
            "-V", "tex2typst-template=" + self.template_import,
        ]
        proc = subprocess.run(cmd, input=src.encode("utf-8"), capture_output=True,
                              cwd=self.root)
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        if err:
            for line in err.splitlines():
                if not line.startswith("[INFO]"):
                    print(line, flush=True)
        if proc.returncode != 0:
            log("Pandoc での変換に失敗しました")
            return False
        out = proc.stdout.decode("utf-8")
        old = self.typ.read_text(encoding="utf-8") if self.typ.exists() else None
        if out != old:
            tmp = self.typ.with_suffix(".typ.tmp")
            tmp.write_text(out, encoding="utf-8", newline="\n")
            os.replace(tmp, self.typ)
        log(f"変換完了 ({time.perf_counter() - t0:.2f}s) → {self.typ.relative_to(self.root)}")
        return True

    def typst_args(self) -> list[str]:
        return ["--root", str(self.root), str(self.typ), str(self.pdf)]

    def compile(self) -> bool:
        t0 = time.perf_counter()
        proc = subprocess.run([self.typst, "compile", *self.typst_args()], cwd=self.root)
        if proc.returncode == 0:
            log(f"PDF 作成完了 ({time.perf_counter() - t0:.2f}s) → {self.pdf.name}")
            return True
        log(f"Typst のエラーです。行番号は {self.typ.relative_to(self.root)} のものです")
        return False

    def watched_files(self) -> dict[str, float]:
        sig: dict[str, float] = {}
        for ext in ("*.tex", "*.sty", "*.cls"):
            for p in self.root.rglob(ext):
                if "_build" in p.parts:
                    continue
                try:
                    sig[str(p)] = p.stat().st_mtime
                except OSError:
                    pass
        return sig

    def watch(self) -> None:
        self.convert()
        proc = subprocess.Popen([self.typst, "watch", *self.typst_args()], cwd=self.root)
        log("監視中… .tex を保存すると自動で PDF を更新します（終了は Ctrl+C）")
        last = self.watched_files()
        try:
            while True:
                time.sleep(0.25)
                now = self.watched_files()
                if now != last:
                    last = now
                    time.sleep(0.05)  # エディタの書き込み完了を待つ
                    try:
                        self.convert()
                    except Exception as e:  # 監視は止めない
                        log(f"変換中にエラー: {e}")
                if proc.poll() is not None:
                    log("typst watch が終了しました")
                    break
        except KeyboardInterrupt:
            pass
        finally:
            if proc.poll() is None:
                proc.terminate()


def main() -> None:
    ap = argparse.ArgumentParser(description=".tex を Typst で高速コンパイル")
    ap.add_argument("main", nargs="?", default="thesis.tex", help="メインの .tex ファイル")
    ap.add_argument("--watch", "-w", action="store_true", help="保存するたびに自動ビルド")
    ap.add_argument("--output", "-o", help="出力 PDF（既定: <名前>-typst.pdf）")
    args = ap.parse_args()

    main_tex = Path(args.main).resolve()
    if not main_tex.is_file():
        sys.exit(f"[tex2typst] {args.main} が見つかりません")
    pdf = Path(args.output).resolve() if args.output else main_tex.with_name(main_tex.stem + "-typst.pdf")
    b = Builder(main_tex, pdf)
    if args.watch:
        b.watch()
    else:
        ok = b.convert() and b.compile()
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
