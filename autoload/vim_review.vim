" autoload/vim_review.vim
if exists('s:initialized')
  finish
endif
let s:initialized = 1

sign define ReviewComment text=💬 texthl=WarningMsg

let s:db = {}            " { abs_file: { lnum: text } }
let s:active_store = ''  " current store file path

function! s:absfile() abort
  return fnamemodify(expand('%:p'), ':p')
endfunction

function! s:bufdir() abort
  return fnamemodify(expand('%:p:h'), ':p')
endfunction

function! s:systemlist(cmd) abort
  if exists('*systemlist')
    return systemlist(a:cmd)
  endif
  return split(system(a:cmd), "\n")
endfunction

function! s:git_root(dir) abort
  let l:out = s:systemlist('git -C ' . shellescape(a:dir) . ' rev-parse --show-toplevel 2>/dev/null')
  return (v:shell_error || empty(l:out)) ? '' : l:out[0]
endfunction

function! s:git_sha(dir) abort
  let l:out = s:systemlist('git -C ' . shellescape(a:dir) . ' rev-parse HEAD 2>/dev/null')
  return (v:shell_error || empty(l:out)) ? '' : l:out[0]
endfunction

function! s:store_path() abort
  let l:dir  = s:bufdir()
  let l:root = s:git_root(l:dir)
  let l:sha  = s:git_sha(l:dir)

  if !empty(l:root) && !empty(l:sha)
    let l:ext = exists('*json_encode') ? 'json' : 'vim'
    return l:root . '/.vim_review/' . l:sha . '-comments.' . l:ext
  endif

  let l:ext = exists('*json_encode') ? 'json' : 'vim'
  return getcwd() . '/.vim_review_comments.' . l:ext
endfunction

function! s:save_db_to(path) abort
  let l:dir = fnamemodify(a:path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif

  if exists('*json_encode')
    call writefile([json_encode(s:db)], a:path)
  else
    call writefile([string(s:db)], a:path)
  endif
endfunction

function! s:load_db_from(path) abort
  if !filereadable(a:path)
    let s:db = {}
    return
  endif

  let l:content = join(readfile(a:path), "\n")
  if exists('*json_decode')
    try
      let s:db = json_decode(l:content)
      if type(s:db) != type({})
        let s:db = {}
      endif
    catch
      let s:db = {}
    endtry
  else
    try
      let s:db = eval(l:content)
      if type(s:db) != type({})
        let s:db = {}
      endif
    catch
      let s:db = {}
    endtry
  endif
endfunction

function! vim_review#sync_store() abort
  if &buftype !=# '' | return | endif
  let l:new = s:store_path()

  if empty(s:active_store)
    let s:active_store = l:new
    call s:load_db_from(s:active_store)
    return
  endif

  if l:new !=# s:active_store
    call s:save_db_to(s:active_store)
    let s:active_store = l:new
    call s:load_db_from(s:active_store)
  endif
endfunction

function! s:place_sign(buf, lnum) abort
  execute 'sign place ' . (a:buf*100000 + a:lnum) . ' line=' . a:lnum . ' name=ReviewComment buffer=' . a:buf
endfunction

function! vim_review#refresh_signs() abort
  let l:buf = bufnr('%')
  execute 'sign unplace * buffer=' . l:buf

  let l:file = s:absfile()
  if empty(l:file) | return | endif
  if !has_key(s:db, l:file) | return | endif

  for l:ln in keys(s:db[l:file])
    call s:place_sign(l:buf, str2nr(l:ln))
  endfor
endfunction

function! vim_review#add() abort
  if &buftype !=# '' | echo "Not a file buffer" | return | endif
  call vim_review#sync_store()

  let l:file = s:absfile()
  if empty(l:file) | echo "No file name" | return | endif

  let l:lnum = string(line('.'))
  if !has_key(s:db, l:file)
    let s:db[l:file] = {}
  endif

  let l:old = get(s:db[l:file], l:lnum, '')
  let l:text = input('💬 Comment: ', l:old)
  if empty(l:text) | echo "Cancelled" | return | endif

  let s:db[l:file][l:lnum] = l:text
  call s:place_sign(bufnr('%'), str2nr(l:lnum))
  call s:save_db_to(s:active_store)
  echo "Comment saved ✔"
endfunction

function! vim_review#del() abort
  if &buftype !=# '' | return | endif
  call vim_review#sync_store()

  let l:file = s:absfile()
  let l:lnum = string(line('.'))
  if has_key(s:db, l:file) && has_key(s:db[l:file], l:lnum)
    call remove(s:db[l:file], l:lnum)
    call s:save_db_to(s:active_store)
    call vim_review#refresh_signs()
    echo "Comment deleted"
  else
    echo "No comment on this line"
  endif
endfunction

function! vim_review#cur() abort
  call vim_review#sync_store()
  let l:file = s:absfile()
  let l:lnum = string(line('.'))
  let l:text = get(get(s:db, l:file, {}), l:lnum, '')
  echo empty(l:text) ? "No comment" : ("💬 " . l:text)
endfunction

function! vim_review#ack() abort
  if &buftype !=# '' | return | endif
  call vim_review#sync_store()

  let l:file = s:absfile()
  let l:lnum = string(line('.'))
  if has_key(s:db, l:file) && has_key(s:db[l:file], l:lnum)
    let s:db[l:file][l:lnum] = 'ignore this comment.'
    call s:save_db_to(s:active_store)
    call vim_review#refresh_signs()
    echo "Comment acknowledged"
  else
    echo "No comment on this line"
  endif
endfunction

function! vim_review#show() abort
  call vim_review#sync_store()
  let l:file = s:absfile()
  let l:items = []
  for [l:ln, l:text] in items(get(s:db, l:file, {}))
    call add(l:items, {
          \ 'bufnr': bufnr('%'),
          \ 'lnum': str2nr(l:ln),
          \ 'col': 1,
          \ 'text': '💬 ' . l:text
          \ })
  endfor
  call setloclist(0, l:items, 'r')
  lopen
endfunction

function! vim_review#list() abort
  call vim_review#sync_store()
  let l:items = []
  for [l:file, l:comments] in items(s:db)
    for [l:ln, l:text] in items(l:comments)
      call add(l:items, {
            \ 'filename': l:file,
            \ 'lnum': str2nr(l:ln),
            \ 'col': 1,
            \ 'text': '💬 ' . l:text
            \ })
    endfor
  endfor
  call setloclist(0, l:items, 'r')
  lopen
endfunction
