" test/run.vim
set nocompatible
set nomore
set shortmess+=I
set hidden

let g:vim_review_no_mappings = 1

let s:repo_root = fnamemodify(expand('<sfile>:p:h:h'), ':p')
execute 'set rtp^=' . fnameescape(s:repo_root)

runtime plugin/vim_review.vim
execute 'source ' . fnameescape(s:repo_root . '/test/vim_review_test.vim')

call VimReviewTestsRun()

if len(v:errors) > 0
  for s:err in v:errors
    echom s:err
  endfor
  cquit 1
endif

qa!
