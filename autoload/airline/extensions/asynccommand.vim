" Show AsyncCommand in vim-airline

function! airline#extensions#asynccommand#init(ext)
    if !exists("g:loaded_asynccommand") || !g:loaded_asynccommand || exists("g:asynccommand_no_airline")
        return
    endif
    call a:ext.add_statusline_funcref(function('airline#extensions#asynccommand#apply'))
endfunction

function! airline#extensions#asynccommand#apply(...)
    let w:airline_section_y = get(w:, 'airline_section_y', g:airline_section_y)
    let w:airline_section_y = '%{asynccommand#statusline()} ' . g:airline_left_sep . w:airline_section_y
endfunction
