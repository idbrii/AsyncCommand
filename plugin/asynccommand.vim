" AsyncCommand
"   Execute commands and have them send their result to vim when they
"   complete.
"   TODO: cscope search
" Author: pydave
" Influences: http://vim.wikia.com/wiki/VimTip1549 (Getting results back into Vim)
"
"

if exists('g:loaded_asynccommand')
    finish
endif
let g:loaded_asynccommand = 1

command! -nargs=+ -complete=file AsyncGrep call AsyncGrep(<q-args>)
command! -nargs=+ -complete=file -complete=shellcmd AsyncShell call AsyncShell(<q-args>)

if exists('g:async_no_touch_lazyredraw')
    let g:async_no_touch_lazyredraw = 0
endif

" Basic background task running is different on each platform
if has("win32")
    " Works in Windows (Win7 x64)
    function! <SID>Async_Impl(tool_cmd, vim_cmd)
        silent exec "!start cmd /c \"".a:tool_cmd." & ".a:vim_cmd."\""
    endfunction
else
    " Works in linux (Ubuntu 10.04)
    function! <SID>Async_Impl(tool_cmd, vim_cmd)
        silent exec "! ".a:tool_cmd." ; ".a:vim_cmd." &"
    endfunction
endif

function! AsyncCommand(command, vim_func)
    " String together and execute.
    let temp_file = tempname()

    " Grab output and error in case there's something we should see
    let tool_cmd = a:command . printf(&shellredir, temp_file)

    let vim_cmd = "vim --servername ".v:servername." --remote-expr \"" . a:vim_func . "('" . temp_file . "')\" "

    call <SID>Async_Impl(tool_cmd, vim_cmd)
endfunction


""""""""""""""""""""""
" Actual implementations

" Grep
"   - open result in quickfix
function! AsyncGrep(query)
    let grep_cmd = "grep --line-number --with-filename ".a:query
    let vim_func = "OnCompleteGetAsyncGrepResults"

    call AsyncCommand(grep_cmd, vim_func)
endfunction
function! OnCompleteGetAsyncGrepResults(temp_file_name)
    let &errorformat = &grepformat
    exec "cfile " . a:temp_file_name
    cwindow
endfunction

" Shell commands
"   - open result in a split
function! AsyncShell(command)
    let vim_func = "OnCompleteLoadFile"
    call AsyncCommand(a:command, vim_func)
endfunction
function! OnCompleteLoadFile(temp_file_name)
    if g:async_no_touch_lazyredraw = 0
        set nolazyredraw
    endif
    exec "split " . a:temp_file_name
    wincmd w
endfunction
