" autoload/vim_review.vim
if exists('s:initialized')
  finish
endif
let s:initialized = 1

sign define ReviewComment text=💬 texthl=WarningMsg

let s:db = {}            " { abs_file: { lnum: text } }
let s:active_store = ''  " current store file path
let s:dirty = 0          " in-memory changes not saved yet
let s:placed_sign_ids = {} " { bufnr: { sign_id: 1 } }

function! s:store_ext() abort
  return exists('*json_encode') ? 'json' : 'vim'
endfunction

function! s:echo_error(msg) abort
  echohl ErrorMsg
  echo a:msg
  echohl None
endfunction

function! s:comment_text(item) abort
  if type(a:item) == type({})
    return get(a:item, 'text', '')
  endif
  return a:item
endfunction

function! s:comment_acked(item) abort
  return type(a:item) == type({}) && get(a:item, 'ack', 0)
endfunction

function! s:absfile() abort
  let l:path = expand('%:p')
  if empty(l:path)
    return ''
  endif
  return fnamemodify(l:path, ':p')
endfunction

function! s:bufdir() abort
  let l:file = s:absfile()
  if empty(l:file)
    return ''
  endif
  return fnamemodify(l:file, ':h')
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
  let l:ext = s:store_ext()
  let l:dir  = s:bufdir()
  if empty(l:dir)
    return getcwd() . '/.vim_review_comments.' . l:ext
  endif
  let l:root = s:git_root(l:dir)
  let l:sha  = s:git_sha(l:dir)

  if !empty(l:root) && !empty(l:sha)
    return l:root . '/.vim_review/' . l:sha . '-comments.' . l:ext
  endif

  return getcwd() . '/.vim_review_comments.' . l:ext
endfunction

function! s:save_db_to(path) abort
  let l:dir = fnamemodify(a:path, ':h')
  if !isdirectory(l:dir)
    try
      call mkdir(l:dir, 'p')
    catch
      return 0
    endtry
    if !isdirectory(l:dir)
      return 0
    endif
  endif

  let l:lines = exists('*json_encode') ? [json_encode(s:db)] : [string(s:db)]
  try
    if writefile(l:lines, a:path) != 0
      return 0
    endif
  catch
    return 0
  endtry

  if fnamemodify(l:dir, ':t') ==# '.vim_review'
    let l:ext = fnamemodify(a:path, ':e')
    let l:latest = l:dir . '/latest-comments.' . l:ext
    if has('unix')
      call system('ln -sfn ' . shellescape(a:path) . ' ' . shellescape(l:latest) . ' 2>/dev/null')
      if v:shell_error
        try
          call writefile(l:lines, l:latest)
        catch
          " Ignore latest pointer failures; canonical store already wrote.
        endtry
      endif
    else
      try
        call writefile(l:lines, l:latest)
      catch
        " Ignore latest pointer failures; canonical store already wrote.
      endtry
    endif
  endif

  let s:dirty = 0
  return 1
endfunction

function! s:load_db_from(path) abort
  if !filereadable(a:path)
    let s:db = {}
    let s:dirty = 0
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
      let l:parsed = {}
      sandbox let l:parsed = eval(l:content)
      if type(l:parsed) == type({})
        let s:db = l:parsed
      else
        let s:db = {}
      endif
    catch
      let s:db = {}
    endtry
  endif

  let s:dirty = 0
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
    if s:dirty && !s:save_db_to(s:active_store)
      call s:echo_error('vim-review: failed to save comment store: ' . s:active_store)
      return
    endif
    let s:active_store = l:new
    call s:load_db_from(s:active_store)
  endif
endfunction

function! s:place_sign(buf, lnum) abort
  let l:id = a:buf*100000 + a:lnum
  execute 'sign place ' . l:id . ' line=' . a:lnum . ' name=ReviewComment buffer=' . a:buf
  if !has_key(s:placed_sign_ids, a:buf)
    let s:placed_sign_ids[a:buf] = {}
  endif
  let s:placed_sign_ids[a:buf][string(l:id)] = 1
endfunction

function! s:unplace_review_signs(buf) abort
  if exists('*sign_getplaced')
    let l:placed = sign_getplaced(a:buf)
    if !empty(l:placed) && has_key(l:placed[0], 'signs')
      for l:sign in l:placed[0].signs
        if get(l:sign, 'name', '') ==# 'ReviewComment'
          execute 'sign unplace ' . l:sign.id . ' buffer=' . a:buf
        endif
      endfor
    endif
    let s:placed_sign_ids[a:buf] = {}
    return
  endif

  if has_key(s:placed_sign_ids, a:buf)
    for l:id in keys(s:placed_sign_ids[a:buf])
      execute 'sign unplace ' . l:id . ' buffer=' . a:buf
    endfor
  endif
  let s:placed_sign_ids[a:buf] = {}
