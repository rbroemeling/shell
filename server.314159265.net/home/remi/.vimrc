" explicitly disable vi-compatibility mode
set nocompatible

" turn on syntax hilighting
syntax on

" set a tab width of 8 characters
set shiftwidth=8
set softtabstop=8
set tabstop=8

" always round to a multiple of shiftwidth
set shiftround

" use the current line's indent level to set the indent
" level of new lines
set autoindent

" attempt to intelligently guess the indent level of any new line based on the
" previous line
set smartindent

" jump to the matching brace/paranthese/bracket whenever a closing or opening
" brace/paranthese/bracket is typed
set showmatch

" show the matching bracket (showmatch) for this many tenths of a second
set matchtime=5

" disable audible beeps -- use visual beeps instead
set vb t_vb=

" search for text as it is entered
set incsearch

" allow the cursor to roam anywhere it likes while in command mode
set virtualedit=all

" hilight the line that the cursor is currently on
set cursorline

" show tabs and trailing whitespace
set list
set listchars=tab:>.,trail:.

" disable line numbers
set number

" support up to line number 9999
set numberwidth=4

" always show current positions in the status bar
set ruler

" keep 5 lines (at the top and the bottom) for scope
set scrolloff=10

" disable automatic line wrapping
set nowrap

" case insensitive searching by default...
set ignorecase

" ... but if there are capital letters, go case-sensitive
set smartcase