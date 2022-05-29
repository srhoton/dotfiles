syntax on
filetype plugin indent on
set number
set relativenumber
set ruler
set term=xterm-256color
set expandtab           " enter spaces when tab is pressed
set textwidth=120       " break lines when line length increases
set tabstop=4           " use 4 spaces to represent tab
set softtabstop=4
set shiftwidth=4        " number of spaces to use for auto indent
set autoindent          " copy indent from current line when starting a new line
set smartindent
set smarttab
set expandtab
set backspace=indent,eol,start
set showcmd
set mouse=a

"Coc install
call plug#begin()
Plug 'neoclide/coc.nvim', {'branch': 'release'}
call plug#end()

" Automatically closing braces
inoremap {<CR> {<CR>}<Esc>ko<tab>
inoremap [<CR> [<CR>]<Esc>ko<tab>
inoremap (<CR> (<CR>)<Esc>ko<tab>
