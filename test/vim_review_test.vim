" test/vim_review_test.vim
let s:repo_root = fnamemodify(expand('<sfile>:p:h:h'), ':p')

function! s:store_ext() abort
  return exists('*json_encode') ? 'json' : 'vim'
endfunction

function! s:store_path_for_cwd(cwd) abort
  return a:cwd . '/.vim_review_comments.' . s:store_ext()
endfunction

function! s:decode_store(path) abort
  if !filereadable(a:path)
    return {}
  endif
  let l:raw = join(readfile(a:path), "\n")
  if exists('*json_decode')
    return json_decode(l:raw)
  endif
  return eval(l:raw)
endfunction

function! s:new_env() abort
  let l:dir = tempname()
  call mkdir(l:dir, 'p')
  return {'dir': l:dir}
endfunction

function! s:reset_editor() abort
  silent! lclose
  silent! only
  silent! %bwipeout!
endfunction

function! s:cleanup_env(env) abort
  execute 'cd ' . fnameescape(s:repo_root)
  call s:reset_editor()
  call delete(a:env.dir, 'rf')
endfunction

function! s:edit_file(path, lines) abort
  call mkdir(fnamemodify(a:path, ':h'), 'p')
  call writefile(a:lines, a:path)
  execute 'edit ' . fnameescape(a:path)
endfunction

function! s:add_comment_at(lnum, text) abort
  call cursor(a:lnum, 1)
  call feedkeys(a:text . "\<CR>", 'tn')
  call vim_review#add()
endfunction

function! s:count_signs(buf, sign_name) abort
  if !exists('*sign_getplaced')
    return -1
  endif
  let l:placed = sign_getplaced(a:buf)
  if empty(l:placed) || !has_key(l:placed[0], 'signs')
    return 0
  endif
  let l:count = 0
  for l:sign in l:placed[0].signs
    if get(l:sign, 'name', '') ==# a:sign_name
      let l:count += 1
    endif
  endfor
  return l:count
endfunction

function! s:loclist_items() abort
  for l:w in range(1, winnr('$'))
    let l:items = getloclist(l:w)
    if !empty(l:items)
      return l:items
    endif
  endfor
  return []
endfunction

function! s:item_filename(item) abort
  if has_key(a:item, 'filename') && !empty(a:item.filename)
    return resolve(fnamemodify(a:item.filename, ':p'))
  endif
  if has_key(a:item, 'bufnr') && a:item.bufnr > 0
    return resolve(fnamemodify(bufname(a:item.bufnr), ':p'))
  endif
  return ''
endfunction

function! s:test_commands_exist() abort
  call assert_equal(2, exists(':ReviewCommentAdd'))
  call assert_equal(2, exists(':ReviewCommentAck'))
  call assert_equal(2, exists(':ReviewCommentDel'))
  call assert_equal(2, exists(':ReviewCommentCur'))
  call assert_equal(2, exists(':ReviewCommentShow'))
  call assert_equal(2, exists(':ReviewCommentList'))
endfunction

function! s:test_add_cur_show_and_refresh_signs() abort
  let l:env = s:new_env()
  try
    call s:reset_editor()
    execute 'cd ' . fnameescape(l:env.dir)
    call s:edit_file(l:env.dir . '/alpha.txt', ['one', 'two', 'three'])

    call s:add_comment_at(2, 'note alpha')
    call vim_review#sync_store()
    call vim_review#refresh_signs()

    let l:store = s:store_path_for_cwd(l:env.dir)
    call assert_true(filereadable(l:store))
    let l:db = s:decode_store(l:store)
    let l:file = expand('%:p')
    call assert_equal('note alpha', l:db[l:file]['2'])

    let l:out = execute('ReviewCommentCur')
    call assert_match('note alpha', l:out)

    if exists('*sign_getplaced')
      call assert_equal(1, s:count_signs(bufnr('%'), 'ReviewComment'))
    endif

    call vim_review#show()
    let l:items = s:loclist_items()
    call assert_equal(1, len(l:items))
    call assert_equal(2, l:items[0].lnum)
    call assert_match('note alpha', l:items[0].text)
  finally
    call s:cleanup_env(l:env)
  endtry
endfunction

