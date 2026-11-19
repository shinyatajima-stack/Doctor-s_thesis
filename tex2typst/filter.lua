-- ==========================================================================
--  tex2typst/filter.lua
--  Pandoc の LaTeX → Typst 変換で足りない部分を補う Lua フィルタ
--    * \ref, \eqref, \pageref, \autoref → Typst の ref（「第\ref{x}章」でも壊れない形）
--    * \cite → #cite（存在しないキーは ?? 表示にしてコンパイルを止めない）
--    * 番号なし数式 (\[ \], equation*, align*) の区別
--    * \tableofcontents, \appendix, \clearpage, \vspace など
--    * 表紙情報 (\title, \degree, ...) をテンプレートへ渡す
-- ==========================================================================
local stringify = pandoc.utils.stringify

local warned = {}
local function warn(msg)
  if not warned[msg] then
    warned[msg] = true
    io.stderr:write('[tex2typst] 警告: ' .. msg .. '\n')
  end
end

-- Typst の文字列リテラル
local function q(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  return '"' .. s .. '"'
end

local function raw(s) return pandoc.RawInline('typst', s) end

local function write_inlines(inlines)
  local out = pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), 'typst')
  return (out:gsub('%s+$', ''))
end

local function file_exists(p)
  local f = io.open(p, 'rb')
  if f then f:close() return true end
  return false
end

-- --------------------------------------------------------------------------
-- 状態
-- --------------------------------------------------------------------------
local defined = {}      -- 定義済みラベル
local alias = {}        -- 同じ数式ブロック内の 2 個目以降の \label → 1 個目
local meta_vals = {}    -- \typstmeta{key}{value}
local bibkeys = {}      -- .bib に存在するキー
local has_bib = false

local state = {
  mainmatter_done = false,
  explicit_mainmatter = false,
  last_unnumbered = nil,  -- 直前の番号なし見出し（\addcontentsline 用）
}

