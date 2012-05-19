AsyncCommand
====

AsyncCommand allows you to execute shell commands without waiting for them 
to complete. When the application terminates, its output can be loaded into 
a vim buffer. AsyncCommand is written to be compatible with Windows and 
Linux (tested on Win7 and Ubuntu 11.10). 

Currently three types of commands are supported: 

AsyncGrep
    grep for files and load results in quickfix 
AsyncShell
    run any program and load results in a split 
AsyncCscopeFindSymbol, AsyncCscopeFindCalls, AsyncCscopeFindX 
    cscope commands
AsyncMake
    run your makeprg with input arguments and load the results in quickfix

For more information, see :help asynccommand