endfunction

function! vim_review#refresh_signs() abort
  let l:buf = bufnr('%')
  call s:unplace_review_signs(l:buf)

  let l:file = s:absfile()
  if empty(l:file) | return | endif
  if !has_key(s:db, l:file) | return | endif

  for [l:ln, l:item] in items(s:db[l:file])
    if s:comment_acked(l:item)
      continue
    endif
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

  let l:old = s:comment_text(get(s:db[l:file], l:lnum, ''))
  let l:text = input('💬 Comment: ', l:old)
  if empty(l:text) | echo "Cancelled" | return | endif

  let s:db[l:file][l:lnum] = l:text
  call s:place_sign(bufnr('%'), str2nr(l:lnum))
  let s:dirty = 1
  if s:save_db_to(s:active_store)
    echo "Comment saved ✔"
  else
    call s:echo_error('vim-review: failed to save comment store')
  endif
endfunction

function! vim_review#del() abort
  if &buftype !=# '' | return | endif
  call vim_review#sync_store()

  let l:file = s:absfile()
  let l:lnum = string(line('.'))
  if has_key(s:db, l:file) && has_key(s:db[l:file], l:lnum)
    call remove(s:db[l:file], l:lnum)
    let s:dirty = 1
    if s:save_db_to(s:active_store)
      echo "Comment deleted"
    else
      call s:echo_error('vim-review: comment deleted but not saved')
    endif
    call vim_review#refresh_signs()
  else
    echo "No comment on this line"
  endif
endfunction

function! vim_review#cur() abort
  call vim_review#sync_store()
  let l:file = s:absfile()
  let l:lnum = string(line('.'))
  let l:item = get(get(s:db, l:file, {}), l:lnum, '')
  let l:text = s:comment_text(l:item)
  if empty(l:text)
    echo "No comment"
    return
  endif
  echo s:comment_acked(l:item) ? ("💬 " . l:text . " (acknowledged)") : ("💬 " . l:text)
endfunction

function! vim_review#ack() abort
  if &buftype !=# '' | return | endif
  call vim_review#sync_store()

  let l:file = s:absfile()
  let l:lnum = string(line('.'))
  if has_key(s:db, l:file) && has_key(s:db[l:file], l:lnum)
    let l:text = s:comment_text(s:db[l:file][l:lnum])
    let s:db[l:file][l:lnum] = {'text': l:text, 'ack': 1, 'ai': 'ignore this comment.'}
    let s:dirty = 1
    if s:save_db_to(s:active_store)
      echo "Comment acknowledged"
    else
      call s:echo_error('vim-review: comment acknowledged but not saved')
    endif
    call vim_review#refresh_signs()
  else
    echo "No comment on this line"
  endif
endfunction

function! vim_review#show() abort
  call vim_review#sync_store()
  let l:file = s:absfile()
  let l:items = []
  let l:comments = get(s:db, l:file, {})
  for l:ln in sort(keys(l:comments), 'n')
    let l:item = l:comments[l:ln]
    let l:text = s:comment_text(l:item)
    let l:prefix = s:comment_acked(l:item) ? '✓ ' : ''
    call add(l:items, {
          \ 'bufnr': bufnr('%'),
          \ 'lnum': str2nr(l:ln),
          \ 'col': 1,
          \ 'text': l:prefix . '💬 ' . l:text
          \ })
  endfor
  call setloclist(0, l:items, 'r')
  lopen
endfunction

function! vim_review#list() abort
  call vim_review#sync_store()
  let l:items = []
  for l:file in sort(keys(s:db))
    let l:comments = s:db[l:file]
    for l:ln in sort(keys(l:comments), 'n')
      let l:item = l:comments[l:ln]
      let l:text = s:comment_text(l:item)
      let l:prefix = s:comment_acked(l:item) ? '✓ ' : ''
      call add(l:items, {
            \ 'filename': l:file,
            \ 'lnum': str2nr(l:ln),
            \ 'col': 1,
            \ 'text': l:prefix . '💬 ' . l:text
            \ })
    endfor
  endfor
  call setloclist(0, l:items, 'r')
  lopen
endfunction