-- --------------------------------------------------------------------------
-- LaTeX コマンド → Typst
-- --------------------------------------------------------------------------
local function parse_cmd(s)
  s = s:gsub('^%s+', '')
  local name, rest = s:match('^\\([%a@]+%*?)(.*)$')
  if not name then
    name, rest = s:match('^\\(.)(.*)$')   -- \, \; \! など 1 文字コマンド
    if not name then return nil end
  end
  local args = {}
  while true do
    rest = rest:gsub('^%s*', '')
    local a = rest:match('^%b{}') or rest:match('^%b[]')
    if not a then break end
    table.insert(args, a:sub(2, -2))
    rest = rest:sub(#a + 1)
  end
  return name, args, rest
end

local function length(x)
  x = (x or ''):gsub('%s', '')
  if x:match('\\fill') or x:match('\\stretch') then return '1fr' end
  local n, u = x:match('^(%-?[%d%.]+)(%a+)$')
  if not n then return nil end
  local units = { cm = 'cm', mm = 'mm', pt = 'pt', bp = 'pt', em = 'em', ['in'] = 'in',
                  zw = 'em', zh = 'em' }
  if u == 'ex' then return tostring(tonumber(n) * 0.5) .. 'em' end
  if units[u] then return n .. units[u] end
  return nil
end

-- 黙って捨ててよいコマンド
local ignore = {}
for _, c in ipairs({
  'centering', 'noindent', 'indent', 'raggedright', 'raggedleft', 'par', 'maketitle',
  'makeatletter', 'makeatother', 'frontmatter', 'backmatter', 'pagestyle', 'thispagestyle',
  'tiny', 'scriptsize', 'footnotesize', 'small', 'normalsize', 'large', 'Large', 'LARGE',
  'huge', 'Huge', 'bibliographystyle', 'label', 'phantomsection', 'hline', 'toprule',
  'midrule', 'bottomrule', 'sloppy', 'fussy', 'nopagebreak', 'setlength', 'addtolength',
  'setcounter', 'addtocounter', 'graphicspath', 'captionsetup', 'FloatBarrier',
  'raggedbottom', 'flushbottom', 'onehalfspacing', 'doublespacing', 'singlespacing',
  'hypersetup', 'urlstyle', 'selectlanguage', 'linespread', 'selectfont', 'protect',
  'relax', 'null', 'leavevmode', 'nocite', 'typstnum', 'cleardoublepage*',
}) do ignore[c] = true end

local convert_cmd  -- forward

-- 相互参照: kind = ref / eqref / pageref / autoref ...
local function ref_typst(kind, key)
  key = (key or ''):gsub('^%s+', ''):gsub('%s+$', '')
  key = alias[key] or key
  if not defined[key] then
    warn('未定義のラベル ' .. key .. ' への参照があります（?? と表示）')
    return '#strong[??]'
  end
  local lab = 'label(' .. q(key) .. ')'
  if kind == 'ref' or kind == 'eqref' then
    return '#ref(' .. lab .. ', supplement: none)'
  elseif kind == 'pageref' then
    return '#context counter(page).at(' .. lab .. ').first()'
  else
    return '#ref(' .. lab .. ')'
  end
end

local function multi_ref(kind)
  return function(a)
    local out = {}
    for k in (a[#a] or ''):gmatch('[^,]+') do table.insert(out, ref_typst(kind, k)) end
    return table.concat(out, ';, ')
  end
end

local handlers = {
  ref = multi_ref('ref'),
  eqref = multi_ref('eqref'),
  pageref = multi_ref('pageref'),
  autoref = multi_ref('autoref'),
  cref = multi_ref('autoref'),
  Cref = multi_ref('autoref'),
  typstmeta = function(a) meta_vals[a[1]] = a[2]; return '' end,
  tableofcontents = function() return '#outline()' end,
  listoffigures = function() return '#outline(title: [図目次], target: figure.where(kind: image))' end,
  listoftables = function() return '#outline(title: [表目次], target: figure.where(kind: table))' end,
  clearpage = function() return '#pagebreak(weak: true)' end,
  newpage = function() return '#pagebreak(weak: true)' end,
  cleardoublepage = function() return '#pagebreak(weak: true, to: "odd")' end,
  pagebreak = function() return '#pagebreak(weak: true)' end,
  appendix = function() return '#show: appendix' end,
  mainmatter = function()
    state.mainmatter_done = true
    return '#show: mainmatter'
  end,
  vspace = function(a)
    local l = length(a[1]); if l then return '#v(' .. l .. ')' end
    warn('\\vspace{' .. (a[1] or '') .. '} の長さを解釈できないので無視しました')
    return ''
  end,
  hspace = function(a)
    local l = length(a[1]); if l then return '#h(' .. l .. ')' end
    warn('\\hspace{' .. (a[1] or '') .. '} の長さを解釈できないので無視しました')
    return ''
  end,
  vfill = function() return '#v(1fr)' end,
  hfill = function() return '#h(1fr)' end,
  smallskip = function() return '#v(0.3em)' end,
  medskip = function() return '#v(0.6em)' end,
  bigskip = function() return '#v(1.2em)' end,
  quad = function() return '#h(1em)' end,
  qquad = function() return '#h(2em)' end,
  [','] = function() return '#h(0.17em)' end,
  [';'] = function() return '#h(0.28em)' end,
  [' '] = function() return ' ' end,
  ['\\'] = function() return '#linebreak()' end,
  newline = function() return '#linebreak()' end,
  linebreak = function() return '#linebreak()' end,
  today = function() return '#datetime.today().display("[year]年[month padding:none]月[day padding:none]日")' end,
  addcontentsline = function()
    if state.last_unnumbered then state.last_unnumbered.outlined = true end
    return ''
  end,
  typstbibliography = function(a)
    local files = {}
    for f in (a[1] or ''):gmatch('[^;]+') do table.insert(files, q('/' .. f)) end
    if #files == 0 then return '' end
    return '#bibliography((' .. table.concat(files, ', ') .. ',), style: ' .. q(a[2] or 'ieee') .. ')'
  end,
}

convert_cmd = function(text)
  local out = {}
  local s = text
  while s and s:match('%S') do
    s = s:gsub('^%s+', '')
    local name, args, rest = parse_cmd(s)
    if not name then
      warn('解釈できない LaTeX を無視しました: ' .. s:sub(1, 60))
      break
    end
    local base = name:gsub('%*$', '')
    if name == 'begin' then
      warn('未対応の環境 \\begin{' .. (args[1] or '') .. '} を無視しました')
      break
    elseif handlers[name] or handlers[base] then
      local r = (handlers[name] or handlers[base])(args)
      if r and r ~= '' then table.insert(out, r) end
    elseif not (ignore[name] or ignore[base]) then
      warn('未対応のコマンド \\' .. name .. ' を無視しました')
    end
    s = rest
  end
  return table.concat(out, '\n')
end

-- --------------------------------------------------------------------------
-- 1 周目: ラベル収集と数式
-- --------------------------------------------------------------------------
local function collect_id(el)
  if el.identifier and el.identifier ~= '' then defined[el.identifier] = true end
end

local function process_math(m)
  if m.mathtype ~= 'DisplayMath' then return nil end
  local text = m.text
  local numbered = text:find('\\typstnum', 1, true) ~= nil
  text = text:gsub('\\typstnum%s*', '')
  -- ブロック内の \label: 1 個目を本体に、2 個目以降は 1 個目への別名にする
  local first = nil
  text = text:gsub('\\label%s*(%b{})', function(b)
    local name = b:sub(2, -2)
    if not first then
      first = name
      defined[name] = true
      return '\\label{' .. name .. '}'
    end
    alias[name] = first
    return ''
  end)
  if text:match('\\nonumber') or text:match('\\notag') then
    text = text:gsub('\\nonumber', ''):gsub('\\notag', '')
  end
  m.text = text
  if numbered then return m end
  if first then alias[first] = nil end
  local body = write_inlines({ m })
  return raw('#[#set math.equation(numbering: none)\n' .. body .. '\n]')
end

-- --------------------------------------------------------------------------
-- 2 周目: 参照・引用・画像
-- --------------------------------------------------------------------------
local function do_link(el)
  local rt = el.attributes['reference-type']
  if not rt then return nil end
  local key = el.attributes['reference'] or el.target:gsub('^#', '')
  return raw(ref_typst(rt, key) .. ';')
end

local function do_cite(el)
  local parts = {}
  for _, c in ipairs(el.citations) do
    local k = c.id
    if bibkeys[k] then
      local args = { 'label(' .. q(k) .. ')' }
      if c.mode == 'AuthorInText' then table.insert(args, 'form: "prose"')
      elseif c.mode == 'SuppressAuthor' then table.insert(args, 'form: "year"') end
      local suf = stringify(c.suffix):gsub('^[,%s]+', '')
      if suf ~= '' then table.insert(args, 'supplement: ' .. q(suf)) end
      table.insert(parts, '#cite(' .. table.concat(args, ', ') .. ');')
    else
      if has_bib then
        warn('文献キー ' .. k .. ' が .bib にありません（[?] と表示）')
      else
        warn('\\cite{' .. k .. '} がありますが \\bibliography がありません')
      end
      table.insert(parts, '#strong(' .. q('[?' .. k .. ']') .. ');')
    end
  end
  return raw(table.concat(parts))
end

local image_exts = { '', '.pdf', '.png', '.jpg', '.jpeg', '.svg', '.gif', '.webp' }
local function do_image(el)
  local src = el.src:gsub('\\', '/')
  if src:match('^%a+://') then return nil end
  src = src:gsub('^%./', ''):gsub('^/', '')
  local found = nil
  local stem = src
  if src:match('%.e?ps$') then
    stem = src:gsub('%.e?ps$', '')
    warn('Typst は EPS 非対応です。PDF/PNG 版を探します: ' .. src)
  end
  for _, ext in ipairs(image_exts) do
    local cand = stem .. ext
    if not cand:match('%.e?ps$') and file_exists(cand) then found = cand break end
  end
  if not found then
    warn('画像が見つかりません: ' .. src)
    return raw('#box(stroke: 0.5pt + gray, inset: 1em)[画像なし: #raw(' .. q(src) .. ')]')
  end
  el.src = '/' .. found
  return el
end

-- --------------------------------------------------------------------------
-- 3 周目: 文書順に見出し・生 LaTeX を処理
-- --------------------------------------------------------------------------
local function raw_inline(el)
  if el.format ~= 'latex' and el.format ~= 'tex' then return nil end
  local r = convert_cmd(el.text)
  if r == '' then return {} end
  if r:sub(1, 1) == '#' then r = r .. ';' end
  return raw(r)
end

local function only_raw(blk)
  if blk.t ~= 'Para' and blk.t ~= 'Plain' then return false end
  local any = false
  for _, il in ipairs(blk.content) do
    if il.t == 'RawInline' and (il.format == 'latex' or il.format == 'tex') then any = true
    elseif il.t ~= 'Space' and il.t ~= 'SoftBreak' then return false end
  end
  return any
end

function Pandoc(doc)
  -- .bib のキー一覧
  local bf = doc.meta['tex2typst-bibfiles']
  if bf then
    for f in stringify(bf):gmatch('[^;]+') do
      local h = io.open(f, 'r')
      if h then
        has_bib = true
        local s = h:read('a'); h:close()
        for key in s:gmatch('@%s*%a+%s*{%s*([^,%s]+)%s*,') do bibkeys[key] = true end
      else
        warn('.bib ファイルが見つかりません: ' .. f)
      end
    end
  end

  doc = doc:walk({
    Header = collect_id, Div = collect_id, Span = collect_id, Figure = collect_id,
    Table = collect_id, Image = collect_id, CodeBlock = collect_id,
    Math = process_math,
  })
  doc = doc:walk({ Link = do_link, Cite = do_cite, Image = do_image })

  -- \mainmatter が明示されているか
  for _, b in ipairs(doc.blocks) do
    if b.t == 'RawBlock' and b.text:match('\\mainmatter') then state.explicit_mainmatter = true end
    if only_raw(b) then
      for _, il in ipairs(b.content) do
        if il.t == 'RawInline' and il.text:match('\\mainmatter') then state.explicit_mainmatter = true end
      end
    end
  end

  local out = {}
  local unnumbered = {}
  for _, b in ipairs(doc.blocks) do
    if b.t == 'RawBlock' then
      if b.format == 'latex' or b.format == 'tex' then
        local r = convert_cmd(b.text)
        if r ~= '' then table.insert(out, pandoc.RawBlock('typst', r)) end
      else
        table.insert(out, b)
      end
    elseif only_raw(b) then
      local parts = {}
      for _, il in ipairs(b.content) do
        if il.t == 'RawInline' then
          local r = convert_cmd(il.text)
          if r ~= '' then table.insert(parts, r) end
        end
      end
      if #parts > 0 then table.insert(out, pandoc.RawBlock('typst', table.concat(parts, '\n'))) end
    elseif b.t == 'Header' then
      b = b:walk({ RawInline = raw_inline })
      if b.classes:includes('unnumbered') then
        local entry = { header = b, outlined = false }
        state.last_unnumbered = entry
        table.insert(unnumbered, entry)
        table.insert(out, entry)
      else
        state.last_unnumbered = nil
        if b.level == 1 and not state.mainmatter_done and not state.explicit_mainmatter then
          state.mainmatter_done = true
          table.insert(out, pandoc.RawBlock('typst', '#show: mainmatter'))
        end
        table.insert(out, b)
      end
    else
      table.insert(out, b:walk({ RawInline = raw_inline }))
    end
  end

  -- 番号なし見出し（\chapter* など）は目次に載せない（\addcontentsline があれば載せる）
  local blocks = {}
  for _, b in ipairs(out) do
    if b.header then
      local h = b.header
      local s = '#heading(level: ' .. h.level .. ', numbering: none, outlined: '
        .. tostring(b.outlined) .. ')[' .. write_inlines(h.content) .. ']'
      if h.identifier ~= '' then s = s .. ' <' .. h.identifier .. '>' end
      table.insert(blocks, pandoc.RawBlock('typst', s))
    else
      table.insert(blocks, b)
    end
  end
  doc.blocks = blocks

  -- 表紙情報
  for k, v in pairs(meta_vals) do
    if k == 'maketitle' then
      doc.meta.maketitle = true
    else
      local parsed = pandoc.read(v, 'latex+raw_tex')
      local inl = {}
      for i, blk in ipairs(parsed.blocks) do
        if i > 1 then table.insert(inl, pandoc.LineBreak()) end
        if blk.content then for _, x in ipairs(blk.content) do table.insert(inl, x) end end
      end
      inl = pandoc.Inlines(inl):walk({ RawInline = raw_inline })
      doc.meta[k] = pandoc.MetaInlines(inl)
    end
  end
  doc.meta['tex2typst-bibfiles'] = nil
  return doc
end
