AsyncCommand
====

AsyncCommand allows you to execute shell commands without waiting for them 
to complete. When the application terminates, its output can be loaded into 
a vim buffer. AsyncCommand is written to be compatible with Windows and 
Linux (tested on Win7 and Ubuntu 10.10). 

Currently three types of commands are supported: 

AsyncGrep
    grep for files and load results in quickfix 
AsyncShell
    run any program and load results in a split 
AsyncCscopeFindSymbol, AsyncCscopeFindCalls, AsyncCscopeFindX 
    cscope commands

You can define your own commands commands by following the same format:
Define a launch function that passes the external command and result handler
(like asynchandler#quickfix) to asynccommand#run. You can use the handlers in
autoload/asynchandler.vim or define your own.

Example: 

::

    function! AsyncHello(query)
        " echo hello and the parameter
        let hello_cmd = "echo hello ".a:query
        " just load the file when we're done
        let vim_func = asynchandler#split()
    
        " call our core function to run in the background and then load the
        " output file on completion
        call asynccommand#run(hello_cmd, vim_func)
    endfunction
