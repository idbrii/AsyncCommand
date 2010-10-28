" AsyncCommand
"   Execute commands and have them send their result to vim when they
"   complete.
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
command! -nargs=1 -complete=tag AsyncCscopeFindSymbol call AsyncCscopeFind('0', <q-args>)
command! -nargs=1 -complete=tag AsyncCscopeFindCalls call AsyncCscopeFind('3', <q-args>)
command! -nargs=1 -complete=tag AsyncCscopeFindX call AsyncCscopeFindX(<q-args>)


if (! exists("no_plugin_maps") || ! no_plugin_maps) &&
      \ (! exists("no_asynccommand_maps") || ! no_asynccommand_maps)
    nmap <unique> <A-S-g> :AsyncCscopeFindSymbol <C-r>=expand('<cword>')<CR><CR>
endif

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
    call OnCompleteLoadErrorFile(a:temp_file_name)
endfunction
function! OnCompleteLoadErrorFile(temp_file_name)
    exec "cgetfile " . a:temp_file_name
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

" Cscope find
"   - open result in quickfix
" s > 0   Find this C symbol
" g > 1   Find this definition
" d > 2   Find functions called by this function
" c > 3   Find functions calling this function
" t > 4   Find assignments to
" e > 6   Find this egrep pattern
" f > 7   Find this file
" i > 8   Find files #including this file
let s:type_char_to_num = {
    \ 's': 0,
    \ 'g': 1,
    \ 'd': 2,
    \ 'c': 3,
    \ 't': 4,
    \ 'e': 6,
    \ 'f': 7,
    \ 'i': 8,
    \ }
function! AsyncCscopeFindX(input)
    " Split the type from the query
    let type = a:input[0]
    let query = a:input[2:]

    " Convert the type from a char to a number
    " (cscope -l requires a number)
    try
        let type_num = s:type_char_to_num[ a:input[ type ] ]
    catch /Key not present in Dictionary/
        echo "Error: " . type . " is an invalid find query. See :cscope help"
        return
    endtry

    call AsyncCscopeFind(type_num, query)
endfunction

function! AsyncCscopeFind(type_num, query)
    " -d  Don't rebuild the database
    " -l  Use cscope's line-oriented mode to send a single search command
    " -f file  Use file as the database file name instead of the default
    " -P path  Prepend path to relative file names in a pre-built database
    " The output is in the form: "filename location line-number context"
    " Use sed to change it so we can use efm: "filename:line-number location context"
    if !exists('g:cscope_database') || !exists('g:cscope_relative_path')
        echoerr "You must define both g:cscope_database and g:cscope_relative_path"
        echoerr "See LocateCscopeFile in tagfilehelpers.vim"
    endif
    let cscope_cmd = &cscopeprg . " -dl -f " . g:cscope_database . " -P " . g:cscope_relative_path
    " sed command: (filename) (symbol context -- may contain spaces) (line number)
    let command = "echo " . a:type_num . a:query . " | " . cscope_cmd . " | sed --regexp-extended -e\"s/(\\S+) (\\S+) ([0-9]+)/\\1:\\3 \\2 \t/\""

    let vim_func = "OnCompleteGetAsyncCscopeResults"

    call AsyncCommand(command, vim_func)
endfunction
function! OnCompleteGetAsyncCscopeResults(temp_file_name)
    " Ignore the >> lines
    setlocal efm=%-G>>%m
    " Match file, line, and message
    setlocal efm+=%f:%l\ %m

    call OnCompleteLoadErrorFile(a:temp_file_name)
endfunction
