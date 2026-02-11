" plugin/vim_review.vim
if exists('g:loaded_vim_review')
  finish
endif
let g:loaded_vim_review = 1

" Default mappings (user can disable / override)
if !exists('g:vim_review_no_mappings')
  nnoremap <silent> <leader>ca :ReviewCommentAdd<CR>
  nnoremap <silent> <leader>ck :ReviewCommentAck<CR>
  nnoremap <silent> <leader>cd :ReviewCommentDel<CR>
  nnoremap <silent> <leader>cs :ReviewCommentCur<CR>
  nnoremap <silent> <leader>cl :ReviewCommentList<CR>
endif

command! ReviewCommentAdd  call vim_review#add()
command! ReviewCommentAck  call vim_review#ack()
command! ReviewCommentDel  call vim_review#del()
command! ReviewCommentCur  call vim_review#cur()
command! ReviewCommentShow call vim_review#show()
command! ReviewCommentList call vim_review#list()

augroup VimReviewComments
  autocmd!
  autocmd VimEnter * call vim_review#sync_store()
  autocmd BufEnter * call vim_review#sync_store() | call vim_review#refresh_signs()
augroup END
