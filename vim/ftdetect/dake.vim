au BufNewFile,BufRead *.dake,Dakefile call SetDakeOptions()
if !exists("*SetDakeOptions")
    function SetDakeOptions()
        set autoindent
        set filetype=dake syntax=dake
        setlocal shiftwidth=4 softtabstop=4
        setlocal indentkeys=!^F,o,O
    endfunction
endif
