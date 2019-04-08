" AsyncCommand implementation
"
" This is the core implementation of AsyncCommand. In general, these functions
" should only be called from AsyncCommand handlers. For handlers to use in
" Async commands, see asynccommand_handlers.vim

if exists("g:loaded_autoload_asynccommand") || &cp
    finish
endif
let g:loaded_autoload_asynccommand = 1

let s:receivers = {}

if !exists("g:asynccommand_statusline")
    let g:asynccommand_statusline = 'Pending:%d'
endif

if !exists("g:asynccommand_statusline_autohide")
    let g:asynccommand_statusline_autohide = 0
endif

" Basic background task running is different on each platform
if has("win32")
    " Works in Windows (Win7 x64)
    function! s:RunWithoutCapturingOutput(tool_cmd)
        silent exec "!start /min cmd /c \"".a:tool_cmd."\""
    endfunction
    let s:result_var = '\%ERRORLEVEL\%'
else
    " Works in linux (Ubuntu 10.04)
    function! s:RunWithoutCapturingOutput(tool_cmd)
        silent exec "! ".a:tool_cmd." &"
    endfunction
    let s:result_var = '$?'
endif

function! asynccommand#run(command, ...)
    " asynccommand#run(command, [function], [dict])
    "   - command is the shell command to execute asynchronously.
    "   - [function] will be called when the command completes. Function
    "   signature should be func(filename) or func(filename, dict) depending
    "   on whether you provide dict. If function is not provided, nothing is
    "   done on command completion.
    "   - [dict] will be passed to function.
    if a:0 == 1
        let Fn = a:1
        let env = 0
    elseif a:0 == 2
        let Fn = a:1
        let env = a:2
    else
        " No additional args means no handling of output, so run without
        " capturing it.
        call s:RunWithoutCapturingOutput(a:command)
		if !has("gui_running")
			" In console vim, clear and redraw after running a background program
			" to remove screen clear from running external program. (Vim stops
			" being visible.)
			redraw!
		endif
		return ""
    endif

    " Using file as an identifier
    let temp_file = tempname()
    " Avoid backslashes to ensure they're not treated as escapes. Vim is smart
    " enough to find files with either slash direction.
    let temp_file = substitute(temp_file, '\\', '/', 'g')

    if type(Fn) == type({})
                \ && has_key(Fn, 'get')
                \ && type(Fn.get) == type(function('asynccommand#run'))
        " Fn is a dictionary and Fn.get is the function we should execute on
        " completion.
        let s:receivers[temp_file] = {'func': Fn.get, 'dict': Fn}
    else
        let s:receivers[temp_file] = {'func': Fn, 'dict': env}
    endif

    " Must escape spaces within post!
    let post = '-post=call\ asynccommand#done("'. temp_file .'",0) '

    " When no visual selection, line1=current, line2=1
    let current_line = getpos('.')[1]
    call asyncrun#run('', '', post . a:command, 0, current_line, 1)
    if !has("gui_running")
        " In console vim, clear and redraw after running a background program
        " to remove screen clear from running external program. (Vim stops
        " being visible.)
        redraw!
    endif
	return ""
endfunction

function! asynccommand#done(temp_file_name, return_code)
    " Text is actually in the quickfix and not in the temp file.
    " TODO: Pull output file out of asyncrun so we don't do this unnecessary
    " work.
    call writefile(map(getqflist(), 'v:val.text'), a:temp_file_name, 'w')
    " Called on completion of the task
    let r = s:receivers[a:temp_file_name]
    if type(r.dict) == type({})
        let r.dict.return_code = a:return_code
        call call(r.func, [a:temp_file_name], r.dict)
    else
        call call(r.func, [a:temp_file_name])
    endif
    unlet s:receivers[a:temp_file_name]
    call delete(a:temp_file_name)
endfunction

function! asynccommand#tab_restore(env)
    " Open the tab the command was run from, load the results there, and then
    " return to the current tab. This ensures that our results are visible where
    " they'll be useful, but we don't jump between tabs.
    "
    " We also use lazyredraw to ensure that the user doesn't see their cursor
    " jumping around.
    "
    " TODO: We probably want notification when the task completes since we won't
    " see it from our current tab.
    let env = {
                \ 'tab': tabpagenr(),
                \ 'env': a:env,
                \ }
    function env.get(temp_file_name) dict
        let lazyredraw = &lazyredraw
        let &lazyredraw = 1
        let current_tab = tabpagenr()
        try
            silent! exec "tabnext " . self.tab
            " pass our return code on to our sub-function
            let self.env.return_code = self.return_code
            " self.env.get is not this function -- it's the function passed to
            " tab_restore()
            call call(self.env.get, [a:temp_file_name], self.env)
            silent! exe "tabnext " . current_tab
            redraw
        finally
            let &lazyredraw = lazyredraw
        endtry
    endfunction
    return env
endfunction

function! asynccommand#statusline()
    let n_pending_jobs = len(s:receivers)
    if g:asynccommand_statusline_autohide && n_pending_jobs == 0
        return ''
    endif

    return g:asyncrun_status
endfunction

" Return a string with a header and list of the output files and title (if
" available) for all pending commands.
function! s:create_pending_listing()
    let out  = "Pending Output Files\n"
    let out .= "====================\n"
    let out .= "Commands (identified by window title if available) are writing to these files.\n"
    let out .= "\n"
    for [fname, handler] in items(s:receivers)
        let out .= fname
        try
            let id = handler.dict.env.title
        catch /Key not present in Dictionary/
            let id = 'untitled'
        endtry
        let out .= printf("\t- %s\n", id)
    endfor
    return out
endfunction

function! asynccommand#open_pending()
    silent pedit _AsyncPending_
    wincmd P
    setlocal modifiable
    1,$delete

    silent 0put =s:create_pending_listing()

    " Map q for easy quit if not already mapped.
    silent! nnoremap <unique> <buffer> q :bdelete<CR>

    " Prevent use of the buffer as a file (to ensure if a file matching this
    " name exists, we don't touch it). We don't support cancelling so
    " modification is meaningless.
    setlocal buftype=nofile
    setlocal bufhidden=wipe
    setlocal noswapfile
    setlocal nobuflisted
    setlocal nomodifiable
    setlocal readonly
endfunction

" vi: et sw=4 ts=4
