" AsyncCommand
"   Execute commands and have them send their result to vim when they
"   complete.
" Author: pydave
" Influences: http://vim.wikia.com/wiki/VimTip1549 (Getting results back into Vim)
" Contributors: Peter Rincker
"
"
" AsyncCommand allows you to execute shell commands without waiting for them
" to complete. When the application terminates, its output can be loaded into
" a vim buffer. AsyncCommand is written to be compatible with Windows and
" Linux (tested on Win7 and Ubuntu 10.10).
" 
" Currently three types of commands are supported:
" AsyncGrep   -- grep for files and load results in quickfix
" AsyncShell  -- run any program and load results in a split
" and three cscope commands: AsyncCscopeFindSymbol, AsyncCscopeFindCalls, AsyncCscopeFindX
" 
" You can define your own commands commands by following the same format:
" Define the launch function that passes the external command and result
" function to AsyncCommand (like AsyncHello), define the complete function
" (like OnCompleteLoadFile).
" 
" Example:
" function! AsyncHello(query)
"     " echo hello and the parameter
"     let hello_cmd = "echo hello ".a:query
"     " just load the file when we're done
"     let vim_func = "OnCompleteLoadFile"
" 
"     " call our core function to run in the background and then load the
"     " output file on completion
"     call AsyncCommand(hello_cmd, vim_func)
" endfunction

" Note that cscope functions require these variables:
"   let g:cscope_database = **full path to cscope database file**
"   let g:cscope_relative_path = **folder containing cscope database file**
" These variables are set by tagfilehelpers.vim

if exists('g:loaded_asynccommand')
    finish
endif
let g:loaded_asynccommand = 1

let s:save_cpo = &cpo
set cpo&vim

function! AsyncCommandDone(file)
  return asynccommand#done(a:file)
endfunction

command! -nargs=+ -complete=shellcmd AsyncCommand call asynccommand#run(<q-args>)

" Examples below
" ==============

command! -nargs=+ -complete=file AsyncGrep call s:AsyncGrep(<q-args>)
command! -nargs=+ -complete=file -complete=shellcmd AsyncShell call s:AsyncShell(<q-args>)

command! -nargs=1 -complete=tag AsyncCscopeFindSymbol call s:AsyncCscopeFindX('0 '. <q-args>)
command! -nargs=1 -complete=tag AsyncCscopeFindCalls call s:AsyncCscopeFindX('3 '. <q-args>)
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
        let type_num = s:type_char_to_num[ a:input[ type ] ]
    catch /Key not present in Dictionary/
        echo "Error: " . type . " is an invalid find query. See :cscope help"
        return
    endtry

    let title = s:num_to_description[type] . ' ' . query

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

    call asynccommand#run(command, s:CScopeResults(title))
endfunction

function! s:CScopeResults(title)
  return asynchandler#quickfix("%-G>>%m,%f:%l\ %m", "[Found: %s] CScope: " . a:title)
endfunction

let &cpo = s:save_cpo

"vi:et:sw=4 ts=4
