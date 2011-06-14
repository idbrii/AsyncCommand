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

  " Grab output and error in case there's something we should see
  let tool_cmd = a:command . printf(&shellredir, temp_file)

  if type(Fn) == type({}) && has_key(Fn, 'get') && type(Fn.get) == type(function('asynccommand#run'))
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
  let r = s:receivers[a:temp_file_name]
  if type(r.dict) == type({})
    call call(r.func, [a:temp_file_name], r.dict)
  else
    call call(r.func, [a:temp_file_name])
  endif
  unlet s:receivers[a:temp_file_name]
  delete a:temp_file_name
endfunction

function! asynccommand#rename(path)
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

function! asynccommand#quickfix(format, ...)
  if a:0 == 1
    return asynccommand#qf("cgetfile", "quickfix", a:format, a:1)
  else
    return asynccommand#qf("cgetfile", "quickfix", a:format)
  endif
endfunction

function! asynccommand#quickfix_add(format, ...)
  if a:0 == 1
    return asynccommand#qf("caddfile", "quickfix", a:format, a:1)
  else
    return asynccommand#qf("caddfile", "quickfix", a:format)
  endif
endfunction

function! asynccommand#loclist(format, ...)
  if a:0 == 1
    return asynccommand#qf("lgetfile", "location-list", a:format, a:1)
  else
    return asynccommand#qf("lgetfile", "location-list", a:format)
  endif
endfunction

function! asynccommand#loclist_add(format, title)
  if a:0 == 1
    return asynccommand#qf("laddfile", "location-list", a:format, a:1)
  else
    return asynccommand#qf("laddfile", "location-list", a:format)
  endif
endfunction


function! asynccommand#qf(command, list, format, title)
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

function! asynccommand#tab_restore(env)
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
      call call(self.env.get, [a:temp_file_name], self.env)
      silent! exe "tabnext " . current_tab
      redraw
    finally
      let &lazyredraw = lazyredraw
    endtry
  endfunction
  return env
endfunction

function! asynccommand#split()
  let env = {}
  function env.get(temp_file_name) dict
    exec "split " . a:temp_file_name
    silent! wincmd p
  endfunction
  return asynccommand#tab_restore(env)
endfunction

"vi:et:sw=4 ts=4
