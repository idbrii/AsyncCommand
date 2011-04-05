" AsyncCommand
"   Execute commands and have them send their result to vim when they
"   complete.
" Author: pydave
" Influences: http://vim.wikia.com/wiki/VimTip1549 (Getting results back into Vim)
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

command! -nargs=+ -complete=file AsyncGrep call AsyncGrep(<q-args>)
command! -nargs=+ -complete=file -complete=shellcmd AsyncShell call AsyncShell(<q-args>)
command! -nargs=1 -complete=tag AsyncCscopeFindSymbol call AsyncCscopeFind('0', <q-args>)
command! -nargs=1 -complete=tag AsyncCscopeFindCalls call AsyncCscopeFind('3', <q-args>)
command! -nargs=1 -complete=tag AsyncCscopeFindX call AsyncCscopeFindX(<q-args>)
command! -nargs=* AsyncMake call AsyncMake(<q-args>)


if (! exists("no_plugin_maps") || ! no_plugin_maps) &&
      \ (! exists("no_asynccommand_maps") || ! no_asynccommand_maps)
    nmap <unique> <A-S-g> :AsyncCscopeFindSymbol <C-r>=expand('<cword>')<CR><CR>
endif

""""""""""""""""""""""
" Library implementation

" Basic background task running is different on each platform
if has("win32")
    " Works in Windows (Win7 x64)
    function! <SID>Async_Impl(tool_cmd, vim_cmd)
        silent exec "!start cmd /c \"".a:tool_cmd." & ".a:vim_cmd."\""
    endfunction
else
    " Works in linux (Ubuntu 10.04)
    function! <SID>Async_Impl(tool_cmd, vim_cmd)
        silent exec "! (".a:tool_cmd." ; ".a:vim_cmd.") &"
    endfunction
endif

function! AsyncCommand(command, vim_func)
    if len(v:servername) == 0
        echo "Error: AsyncCommand requires vim to be started with a servername."
        echo "       See :help --servername"
        return
    endif

    " String together and execute.
    let temp_file = tempname()

    " Grab output and error in case there's something we should see
    let tool_cmd = a:command . printf(&shellredir, temp_file)

    let vim_cmd = "vim --servername ".v:servername." --remote-expr \"" . a:vim_func . "('" . temp_file . "')\" "

    call <SID>Async_Impl(tool_cmd, vim_cmd)
endfunction

" Load the output as an error file -- does not jump cursor to quick fix
function! OnCompleteLoadErrorFile(temp_file_name)
    exec "cgetfile " . a:temp_file_name
    cwindow
    redraw
endfunction

" Load the output as a file -- moves cursor back to previous window
function! OnCompleteLoadFile(temp_file_name)
    exec "split " . a:temp_file_name
    wincmd w
    redraw
endfunction

""""""""""""""""""""""
" Actual implementations

" Grep
"   - open result in quickfix
function! AsyncGrep(query)
    " Valid queries require two items. 
    " We could also search for that item in the current file, but console grep
    " reads stdin, :grep does nothing, and :vimgrep errors. And we'd have to
    " special case when the buffer has no file.
    " We're consistent instead of convenient.
    if len(split(a:query, '\s')) < 2
        echoerr "Invalid input: missing filename or pattern."
        return
    endif

    let grep_cmd = "grep --line-number --with-filename ".a:query
    let vim_func = "OnCompleteGetAsyncGrepResults"

    call AsyncCommand(grep_cmd, vim_func)
endfunction
function! OnCompleteGetAsyncGrepResults(temp_file_name)
    let &errorformat = &grepformat
    call OnCompleteLoadErrorFile(a:temp_file_name)
endfunction

" Shell commands
"   - open result in a split
function! AsyncShell(command)
    let vim_func = "OnCompleteLoadFile"
    call AsyncCommand(a:command, vim_func)
endfunction

" Make
"   - uses the current make command
"   - optional parameter for make target(s)
function! AsyncMake(target)
    let make_cmd = &makeprg ." ". a:target
    let vim_func = "OnCompleteLoadErrorFile"
    call AsyncCommand(make_cmd, vim_func)
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
" Wrap AsyncCscopeFind to make it easier to do cscope searches. The user
" passes everything as one parameter and doesn't have to use numbers.
function! AsyncCscopeFindX(input)
    " Split the type from the query
    let type = a:input[0]
    let query = a:input[2:]

    " Convert the type from a char to a number
    " (cscope -l requires a number)
    try
        let type_num = s:type_char_to_num[ a:input[ type ] ]
    catch /Key not present in Dictionary/
        echoerr "Error: " . type . " is an invalid find query. See :cscope help"
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
        return
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
