set nocompatible " do not have strict vi compatibility
syntax on 
set number " set line number
set relativenumber " set relative line number
set autoindent " when new line, cursor checks where the previous line started

set softtabstop=0 noexpandtab shiftwidth=4 " tab behaviour

" searching:
set incsearch " colours what was matched, when searching
set smartcase " case-insensitive searching, but case-sensitive if you use capital letters
set hlsearch " highlights all search results
set hidden " allow switching buffers without saving


nnoremap ; :o
" use » to mark Tabs and ° to mark trailing whitespace. This is a
" non-obtrusive way to mark these special characters.
set list listchars=tab:»\ ,trail:°

set clipboard=unnamedplus