function! s:test_ack_and_foreign_sign_survives_refresh() abort
  let l:env = s:new_env()
  try
    call s:reset_editor()
    execute 'cd ' . fnameescape(l:env.dir)
    call s:edit_file(l:env.dir . '/ack.txt', ['line1', 'line2', 'line3'])

    execute 'sign define ForeignSign text=FS texthl=WarningMsg'
    execute 'sign place 777 line=1 name=ForeignSign buffer=' . bufnr('%')

    call s:add_comment_at(2, 'needs ack')
    call cursor(2, 1)
    call vim_review#ack()
    call vim_review#refresh_signs()

    let l:db = s:decode_store(s:store_path_for_cwd(l:env.dir))
    let l:item = l:db[expand('%:p')]['2']
    call assert_equal(1, l:item.ack)
    call assert_equal('needs ack', l:item.text)

    let l:out = execute('ReviewCommentCur')
    call assert_match('acknowledged', l:out)

    if exists('*sign_getplaced')
      call assert_equal(0, s:count_signs(bufnr('%'), 'ReviewComment'))
      call assert_equal(1, s:count_signs(bufnr('%'), 'ForeignSign'))
    endif
  finally
    call s:cleanup_env(l:env)
  endtry
endfunction

function! s:test_del_removes_comment() abort
  let l:env = s:new_env()
  try
    call s:reset_editor()
    execute 'cd ' . fnameescape(l:env.dir)
    call s:edit_file(l:env.dir . '/delete.txt', ['a', 'b', 'c'])

    call s:add_comment_at(2, 'will delete')
    call cursor(2, 1)
    call vim_review#del()

    let l:db = s:decode_store(s:store_path_for_cwd(l:env.dir))
    call assert_false(has_key(l:db[expand('%:p')], '2'))

    let l:out = execute('ReviewCommentCur')
    call assert_match('No comment', l:out)

    if exists('*sign_getplaced')
      call assert_equal(0, s:count_signs(bufnr('%'), 'ReviewComment'))
    endif
  finally
    call s:cleanup_env(l:env)
  endtry
endfunction

function! s:test_list_sorted_by_file_and_line() abort
  let l:env = s:new_env()
  try
    call s:reset_editor()
    execute 'cd ' . fnameescape(l:env.dir)

    let l:b_file = l:env.dir . '/b.txt'
    let l:a_file = l:env.dir . '/a.txt'
    call s:edit_file(l:b_file, ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'])
    call s:add_comment_at(10, 'b10')
    call s:add_comment_at(2, 'b2')

    call s:edit_file(l:a_file, ['x', 'y', 'z'])
    call s:add_comment_at(3, 'a3')

    call vim_review#list()
    let l:items = s:loclist_items()
    let l:expected_a = resolve(fnamemodify(l:a_file, ':p'))
    let l:expected_b = resolve(fnamemodify(l:b_file, ':p'))
    call assert_equal(3, len(l:items))
    call assert_equal(l:expected_a, s:item_filename(l:items[0]))
    call assert_equal(3, l:items[0].lnum)
    call assert_equal(l:expected_b, s:item_filename(l:items[1]))
    call assert_equal(2, l:items[1].lnum)
    call assert_equal(l:expected_b, s:item_filename(l:items[2]))
    call assert_equal(10, l:items[2].lnum)
  finally
    call s:cleanup_env(l:env)
  endtry
endfunction

function! s:test_sync_store_switch_has_no_empty_writes() abort
  let l:env = s:new_env()
  try
    call s:reset_editor()
    let l:dir_one = l:env.dir . '/one'
    let l:dir_two = l:env.dir . '/two'
    call mkdir(l:dir_one, 'p')
    call mkdir(l:dir_two, 'p')
    call writefile(['one'], l:dir_one . '/f1.txt')
    call writefile(['two'], l:dir_two . '/f2.txt')

    execute 'cd ' . fnameescape(l:dir_one)
    execute 'edit ' . fnameescape(l:dir_one . '/f1.txt')
    call vim_review#sync_store()
    let l:store_one = s:store_path_for_cwd(l:dir_one)
    call assert_false(filereadable(l:store_one))

    execute 'cd ' . fnameescape(l:dir_two)
    execute 'edit ' . fnameescape(l:dir_two . '/f2.txt')
    call vim_review#sync_store()
    let l:store_two = s:store_path_for_cwd(l:dir_two)
    call assert_false(filereadable(l:store_one))
    call assert_false(filereadable(l:store_two))

    call s:add_comment_at(1, 'persisted')
    call assert_true(filereadable(l:store_two))

    execute 'cd ' . fnameescape(l:dir_one)
    execute 'edit ' . fnameescape(l:dir_one . '/f1.txt')
    call vim_review#sync_store()
    call assert_false(filereadable(l:store_one))
  finally
    call s:cleanup_env(l:env)
  endtry
endfunction

function! VimReviewTestsRun() abort
  let v:errors = []
  call s:test_commands_exist()
  call s:test_add_cur_show_and_refresh_signs()
  call s:test_ack_and_foreign_sign_survives_refresh()
  call s:test_del_removes_comment()
  call s:test_list_sorted_by_file_and_line()
  call s:test_sync_store_switch_has_no_empty_writes()
endfunction
