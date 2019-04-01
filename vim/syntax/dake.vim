"
"  Vim syntax file for dake
"  Based on https://bitbucket.org/larsyencken/vim-drake-syntax.git
"  Language: dake
"  Latest Revision: 2019-03-31
"

if exists("b:current_syntax")
  finish
endif

syn include @Shell syntax/sh.vim
unlet b:current_syntax

syn include @Python syntax/python.vim
unlet b:current_syntax

syn include @Ruby syntax/ruby.vim
unlet b:current_syntax

syn include @Awk syntax/awk.vim
unlet b:current_syntax

syn include @R syntax/r.vim
let b:current_syntax = 'dake'

" Comments Tag Pattern Directives and Protocols
syn match dakeTag /@[^ ,@"'[\]]\+\|"[^"]*"\|'[^']*'/ contained contains=dakeVariableRef
syn match dakeDirective "^%[a-zA-Z_][a-zA-Z_]*"
syn match dakeComment "#.*$" contains=dakeTodo
syn keyword dakeTodo contained TODO NOTE FIXME XXX
syn keyword dakeProtocol contained shell python ruby awk R

" Variable definitions
syn match dakeSetVariable "^[a-zA-Z_][a-zA-Z0-9_]* *|\?= *" contains=dakeVariable nextgroup=dakeString
syn match dakeVariable "^[a-zA-Z_][a-zA-Z0-9_]*" contained
syn match dakeString /[^ ,@"'[\]]\+\|"[^"]*"\|'[^']*'/ contained contains=dakeVariableRef containedin=dakeSetValue nextgroup=dakeString
syn match dakeEscChar /\\\(x[0-9a-fA-F]\{1,2}\|u[0-9a-fA-F]\{1,4}\|.\)/ contained containedin=dakeString

" Method blocks
syn region dakeMethodBlock start="^[a-zA-Z_][a-zA-Z0-9_]*()" end="^$" contains=dakeMethodSignature
syn match dakeMethodSignature "^[a-zA-Z_][a-zA-Z0-9_]*" contained nextgroup=dakeMethodBraces
syn match dakeMethodBraces "()" contained nextgroup=dakeOptionListPy,dakeOptionListRb,dakeOptionListAwk,dakeOptionListR,dakeOptionListSh,dakeOptionList,dakeDefaultShBlock skipwhite skipnl

" Variable references in strings
syn region dakeVariableRef start='\$\[' end='\]' contained containedin=dakeString,dakeRbBlock,rubyString,dakePyBlock,pythonString,dakeAwkBlock,awkString,dakeRBlock,rString,dakeDefaultShBlock,dakeShBLock,shCmdParenRegion,shPattern,shDeref,shDerefSimple,shDoubleQuote,shExDoubleQuote,shSingleQuote,shExSingleQuote,shHereDoc,shHereString,shEcho contains=dakeVariableName
syn match dakeVariableName "[a-zA-Z_][a-zA-Z0-9_]*" contained containedin=dakeVariableRef

" Rule blocks
syn region dakeBlock start="[^<#, ][^<#, ]*\(, [^<#, ][^<#, ]*\)* <-" end="^$" contains=dakeRule
syn match dakeRule "[^<#, ].* <-\( *[^[<# ][^<# ]*\)*" contains=dakeTargets nextgroup=dakeOptionListPy,dakeOptionListRb,dakeOptionListAwk,dakeOptionListR,dakeOptionListSh,dakeOptionList,dakeDefaultShBlock skipwhite skipnl
syn match dakeTargets "[^<#, ][^<#, ]*\(, [^<#, ][^<#, ]*\)*" contained nextgroup=dakeRuleIdentifier contains=dakeTag,dakeString,dakeTargetSep
syn match dakeRuleIdentifier " <-" contained nextgroup=dakeSources
syn match dakeTargetSep ", " contained containedin=dakeTargets
syn region dakeOptionList matchgroup=Snip start=/\v \[/ end="\]" contained contains=dakeOption nextgroup=dakeShBlock skipwhite skipnl
syn region dakeOptionListSh matchgroup=Snip start=/\v \[(shell|.* shell)/ end="\]" contained contains=dakeOption,dakeProtocol nextgroup=dakeShBlock skipwhite skipnl
syn region dakeOptionListPy matchgroup=Snip start=/\v \[(python|.* python)/ end="\]" contained contains=dakeOption,dakeProtocol nextgroup=dakePyBlock skipwhite skipnl
syn region dakeOptionListRb matchgroup=Snip start=/\v \[(ruby|.* ruby)/ end="\]" contained contains=dakeOption,dakeProtocol nextgroup=dakeRbBlock skipwhite skipnl
syn region dakeOptionListAwk matchgroup=Snip start=/\v \[(awk|.* awk)/ end="\]" contained contains=dakeOption,dakeProtocol nextgroup=dakeAwkBlock skipwhite skipnl
syn region dakeOptionListR matchgroup=Snip start=/\v \[(R|.* R)/ end="\]" contained contains=dakeOption,dakeProtocol nextgroup=dakeRBlock skipwhite skipnl
syn match dakeOption '[a-zA-Z_][a-zA-Z0-9_]*:\|[+-][a-zA-Z_][a-zA-Z0-9_]*' contained nextgroup=dakeString

hi link dakeComment Comment
hi link dakeTodo rubyConstant
hi link dakeProtocol PreProc
hi link dakeVariable shVariable
hi link dakeVariableName shDerefSimple
hi link dakeSetIdentifier Delimiter
hi link dakeRuleIdentifier Delimiter
hi link dakeTag rubyConstant
hi link dakeString String
hi link dakeEscChar shEscape
hi link VarBraces SpecialComment
hi link dakeTargetSep Delimiter
hi link dakeDirective PreProc
hi link dakeOption Constant

" Embedded shell region in block
syn region dakeDefaultShBlock start='^\(#.*$\n\)*[ \t][ \t]*' end='^$' contained containedin=dakeBlock,dakeMethodBlock contains=@Shell
syn region dakeShBlock start=/^\(#.*$\n\)*[ \t]/ end='^$' contained contains=@Shell
syn region dakePyBlock start=/^\(#.*$\n\)*[ \t]/ end='^$' contained contains=@Python
syn region dakeRbBlock start=/^\(#.*$\n\)*[ \t]/ end='^$' contained contains=@Ruby
syn region dakeAwkBlock start=/^\(#.*$\n\)*[ \t]/ end='^$' contained contains=@Awk
syn region dakeRBlock start=/^\(#.*$\n\)*[ \t]/ end='^$' contained contains=@R

" Embedded shell regions in strings
syn region shellBrackets matchgroup=SnipBraces start='\$(' end=')' containedin=dakeString contains=@Shell

hi link Snip SpecialComment
hi link SnipBraces SpecialComment
hi link dakeVariableRef shDerefSimple
hi link dakeMethodSignature Function
hi link dakeMethodBraces SpecialComment

" Syncing
syn sync minlines=20 maxlines=200

