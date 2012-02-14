" AsyncCommand Handlers
"
" Various handlers for processing Async results. When an AsyncCommand
" completes, the function provided to asynccommand#run is called. You can use
" these functions, or use them as a guide to define your own handlers.

if exists("g:loaded_autoload_asynchandler") || &cp || !has('clientserver')
    " requires nocompatible and clientserver
    " also, don't double load
    finish
endif
let g:loaded_autoload_asynchandler = 1

function! asynchandler#rename(path)
    " Move the output file to somewhere permanent.
    let env = {'path': a:path}
    function env.get(temp_file_name) dict
        silent! let ret = rename(a:temp_file_name, self.path)
        if ret != 0
            echohl WarningMsg
            echo "Async rename failed: " . escape(self.path)
            echohl NONE
        endif
    endfunction
    return env
endfunction

" Convienience functions for loading the result in the quickfix/locationlist
" or adding to the window's contents
"
function! asynchandler#quickfix(format, title)
    return asynchandler#qf("cgetfile", "quickfix", a:format, a:title)
endfunction

function! asynchandler#quickfix_add(format, title)
    return asynchandler#qf("caddfile", "quickfix", a:format, a:title)
endfunction

function! asynchandler#loclist(format, title)
    return asynchandler#qf("lgetfile", "location-list", a:format, a:title)
endfunction

function! asynchandler#loclist_add(format, title)
    return asynchandler#qf("laddfile", "location-list", a:format, a:title)
endfunction


function! asynchandler#qf(command, list, format, title)
    " Load the result in the quickfix/locationlist
    let env = {
                \ 'title': a:title,
                \ 'command': a:command,
                \ 'list': a:list, 
                \ 'format': a:format, 
                \ 'mode': a:list == 'quickfix' ? 'c' : 'l',
                \ }
    function env.get(temp_file_name) dict
        let errorformat=&errorformat
        let &errorformat=self.format
        try
            exe 'botright ' . self.mode . "open"
            let cmd = self.command . ' ' . a:temp_file_name
            exe cmd
            if type(self.title) == type("") && self.title != ""
                let w:quickfix_title = printf(self.title, len(self.mode == 'c' ? getqflist() : getloclist()))
            endif
            silent! wincmd p
        finally
            let &errorformat = errorformat
        endtry
    endfunction
    return asynccommand#tab_restore(env)
endfunction

function! asynchandler#split()
    " Load the result in a split
    let env = {}
    function env.get(temp_file_name) dict
        exec "split " . a:temp_file_name
        silent! wincmd p
    endfunction
    return asynccommand#tab_restore(env)
endfunction

"vi:et:sw=4 ts=4
