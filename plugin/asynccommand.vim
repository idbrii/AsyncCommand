" AsyncCommand
"   Execute commands and have them send their result to vim when they
"   complete.
" Author: pydave
" Influences: http://vim.wikia.com/wiki/VimTip1549 (Getting results back into Vim)
" Contributors: Peter Rincker
"
" To define new commands:
"   Define a launch function that passes the external command and result handler
" (like asynchandler#quickfix) to asynccommand#run.
"   You can use the handlers in autoload/asynchandler.vim or define your own.
" 
" Note that cscope functions require these variables:
"   let g:cscope_database = **full path to cscope database file**
"   let g:cscope_relative_path = **folder containing cscope database file**
" These variables are set by tagfilehelpers.vim

if exists('g:loaded_asynccommand')
    finish
endif
let g:loaded_asynccommand = 1

if &cp
    echoerr "AsyncCommand cannot run in vi-compatible mode (see :help 'cp')."
    finish
elseif !has('clientserver')
    echoerr "AsyncCommand requires vim compiled with +clientserver (see :help +clientserver)"
    finish
endif

let s:save_cpo = &cpo
set cpo&vim

function! AsyncCommandDone(file, return_code)
    return asynccommand#done(a:file, a:return_code)
endfunction

command! -nargs=+ -complete=shellcmd AsyncCommand call asynccommand#run(<q-args>)

" Examples below
" ==============

command! -nargs=+ -complete=file AsyncGrep call s:AsyncGrep(<q-args>)
command! -nargs=+ -complete=file -complete=shellcmd AsyncShell call s:AsyncShell(<q-args>)
command! -nargs=* AsyncMake call s:AsyncMake(<q-args>)

command! -nargs=1 -complete=tag AsyncCscopeFindSymbol call s:AsyncCscopeFindX('s '. <q-args>)
command! -nargs=1 -complete=tag AsyncCscopeFindCalls call s:AsyncCscopeFindX('c '. <q-args>)
command! -nargs=1 -complete=tag AsyncCscopeFindX call s:AsyncCscopeFindX(<q-args>)


if (! exists("no_plugin_maps") || ! no_plugin_maps) &&
            \ (! exists("no_asynccommand_maps") || ! no_asynccommand_maps)
    nmap <unique> <A-S-g> :AsyncCscopeFindSymbol <C-r>=expand('<cword>')<CR><CR>
endif

""""""""""""""""""""""
" Actual implementations

" Grep
"   - open result in quickfix
function! s:AsyncGrep(query)
    let grep_cmd = "grep --line-number --with-filename ".a:query
    call asynccommand#run(grep_cmd, asynchandler#quickfix(&grepformat, '[Found: %s] grep ' . a:query))
endfunction

" Shell commands
"   - open result in a split
function! s:AsyncShell(command)
    call asynccommand#run(a:command, asynchandler#split())
endfunction

" Make
"   - uses the current make program
"   - optional parameter for make target(s)
function! s:AsyncMake(target)
    let make_cmd = &makeprg ." ". a:target
    let title = 'Make: '
    if a:target == ''
        let title .= "(default)"
    else
        let title .= a:target
    endif
    call asynccommand#run(make_cmd, asynchandler#quickfix(&errorformat, title))
endfunction


" Cscope find
"   - open result in quickfix
" Map the commands from `:cscope help` to the numbers expected by `cscope -l`
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
let s:num_to_description = {
            \ 0: 'C symbol',
            \ 1: 'Definition',
            \ 2: 'Functions called by this function',
            \ 3: 'Functions calling this function',
            \ 4: 'Assignments to',
            \ 6: 'Egrep pattern',
            \ 7: 'File',
            \ 8: '#including this file',
            \ }
" Wrap AsyncCscopeFind to make it easier to do cscope searches. The user
" passes everything as one parameter and doesn't have to use numbers.
function! s:AsyncCscopeFindX(input)
    " Split the type from the query
    let type = a:input[0]
    let query = a:input[2:]

    " Convert the type from a char to a number
    " (cscope -l requires a number)
    try
        let type_num = s:type_char_to_num[ type ]
    catch /Key not present in Dictionary/
        echo "Error: " . type . " is an invalid find query. See :cscope help"
        return
    endtry

    let title = s:num_to_description[type_num] . ' ' . query

    call s:AsyncCscopeFind(type_num, query, title)
endfunction

function! s:AsyncCscopeFind(type_num, query, title)
    " -d  Don't rebuild the database
    " -l  Use cscope's line-oriented mode to send a single search command
    " -f file  Use file as the database file name instead of the default
    " -P path  Prepend path to relative file names in a pre-built database
    " The output is in the form: "filename location line-number context"
    " Use sed to change it so we can use efm: "filename:line-number location context"
    if !exists('g:cscope_database') || !exists('g:cscope_relative_path')
        echoerr "You must define both g:cscope_database and g:cscope_relative_path"
        echoerr "See LocateCscopeFile in tagfilehelpers.vim"
        return
    endif
    let cscope_cmd = &cscopeprg . " -dl -f " . g:cscope_database . " -P " . g:cscope_relative_path
    " sed command: (filename) (symbol context -- may contain spaces) (line number)
    let command = "echo " . a:type_num . a:query . " | " . cscope_cmd . " | sed --regexp-extended -e\"s/(\\S+) (\\S+) ([0-9]+)/\\1:\\3 \\2 \t/\""

    call asynccommand#run(command, s:CscopeResults(a:title))
endfunction

function! s:CscopeResults(title)
    return asynchandler#quickfix("%-G>>%m,%f:%l\ %m", "[Found: %s] Cscope: " . a:title)
endfunction

let &cpo = s:save_cpo

"vi:et:sw=4 ts=4
