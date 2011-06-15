" AsyncCommand implementation
"
" This is the core implementation of AsyncCommand. In general, these functions
" should only be called from AsyncCommand handlers. For handlers to use in
" Async commands, see asynccommand_handlers.vim

if exists("g:loaded_autoload_asynccommand") || &cp || !has('clientserver')
  finish
endif
let g:loaded_autoload_asynccommand = 1

let s:receivers = {}

" Basic background task running is different on each platform
if has("win32")
    " Works in Windows (Win7 x64)
    function! s:Async_Impl(tool_cmd, vim_cmd)
        silent exec "!start /min cmd /c \"".a:tool_cmd." & ".a:vim_cmd."\""
    endfunction
    function! s:Async_Single_Impl(tool_cmd)
        silent exec "!start /min cmd /c \"".a:tool_cmd."\""
    endfunction
else
    " Works in linux (Ubuntu 10.04)
    function! s:Async_Impl(tool_cmd, vim_cmd)
        silent exec "! ( ".a:tool_cmd." ; ".a:vim_cmd." ) &"
    endfunction
    function! s:Async_Single_Impl(tool_cmd)
        silent exec "! ".a:tool_cmd." &"
    endfunction
endif

function! asynccommand#run(command, ...)
    " asynccommand#run(command, [function], [dict])
    "   - command is the shell command to execute asynchronously.
    "   - [function] will be called when the command completes. Function
    "   signature should be func(filename) or func(filename, dict) depending
    "   on whether you provide dict. If function is not provided, nothing is
    "   done on command completion.
    "   - [dict] will be passed to function.
  if len(v:servername) == 0
    echo "Error: AsyncCommand requires vim to be started with a servername."
    echo "       See :help --servername"
    return
  endif
  if a:0 == 1
    let Fn = a:1
    let env = 0
  elseif a:0 == 2
    let Fn = a:1
    let env = a:2
  else
    " execute in background
    return s:Async_Single_Impl(a:command)
  endif

  " String together and execute.
  let temp_file = tempname()

  let shellredir = &shellredir
  if match( shellredir, '%s') == -1
      " ensure shellredir has a %s so printf works
      let shellredir .= '%s'
  endif

  " Grab output and error in case there's something we should see
  let tool_cmd = a:command . printf(shellredir, temp_file)

  if type(Fn) == type({})
              \ && has_key(Fn, 'get')
              \ && type(Fn.get) == type(function('asynccommand#run'))
    " Fn is a dictionary and Fn.get is the function we should execute on
    " completion.
    let s:receivers[temp_file] = {'func': Fn.get, 'dict': Fn}
  else
    let s:receivers[temp_file] = {'func': Fn, 'dict': env}
  endif

  if exists('g:asynccommand_prg')
    let prg = g:asynccommand_prg
  elseif has("gui_macvim") && executable('mvim')
    let prg = "mvim"
  else
    let prg = "vim"
  endif

  let vim_cmd = prg . " --servername " . v:servername . " --remote-expr \"AsyncCommandDone('" . temp_file . "')\" "

  call s:Async_Impl(tool_cmd, vim_cmd)
endfunction

function! asynccommand#done(temp_file_name)
  " Called on completion of the task
  let r = s:receivers[a:temp_file_name]
  if type(r.dict) == type({})
    call call(r.func, [a:temp_file_name], r.dict)
  else
    call call(r.func, [a:temp_file_name])
  endif
  unlet s:receivers[a:temp_file_name]
  delete a:temp_file_name
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

"vi:et:sw=4 ts=4
