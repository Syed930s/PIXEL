format MZ
stack 2000h

MAX_FILES       = 256
MAX_TREE        = 64

ENTRY_SIZE      = 24
TREE_SIZE       = 16

F_NAME          = 0
F_ATTR          = 13
F_SIZE_LO       = 14
F_SIZE_HI       = 16

VISIBLE         = 10
ROW_H           = 10

MENU_TOP        = 26
TITLE_H         = 12
MENU_Y          = 12
MENU_H          = 14
TOOLBAR_Y       = 27
TOOLBAR_H       = 16
DRIVE_Y         = 44
DRIVE_H         = 14
CONTENT_Y       = 58
PANE_Y          = 60
PANE_H          = 122
HEADER_Y        = 63
LIST_TOP        = 74
STATUS_Y        = 184
STATUS_H        = 16

INPUT_MAX       = 20
COPY_BUF_SIZE   = 2048

segment main
entry main:start

start:
    mov ax,cs
    mov ds,ax
    mov es,ax
    cld

    mov ax,13h
    int 10h

    call init_font
    call init_mouse
    call update_path
    call refresh_all

main_loop:
    call update_layout
    call render_all
    call process_input
    call wait_vsync
    jmp main_loop

exit_program:
    mov ax,3
    int 10h

    mov ax,4C00h
    int 21h

; ================================================================
; INIT
; ================================================================

init_mouse:
    push es

    xor ax,ax
    mov es,ax

    mov ax,[es:0CCh]
    mov bx,[es:0CEh]
    or ax,bx

    pop es
    jz .no_mouse

    xor ax,ax
    int 33h
    test ax,ax
    jz .no_mouse

    mov ax,1
    int 33h
    mov byte [mouse_ok],1

.no_mouse:
    ret

init_font:
    push ax
    push bx
    push cx
    push si
    push di
    push bp

    mov ax,1130h
    mov bh,0
    int 10h

    push ds

    mov ax,es
    mov ds,ax
    mov si,bp

    mov ax,cs
    mov es,ax
    mov di,font_data
    mov cx,2048
    cld
    rep movsb

    pop ds

    pop bp
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

update_layout:
    cmp byte [show_tree],0
    je .no_tree

    mov word [tree_x],2
    mov word [tree_w],84
    mov word [file_x],88
    mov word [file_w],230
    ret

.no_tree:
    mov word [tree_x],0
    mov word [tree_w],0
    mov word [file_x],2
    mov word [file_w],316
    ret

; ================================================================
; PATH / DIRECTORY
; ================================================================

update_path:
    push ax
    push bx
    push cx
    push si
    push di

    mov ah,19h
    int 21h
    add al,'A'
    mov [current_drive],al

    mov ah,47h
    xor dl,dl
    mov si,dir_buffer
    int 21h
    jc .root

    cmp byte [dir_buffer],0
    je .root

    mov byte [is_root],0
    jmp .build

.root:
    mov byte [is_root],1

.build:
    push ds
    pop es

    mov di,current_path

    mov al,[current_drive]
    stosb

    mov al,':'
    stosb

    mov al,'\'
    stosb

    cmp byte [is_root],1
    je .null_end

    mov si,dir_buffer
    call str_copy
    jmp .after

.null_end:
    xor al,al
    stosb

.after:
    push ds
    pop es

    mov si,current_path
    mov di,path_display
    mov cx,24

.trunc:
    lodsb
    test al,al
    jz .trunc_done
    stosb
    loop .trunc

.trunc_done:
    mov byte [di],0

    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

change_dir:
    mov ah,3Bh
    int 21h
    jc .error

    call update_path
    call refresh_all
    ret

.error:
    mov si,msg_cannot_open
    call show_error
    ret

change_drive:
    cmp al,3
    ja .done

    mov dl,al
    mov ah,0Eh
    int 21h

    mov dx,root_path
    call change_dir

.done:
    ret

build_full_path:
    mov [tmp_src],si
    mov [tmp_dst],di

    push ds
    pop es

    mov si,current_path
    mov di,[tmp_dst]
    call str_copy

    dec di

    cmp di,[tmp_dst]
    je .append

    cmp byte [di-1],'\'
    je .append

    mov al,'\'
    stosb

.append:
    mov si,[tmp_src]
    call str_copy
    ret

; ================================================================
; REFRESH / LIST BUILDING
; ================================================================

refresh_all:
    call refresh_tree
    call refresh_files

    mov word [file_selected],0
    mov word [file_scroll],0
    mov word [tree_selected],0
    mov word [tree_scroll],0

    ret

refresh_files:
    mov ah,1Ah
    mov dx,dta_buffer
    int 21h

    mov word [file_count],0
    mov word [file_start],0

    cmp byte [is_root],1
    je .no_parent

    mov si,dotdot_name
    mov bl,10h
    xor cx,cx
    xor dx,dx
    call add_file_entry

    mov word [file_start],1

.no_parent:
    mov ah,4Eh
    mov cx,37h
    mov dx,star_dot_star
    int 21h
    jc .done

.next:
    mov al,[dta_buffer+15h]

    test al,08h
    jnz .find_next

    cmp byte [dta_buffer+1Eh],'.'
    je .find_next

    cmp byte [show_hidden],0
    jne .include

    test al,06h
    jnz .find_next

.include:
    mov si,dta_buffer+1Eh
    mov bl,al
    mov cx,[dta_buffer+1Ah]
    mov dx,[dta_buffer+1Ch]
    call add_file_entry

.find_next:
    mov ah,4Fh
    int 21h
    jnc .next

.done:
    call sort_file_list
    ret

refresh_tree:
    mov ah,1Ah
    mov dx,dta_buffer
    int 21h

    mov word [tree_count],0

    cmp byte [is_root],1
    je .no_parent

    mov si,dotdot_name
    call add_tree_entry

.no_parent:
    mov ah,4Eh
    mov cx,37h
    mov dx,star_dot_star
    int 21h
    jc .done

.next:
    mov al,[dta_buffer+15h]

    test al,10h
    jz .find_next

    test al,08h
    jnz .find_next

    cmp byte [show_hidden],0
    jne .include

    test al,06h
    jnz .find_next

.include:
    mov si,dta_buffer+1Eh
    call add_tree_entry

.find_next:
    mov ah,4Fh
    int 21h
    jnc .next

.done:
    ret

add_file_entry:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    cmp word [file_count],MAX_FILES
    jge .done

    mov ax,[file_count]
    mov bx,ENTRY_SIZE
    mul bx

    mov di,file_list
    add di,ax

    call copy_name13

    mov [di],bl
    mov [di+1],cx
    mov [di+3],dx

    inc word [file_count]

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

add_tree_entry:
    push ax
    push bx
    push cx
    push si
    push di

    cmp word [tree_count],MAX_TREE
    jge .done

    mov ax,[tree_count]
    mov bx,TREE_SIZE
    mul bx

    mov di,tree_list
    add di,ax

    call copy_name13

    mov byte [di],0
    mov byte [di+1],0
    mov byte [di+2],0

    inc word [tree_count]

.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

copy_name13:
    push ds
    pop es

    mov cx,13

.copy:
    lodsb
    test al,al
    jz .fill
    stosb
    loop .copy
    jmp .done

.fill:
    stosb
    dec cx
    jz .done

    xor al,al
    rep stosb

.done:
    ret

; ================================================================
; SORTING
; ================================================================

sort_file_list:
    cmp word [file_count],2
    jb .done

    mov ax,[file_start]
    mov [sort_i],ax

.outer:
    mov ax,[sort_i]
    cmp ax,[file_count]
    jge .done

    mov bx,ax
    inc bx

.inner:
    cmp bx,[file_count]
    jge .next_i

    mov [cmp_i],ax
    mov [cmp_j],bx

    push ax
    push bx
    call compare_entries
    pop bx
    pop ax

    jnc .no_swap

    push ax
    push bx
    call swap_entries
    pop bx
    pop ax

.no_swap:
    inc bx
    jmp .inner

.next_i:
    inc word [sort_i]
    jmp .outer

.done:
    ret

compare_entries:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov bx,[cmp_i]
    call get_file_entry
    mov di,si

    mov bx,[cmp_j]
    call get_file_entry

    mov al,[di+F_ATTR]
    and al,10h
    mov bl,[si+F_ATTR]
    and bl,10h

    cmp al,bl
    je .mode

    test al,al
    jnz .less

    stc
    jmp .done

.mode:
    cmp byte [sort_mode],0
    je .name

    cmp byte [sort_mode],1
    je .size

    clc
    jmp .done

.name:
    mov cx,13

.name_loop:
    mov al,[di]
    mov bl,[si]

    cmp al,bl
    ja .greater
    jb .less

    inc di
    inc si
    loop .name_loop

    clc
    jmp .done

.size:
    mov ax,[di+F_SIZE_HI]
    cmp ax,[si+F_SIZE_HI]
    ja .greater
    jb .less

    mov ax,[di+F_SIZE_LO]
    cmp ax,[si+F_SIZE_LO]
    ja .greater
    jb .less

    clc
    jmp .done

.greater:
    stc
    jmp .done

.less:
    clc

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

swap_entries:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov bx,[cmp_i]
    call get_file_entry
    mov di,si

    mov bx,[cmp_j]
    call get_file_entry

    mov cx,ENTRY_SIZE/2

.swap_loop:
    mov ax,[di]
    mov dx,[si]

    mov [si],ax
    mov [di],dx

    add di,2
    add si,2
    loop .swap_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

get_file_entry:
    push ax
    push dx

    mov ax,bx
    mov bx,ENTRY_SIZE
    mul bx

    add ax,file_list
    mov si,ax

    pop dx
    pop ax
    ret

get_tree_entry:
    push ax
    push dx

    mov ax,bx
    mov bx,TREE_SIZE
    mul bx

    add ax,tree_list
    mov si,ax

    pop dx
    pop ax
    ret

; ================================================================
; INPUT
; ================================================================

process_input:
    mov ah,1
    int 16h
    jz .mouse

    mov ah,0
    int 16h
    call handle_keyboard

.mouse:
    cmp byte [mouse_ok],0
    je .done

    mov ax,3
    int 33h

    shr cx,1

    mov [mouse_x],cx
    mov [mouse_y],dx

    test bx,1
    jz .no_left

    test [prev_buttons],1
    jnz .update

    call handle_mouse_down
    jmp .update

.no_left:
    test [prev_buttons],1
    jz .update
    call handle_mouse_up

.update:
    mov [prev_buttons],bx

.done:
    ret

handle_keyboard:
    cmp byte [menu_open],0
    je .no_menu

    cmp al,1Bh
    je .close_menu

    cmp al,0Dh
    je .exec_menu

    ret

.exec_menu:
    cmp word [selected_menu_item],0FFFFh
    je .close_menu

    call execute_menu_item
    call close_menu
    ret

.close_menu:
    call close_menu
    ret

.no_menu:
    test al,al
    jnz .ascii

    cmp ah,48h
    je .up

    cmp ah,50h
    je .down

    cmp ah,3Fh
    je .f5

    cmp ah,41h
    je .f7

    cmp ah,53h
    je .del

    ret

.ascii:
    cmp al,1Bh
    je .esc

    cmp al,0Dh
    je .enter

    cmp al,08h
    je .backspace

    cmp al,09h
    je .tab

    cmp al,' '
    jb .done

    ret

.up:
    cmp byte [active_pane],0
    je .file_up

    call select_tree_prev
    ret

.file_up:
    call select_file_prev
    ret

.down:
    cmp byte [active_pane],0
    je .file_down

    call select_tree_next
    ret

.file_down:
    call select_file_next
    ret

.f5:
    call refresh_all
    ret

.f7:
    call create_directory
    ret

.del:
    call delete_selected
    ret

.esc:
    call confirm_exit
    ret

.enter:
    call open_active
    ret

.backspace:
    mov dx,dotdot_path
    call change_dir
    ret

.tab:
    mov al,[active_pane]
    xor al,1
    mov [active_pane],al
    ret

.done:
    ret

handle_mouse_down:
    mov ax,[mouse_y]

    cmp ax,TITLE_H
    jl .done

    cmp ax,MENU_TOP
    jl .menu_bar

    cmp byte [menu_open],0
    jne .menu_click_outside

    cmp ax,DRIVE_Y
    jl .toolbar

    cmp ax,CONTENT_Y
    jl .drive

    cmp ax,STATUS_Y
    jl .content

    ret

.menu_bar:
    mov ax,[mouse_x]

    cmp ax,34
    jl .open_file_menu

    cmp ax,74
    jl .open_options_menu

    cmp ax,106
    jl .open_view_menu

    cmp ax,138
    jl .open_help_menu

    call close_menu
    ret

.open_file_menu:
    mov al,0
    jmp .toggle_menu

.open_options_menu:
    mov al,1
    jmp .toggle_menu

.open_view_menu:
    mov al,2
    jmp .toggle_menu

.open_help_menu:
    mov al,3

.toggle_menu:
    cmp byte [menu_open],0
    je .open_it

    cmp [menu_selected],al
    je .close_it

.open_it:
    call open_menu
    ret

.close_it:
    call close_menu
    ret

.menu_click_outside:
    call setup_menu

    mov ax,[mouse_y]
    cmp ax,MENU_TOP
    jl .close_menu_now

    mov bx,[menu_count]
    mov cx,ROW_H
    mul cx
    add ax,MENU_TOP+4

    mov bx,[mouse_y]
    cmp bx,ax
    jg .close_menu_now

    mov ax,[mouse_x]
    cmp ax,[menu_x]
    jl .close_menu_now

    mov bx,[menu_x]
    add bx,[menu_w]
    cmp ax,bx
    jg .close_menu_now

    mov ax,[mouse_y]
    sub ax,MENU_TOP

    xor dx,dx
    mov bx,ROW_H
    div bx

    cmp ax,[menu_count]
    jge .close_menu_now

    mov [selected_menu_item],ax
    ret

.close_menu_now:
    call close_menu
    ret

.toolbar:
    call handle_toolbar_click
    ret

.drive:
    call handle_drive_click
    ret

.content:
    call handle_content_click
    ret

.done:
    ret

handle_mouse_up:
    cmp byte [menu_open],0
    je .done

    cmp word [selected_menu_item],0FFFFh
    je .done

    call execute_menu_item
    call close_menu

.done:
    ret

handle_toolbar_click:
    mov ax,[mouse_x]

    cmp ax,2
    jl .done
    cmp ax,36
    jl .open

    cmp ax,38
    jl .done
    cmp ax,68
    jl .new

    cmp ax,70
    jl .done
    cmp ax,100
    jl .del

    cmp ax,102
    jl .done
    cmp ax,134
    jl .ren

    cmp ax,136
    jl .done
    cmp ax,172
    jl .copy

    cmp ax,174
    jl .done
    cmp ax,212
    jl .move

    cmp ax,214
    jl .done
    cmp ax,256
    jl .paste

.done:
    ret

.open:
    call open_selected_file
    ret

.new:
    call create_directory
    ret

.del:
    call delete_selected
    ret

.ren:
    call rename_selected
    ret

.copy:
    call copy_selected
    ret

.move:
    call move_selected
    ret

.paste:
    call paste_clipboard
    ret

handle_drive_click:
    mov ax,[mouse_y]
    cmp ax,45
    jl .done
    cmp ax,57
    jg .done

    mov ax,[mouse_x]
    cmp ax,40
    jl .done
    cmp ax,102
    jg .done

    sub ax,40

    xor dx,dx
    mov bx,16
    div bx

    cmp ax,3
    ja .done

    call change_drive

.done:
    ret

handle_content_click:
    cmp byte [show_tree],0
    je .file_pane

    mov ax,[mouse_x]
    cmp ax,[tree_x]
    jl .file_pane

    mov bx,[tree_x]
    add bx,[tree_w]
    cmp ax,bx
    jge .file_pane

    mov byte [active_pane],1

    mov ax,[mouse_y]
    cmp ax,LIST_TOP
    jl .done

    sub ax,LIST_TOP

    xor dx,dx
    mov bx,ROW_H
    div bx

    add ax,[tree_scroll]
    cmp ax,[tree_count]
    jge .done

    mov bx,ax
    cmp bx,[tree_selected]
    je .open_tree

    call set_tree_selection
    ret

.open_tree:
    call open_selected_tree
    ret

.file_pane:
    mov byte [active_pane],0

    mov ax,[mouse_x]
    cmp ax,[file_x]
    jl .done

    mov bx,[file_x]
    add bx,[file_w]
    cmp ax,bx
    jge .done

    mov ax,[mouse_y]
    cmp ax,LIST_TOP
    jl .done

    sub ax,LIST_TOP

    xor dx,dx
    mov bx,ROW_H
    div bx

    add ax,[file_scroll]
    cmp ax,[file_count]
    jge .done

    mov bx,ax
    cmp bx,[file_selected]
    je .open_file

    call set_file_selection
    ret

.open_file:
    call open_selected_file
    ret

.done:
    ret

; ================================================================
; SELECTION / NAVIGATION
; ================================================================

set_file_selection:
    cmp bx,[file_count]
    jge .done

    mov [file_selected],bx
    call ensure_file_visible

.done:
    ret

set_tree_selection:
    cmp bx,[tree_count]
    jge .done

    mov [tree_selected],bx
    call ensure_tree_visible

.done:
    ret

select_file_next:
    cmp word [file_count],0
    je .done

    mov bx,[file_selected]
    inc bx

    cmp bx,[file_count]
    jge .done

    mov [file_selected],bx
    call ensure_file_visible

.done:
    ret

select_file_prev:
    mov bx,[file_selected]
    cmp bx,0
    jle .done

    dec bx
    mov [file_selected],bx
    call ensure_file_visible

.done:
    ret

select_tree_next:
    cmp word [tree_count],0
    je .done

    mov bx,[tree_selected]
    inc bx

    cmp bx,[tree_count]
    jge .done

    mov [tree_selected],bx
    call ensure_tree_visible

.done:
    ret

select_tree_prev:
    mov bx,[tree_selected]
    cmp bx,0
    jle .done

    dec bx
    mov [tree_selected],bx
    call ensure_tree_visible

.done:
    ret

ensure_file_visible:
    mov bx,[file_selected]

    mov ax,[file_scroll]
    cmp bx,ax
    jl .up

    add ax,VISIBLE
    cmp bx,ax
    jge .down

    ret

.up:
    mov [file_scroll],bx
    ret

.down:
    sub bx,VISIBLE-1
    mov [file_scroll],bx
    ret

ensure_tree_visible:
    mov bx,[tree_selected]

    mov ax,[tree_scroll]
    cmp bx,ax
    jl .up

    add ax,VISIBLE
    cmp bx,ax
    jge .down

    ret

.up:
    mov [tree_scroll],bx
    ret

.down:
    sub bx,VISIBLE-1
    mov [tree_scroll],bx
    ret

open_active:
    cmp byte [active_pane],0
    je .file

    call open_selected_tree
    ret

.file:
    call open_selected_file
    ret

open_selected_file:
    call get_selected_file_entry
    jc .done

    mov [entry_ptr],si

    mov bl,[si+F_ATTR]
    test bl,10h
    jz .file

    mov dx,si
    call change_dir
    ret

.file:
    call show_properties
    ret

.done:
    ret

open_selected_tree:
    mov bx,[tree_selected]
    cmp bx,[tree_count]
    jge .done

    call get_tree_entry
    mov dx,si
    call change_dir

.done:
    ret

get_selected_file_entry:
    mov bx,[file_selected]
    cmp bx,[file_count]
    jge .error

    call get_file_entry
    clc
    ret

.error:
    stc
    ret

; ================================================================
; MENUS
; ================================================================

open_menu:
    mov [menu_selected],al
    mov byte [menu_open],1
    mov word [selected_menu_item],0FFFFh
    call setup_menu
    ret

close_menu:
    mov byte [menu_open],0
    mov word [selected_menu_item],0FFFFh
    ret

setup_menu:
    mov al,[menu_selected]

    cmp al,0
    je .file

    cmp al,1
    je .options

    cmp al,2
    je .view

    mov word [menu_x],106
    mov word [menu_w],80
    mov word [menu_count],1
    ret

.file:
    mov word [menu_x],2
    mov word [menu_w],110
    mov word [menu_count],12
    ret

.options:
    mov word [menu_x],34
    mov word [menu_w],110
    mov word [menu_count],2
    ret

.view:
    mov word [menu_x],74
    mov word [menu_w],110
    mov word [menu_count],4
    ret

execute_menu_item:
    mov al,[menu_selected]

    cmp al,0
    je .file

    cmp al,1
    je .options

    cmp al,2
    je .view

    cmp al,3
    je .help

    ret

.file:
    mov ax,[selected_menu_item]

    cmp ax,0
    je .file_open

    cmp ax,2
    je .file_copy

    cmp ax,3
    je .file_move

    cmp ax,4
    je .file_paste

    cmp ax,6
    je .file_delete

    cmp ax,7
    je .file_rename

    cmp ax,8
    je .file_mkdir

    cmp ax,9
    je .file_props

    cmp ax,11
    je .file_exit

    ret

.file_open:
    call open_selected_file
    ret

.file_copy:
    call copy_selected
    ret

.file_move:
    call move_selected
    ret

.file_paste:
    call paste_clipboard
    ret

.file_delete:
    call delete_selected
    ret

.file_rename:
    call rename_selected
    ret

.file_mkdir:
    call create_directory
    ret

.file_props:
    call show_properties
    ret

.file_exit:
    call confirm_exit
    ret

.options:
    mov ax,[selected_menu_item]

    cmp ax,0
    je .opt_hidden

    cmp ax,1
    je .opt_tree

    ret

.opt_hidden:
    call toggle_hidden
    ret

.opt_tree:
    call toggle_tree
    ret

.view:
    mov ax,[selected_menu_item]

    cmp ax,0
    je .view_refresh

    cmp ax,2
    je .view_sort_name

    cmp ax,3
    je .view_sort_size

    ret

.view_refresh:
    call refresh_all
    ret

.view_sort_name:
    mov byte [sort_mode],0
    call sort_file_list
    ret

.view_sort_size:
    mov byte [sort_mode],1
    call sort_file_list
    ret

.help:
    mov ax,[selected_menu_item]

    cmp ax,0
    je .help_about

    ret

.help_about:
    call show_about
    ret

toggle_hidden:
    mov al,[show_hidden]
    xor al,1
    mov [show_hidden],al
    call refresh_all
    ret

toggle_tree:
    mov al,[show_tree]
    xor al,1
    mov [show_tree],al
    ret

; ================================================================
; FILE OPERATIONS
; ================================================================

copy_selected:
    call get_selected_file_entry
    jc .done

    mov [entry_ptr],si

    mov bl,[si+F_ATTR]
    test bl,10h
    jnz .dir_not_supported

    mov si,[entry_ptr]
    mov di,clip_name
    call str_copy

    mov si,[entry_ptr]
    mov di,clip_path
    call build_full_path

    mov byte [clip_op],1
    mov word [clip_count],1

.done:
    ret

.dir_not_supported:
    mov si,msg_dir_not_supported
    call show_info
    ret

move_selected:
    call get_selected_file_entry
    jc .done

    mov [entry_ptr],si

    mov bl,[si+F_ATTR]
    test bl,10h
    jnz .dir_not_supported

    mov si,[entry_ptr]
    mov di,clip_name
    call str_copy

    mov si,[entry_ptr]
    mov di,clip_path
    call build_full_path

    mov byte [clip_op],2
    mov word [clip_count],1

.done:
    ret

.dir_not_supported:
    mov si,msg_dir_not_supported
    call show_info
    ret

paste_clipboard:
    cmp word [clip_count],0
    jne .do_paste

    mov si,msg_clipboard_empty
    call show_info
    ret

.do_paste:
    mov si,clip_name
    mov di,dest_path
    call build_full_path

    mov si,clip_path
    mov di,dest_path
    call str_equal

    test cx,cx
    jnz .same

    mov dx,clip_path
    mov di,dest_path

    cmp byte [clip_op],2
    je .move

    call copy_file
    jmp .after

.move:
    call move_file

.after:
    jc .error

    mov word [clip_count],0
    call refresh_all
    ret

.same:
    mov si,msg_same_path
    call show_info
    ret

.error:
    mov si,msg_paste_failed
    call show_error
    ret

delete_selected:
    call get_selected_file_entry
    jc .done

    cmp byte [si],'.'
    je .done

    mov [entry_ptr],si

    mov bl,[si+F_ATTR]
    mov [del_attr],bl

    mov di,temp_name
    call copy_name13_from_entry

    mov [dlg_title],msg_confirm_title
    mov [dlg_line1],msg_delete_confirm
    mov word [dlg_line2],0
    mov word [dlg_line3],0
    mov word [dlg_line4],0

    call confirm_box
    jc .done

    mov si,[entry_ptr]
    mov di,path_buffer
    call build_full_path

    mov dx,path_buffer

    cmp byte [del_attr],10h
    je .dir

    mov ah,41h
    jmp .do

.dir:
    mov ah,3Ah

.do:
    int 21h
    jc .error

    call refresh_all
    ret

.error:
    mov si,msg_delete_failed
    call show_error
    ret

.done:
    ret

rename_selected:
    call get_selected_file_entry
    jc .done

    cmp byte [si],'.'
    je .done

    mov [entry_ptr],si

    mov di,input_buffer
    call copy_name13_from_entry

    call update_input_len

    mov si,[entry_ptr]
    mov di,old_path
    call build_full_path

    mov [dlg_title],msg_rename_title
    mov [dlg_prompt],msg_new_name

    call input_box
    jc .done

    cmp byte [input_buffer],0
    je .done

    mov si,input_buffer
    mov di,new_path
    call build_full_path

    push ds
    pop es

    mov dx,old_path
    mov di,new_path
    mov ah,56h
    int 21h
    jc .error

    call refresh_all
    ret

.error:
    mov si,msg_rename_failed
    call show_error
    ret

.done:
    ret

create_directory:
    mov byte [input_buffer],0
    mov byte [input_len],0

    mov [dlg_title],msg_mkdir_title
    mov [dlg_prompt],msg_mkdir_prompt

    call input_box
    jc .done

    cmp byte [input_buffer],0
    je .done

    mov si,input_buffer
    mov di,path_buffer
    call build_full_path

    mov ah,39h
    mov dx,path_buffer
    int 21h
    jc .error

    call refresh_all
    ret

.error:
    mov si,msg_mkdir_failed
    call show_error
    ret

.done:
    ret

show_properties:
    call get_selected_file_entry
    jc .done

    mov [entry_ptr],si

    mov di,prop_line1
    mov si,msg_name_label
    call str_copy

    mov si,[entry_ptr]
    mov di,prop_line1
    call append_string

    mov di,prop_line2
    mov si,msg_size_label
    call str_copy

    mov si,[entry_ptr]
    mov bl,[si+F_ATTR]
    test bl,10h
    jz .size

    mov si,msg_size_dir
    mov di,prop_line2
    call append_string
    jmp .attr

.size:
    mov si,[entry_ptr]
    mov ax,[si+F_SIZE_LO]
    mov dx,[si+F_SIZE_HI]

    mov di,size_str
    call format_dword

    mov si,size_str
    mov di,prop_line2
    call append_string

.attr:
    mov di,prop_line3
    mov si,msg_attr_label
    call str_copy

    mov si,[entry_ptr]
    mov al,[si+F_ATTR]

    test al,10h
    jz .no_d

    mov di,prop_line3
    mov al,'D'
    call append_char

.no_d:
    mov si,[entry_ptr]
    mov al,[si+F_ATTR]

    test al,02h
    jz .no_h

    mov di,prop_line3
    mov al,'H'
    call append_char

.no_h:
    mov si,[entry_ptr]
    mov al,[si+F_ATTR]

    test al,04h
    jz .no_s

    mov di,prop_line3
    mov al,'S'
    call append_char

.no_s:
    mov si,[entry_ptr]
    mov al,[si+F_ATTR]

    test al,01h
    jz .no_r

    mov di,prop_line3
    mov al,'R'
    call append_char

.no_r:
    mov si,[entry_ptr]
    mov al,[si+F_ATTR]

    test al,20h
    jz .no_a

    mov di,prop_line3
    mov al,'A'
    call append_char

.no_a:
    mov [dlg_title],msg_props_title
    mov [dlg_line1],prop_line1
    mov [dlg_line2],prop_line2
    mov [dlg_line3],prop_line3
    mov word [dlg_line4],0

    call show_message

.done:
    ret

copy_name13_from_entry:
    push ax
    push cx
    push si
    push di

    push ds
    pop es

    mov si,[entry_ptr]
    mov cx,13

.copy:
    lodsb
    stosb
    test al,al
    jz .done
    loop .copy

.done:
    pop di
    pop si
    pop cx
    pop ax
    ret

copy_file:
    mov [copy_src],dx
    mov [copy_dst],di

    push ds
    pop es

    mov dx,[copy_src]
    mov ax,3D00h
    int 21h
    jc .error

    mov [src_handle],ax

    mov dx,[copy_dst]
    mov ax,3C00h
    xor cx,cx
    int 21h
    jc .close_src_error

    mov [dst_handle],ax

.loop:
    mov bx,[src_handle]
    mov dx,copy_buffer
    mov cx,COPY_BUF_SIZE
    mov ah,3Fh
    int 21h
    jc .close_both_error

    cmp ax,0
    je .success

    mov bx,[dst_handle]
    mov cx,ax
    mov dx,copy_buffer
    mov ah,40h
    int 21h
    jc .close_both_error

    cmp ax,cx
    jne .close_both_error

    jmp .loop

.success:
    mov bx,[dst_handle]
    mov ah,3Eh
    int 21h

    mov bx,[src_handle]
    mov ah,3Eh
    int 21h

    clc
    ret

.close_both_error:
    mov bx,[dst_handle]
    mov ah,3Eh
    int 21h

.close_src_error:
    mov bx,[src_handle]
    mov ah,3Eh
    int 21h

.error:
    stc
    ret

move_file:
    mov [copy_src],dx
    mov [copy_dst],di

    push ds
    pop es

    mov dx,[copy_src]
    mov di,[copy_dst]
    mov ah,56h
    int 21h
    jnc .success

    mov dx,[copy_src]
    mov di,[copy_dst]
    call copy_file
    jc .error

    mov dx,[copy_src]
    mov ah,41h
    int 21h
    jc .error

.success:
    clc
    ret

.error:
    stc
    ret

; ================================================================
; RENDER
; ================================================================

render_all:
    call draw_title_bar
    call draw_menu_bar
    call draw_toolbar
    call draw_drive_bar
    call draw_content
    call draw_status_bar

    cmp byte [menu_open],0
    je .no_menu
    call draw_active_menu

.no_menu:
    cmp byte [mouse_ok],0
    je .done
    call draw_cursor

.done:
    ret

draw_title_bar:
    box 0,0,320,TITLE_H,1
    puttext 112,2,15,title_str

    box 0,11,320,1,0
    ret

draw_menu_bar:
    box 0,MENU_Y,320,MENU_H,7
    box 0,25,320,1,8

    cmp byte [menu_open],0
    je .normal

    cmp byte [menu_selected],0
    jne .file_normal

    box 2,13,30,12,1
    puttext 4,15,15,menu_file
    jmp .options

.file_normal:
    puttext 4,15,0,menu_file

.options:
    cmp byte [menu_open],0
    je .options_normal

    cmp byte [menu_selected],1
    jne .options_normal

    box 34,13,38,12,1
    puttext 36,15,15,menu_options
    jmp .view

.options_normal:
    puttext 36,15,0,menu_options

.view:
    cmp byte [menu_open],0
    je .view_normal

    cmp byte [menu_selected],2
    jne .view_normal

    box 74,13,30,12,1
    puttext 76,15,15,menu_view
    jmp .help

.view_normal:
    puttext 76,15,0,menu_view

.help:
    cmp byte [menu_open],0
    je .help_normal

    cmp byte [menu_selected],3
    jne .help_normal

    box 106,13,30,12,1
    puttext 108,15,15,menu_help
    jmp .done

.help_normal:
    puttext 108,15,0,menu_help

.done:
    ret

draw_toolbar:
    box 0,TOOLBAR_Y-1,320,TOOLBAR_H+2,7

    mov ax,2
    mov bx,TOOLBAR_Y
    mov cx,34
    mov dx,16
    call draw_button_up
    puttext 6,31,0,tb_open

    mov ax,38
    mov bx,TOOLBAR_Y
    mov cx,30
    mov dx,16
    call draw_button_up
    puttext 42,31,0,tb_new

    mov ax,70
    mov bx,TOOLBAR_Y
    mov cx,30
    mov dx,16
    call draw_button_up
    puttext 74,31,0,tb_del

    mov ax,102
    mov bx,TOOLBAR_Y
    mov cx,32
    mov dx,16
    call draw_button_up
    puttext 106,31,0,tb_ren

    mov ax,136
    mov bx,TOOLBAR_Y
    mov cx,36
    mov dx,16
    call draw_button_up
    puttext 140,31,0,tb_copy

    mov ax,174
    mov bx,TOOLBAR_Y
    mov cx,38
    mov dx,16
    call draw_button_up
    puttext 178,31,0,tb_move

    mov ax,214
    mov bx,TOOLBAR_Y
    mov cx,42
    mov dx,16
    call draw_button_up
    puttext 218,31,0,tb_paste

    box 0,43,320,1,8
    ret

draw_drive_bar:
    box 0,DRIVE_Y,320,DRIVE_H,7
    box 0,57,320,1,8

    puttext 2,46,0,drive_label

    mov al,'A'
    mov bx,40
    call draw_drive_button

    mov al,'B'
    mov bx,56
    call draw_drive_button

    mov al,'C'
    mov bx,72
    call draw_drive_button

    mov al,'D'
    mov bx,88
    call draw_drive_button

    puttext 110,46,0,path_display
    ret

draw_drive_button:
    mov [drv_char],al
    mov [drv_x],bx

    cmp al,[current_drive]
    jne .normal

    box [drv_x],45,14,12,1

    mov al,[drv_char]
    mov [char_buffer],al
    mov byte [char_buffer+1],0

    mov ax,[drv_x]
    add ax,4
    mov bx,47
    mov cl,15
    mov si,char_buffer
    call draw_string

    ret

.normal:
    box [drv_x],45,14,12,7
    frame [drv_x],45,14,12,0

    mov al,[drv_char]
    mov [char_buffer],al
    mov byte [char_buffer+1],0

    mov ax,[drv_x]
    add ax,4
    mov bx,47
    mov cl,0
    mov si,char_buffer
    call draw_string

    ret

draw_content:
    box 0,CONTENT_Y,320,126,7

    cmp byte [show_tree],0
    je .no_tree

    mov ax,[tree_x]
    mov bx,PANE_Y
    mov cx,[tree_w]
    mov dx,PANE_H
    call draw_pane

    puttext 6,HEADER_Y,0,tree_title
    call draw_tree_list

.no_tree:
    mov ax,[file_x]
    mov bx,PANE_Y
    mov cx,[file_w]
    mov dx,PANE_H
    call draw_pane

    mov ax,[file_x]
    add ax,3
    mov bx,HEADER_Y
    mov cl,0
    mov si,name_title
    call draw_string

    mov ax,[file_x]
    add ax,112
    mov bx,HEADER_Y
    mov cl,0
    mov si,size_title
    call draw_string

    call draw_file_list
    ret

draw_tree_list:
    cmp word [tree_count],0
    jne .start

    ret

.start:
    mov ax,[tree_scroll]
    mov [draw_index],ax
    mov word [draw_y],LIST_TOP

    mov di,VISIBLE

.loop:
    push di

    mov ax,[draw_index]
    cmp ax,[tree_count]
    jge .exit_pop

    cmp ax,[tree_selected]
    jne .no_sel

    mov ax,[tree_x]
    inc ax

    mov bx,[draw_y]
    mov cx,[tree_w]
    sub cx,2
    mov dx,ROW_H

    mov byte [rect_color],1
    call draw_rect

    mov byte [row_color],15
    jmp .draw

.no_sel:
    mov byte [row_color],0

.draw:
    mov bx,[draw_index]
    call get_tree_entry

    mov cx,9
    call make_short_name

    mov ax,[tree_x]
    add ax,3

    mov bx,[draw_y]
    inc bx

    mov cl,[row_color]
    mov si,row_buffer
    call draw_string

    mov bx,[draw_y]
    add bx,ROW_H
    mov [draw_y],bx

    inc word [draw_index]

    pop di
    dec di
    jnz .loop

    ret

.exit_pop:
    pop di
    ret

draw_file_list:
    cmp word [file_count],0
    jne .start

    mov ax,[file_x]
    add ax,3
    mov bx,LIST_TOP
    mov cl,0
    mov si,no_files
    call draw_string

    ret

.start:
    mov ax,[file_scroll]
    mov [draw_index],ax
    mov word [draw_y],LIST_TOP

    mov di,VISIBLE

.loop:
    push di

    mov ax,[draw_index]
    cmp ax,[file_count]
    jge .exit_pop

    cmp ax,[file_selected]
    jne .no_sel

    mov ax,[file_x]
    inc ax

    mov bx,[draw_y]
    mov cx,[file_w]
    sub cx,2
    mov dx,ROW_H

    mov byte [rect_color],1
    call draw_rect

    mov byte [row_color],15
    jmp .draw

.no_sel:
    mov byte [row_color],0

.draw:
    mov bx,[draw_index]
    call get_file_entry

    mov [entry_ptr],si

    mov ax,[file_x]
    add ax,3

    mov bx,[draw_y]
    inc bx

    mov cl,[row_color]
    mov si,[entry_ptr]
    call draw_string

    mov si,[entry_ptr]
    mov bl,[si+F_ATTR]
    test bl,10h
    jz .size

    mov ax,[file_x]
    add ax,112

    mov bx,[draw_y]
    inc bx

    mov cl,[row_color]
    mov si,dir_str
    call draw_string

    jmp .after

.size:
    mov si,[entry_ptr]
    mov ax,[si+F_SIZE_LO]
    mov dx,[si+F_SIZE_HI]

    mov di,size_str
    call format_dword

    mov ax,[file_x]
    add ax,112

    mov bx,[draw_y]
    inc bx

    mov cl,[row_color]
    mov si,size_str
    call draw_string

.after:
    mov bx,[draw_y]
    add bx,ROW_H
    mov [draw_y],bx

    inc word [draw_index]

    pop di
    dec di
    jnz .loop

    ret

.exit_pop:
    pop di
    ret

draw_status_bar:
    box 0,STATUS_Y,320,STATUS_H,7
    box 0,STATUS_Y,320,1,8

    puttext 2,188,0,status_files

    mov di,count_str
    mov ax,[file_count]
    call format_word

    puttext 45,188,0,count_str
    puttext 85,188,0,sel_label

    call get_selected_file_entry
    jc .no_sel

    mov cx,12
    call make_short_name

    puttext 120,188,0,row_buffer
    ret

.no_sel:
    ret

draw_active_menu:
    call setup_menu

    mov al,[menu_selected]

    cmp al,0
    je .file

    cmp al,1
    je .options

    cmp al,2
    je .view

    cmp al,3
    je .help

    ret

.file:
    box [menu_x],MENU_TOP,[menu_w],124,15
    frame [menu_x],MENU_TOP,[menu_w],124,0

    menuitem 8,28,0,file_open
    menuitem 8,38,1,0
    menuitem 8,48,2,file_copy
    menuitem 8,58,3,file_move
    menuitem 8,68,4,file_paste
    menuitem 8,78,5,0
    menuitem 8,88,6,file_delete
    menuitem 8,98,7,file_rename
    menuitem 8,108,8,file_createdir
    menuitem 8,118,9,file_props
    menuitem 8,128,10,0
    menuitem 8,138,11,file_exit
    ret

.options:
    box [menu_x],MENU_TOP,[menu_w],24,15
    frame [menu_x],MENU_TOP,[menu_w],24,0

    menuitem 48,28,0,opt_hidden
    menuitem 48,38,1,opt_tree

    cmp byte [show_hidden],0
    je .no_hidden

    puttext 38,29,0,star_str

.no_hidden:
    cmp byte [show_tree],0
    je .no_tree

    puttext 38,39,0,star_str

.no_tree:
    ret

.view:
    box [menu_x],MENU_TOP,[menu_w],44,15
    frame [menu_x],MENU_TOP,[menu_w],44,0

    menuitem 88,28,0,view_refresh
    menuitem 88,38,1,0
    menuitem 88,48,2,view_sort_name
    menuitem 88,58,3,view_sort_size

    cmp byte [sort_mode],0
    jne .not_name

    puttext 78,49,0,star_str

.not_name:
    cmp byte [sort_mode],1
    jne .not_size

    puttext 78,59,0,star_str

.not_size:
    ret

.help:
    box [menu_x],MENU_TOP,[menu_w],14,15
    frame [menu_x],MENU_TOP,[menu_w],14,0

    menuitem 112,28,0,help_about
    ret

draw_menu_item:
    push ax
    push bx
    push cx
    push dx

    mov [mi_x],ax
    mov [mi_y],bx
    mov [mi_index],cx
    mov [mi_str],dx

    cmp dx,0
    jne .not_sep

    mov ax,[menu_x]
    add ax,2

    mov bx,[mi_y]
    add bx,4

    mov cx,[menu_w]
    sub cx,4

    mov dx,1
    mov byte [rect_color],8
    call draw_rect

    jmp .done

.not_sep:
    mov cx,[mi_index]
    cmp cx,[selected_menu_item]
    jne .normal

    mov ax,[menu_x]
    inc ax

    mov bx,[mi_y]

    mov cx,[menu_w]
    sub cx,2

    mov dx,ROW_H
    mov byte [rect_color],1
    call draw_rect

    mov byte [menu_text_color],15
    jmp .draw

.normal:
    mov byte [menu_text_color],0

.draw:
    mov ax,[mi_x]
    mov bx,[mi_y]
    inc bx

    mov cl,[menu_text_color]
    mov si,[mi_str]
    call draw_string

.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ================================================================
; WINDOWS 3.X STYLE DRAWING PRIMITIVES
; ================================================================

draw_button_up:
    push ax
    push bx
    push cx
    push dx

    mov [btn_x],ax
    mov [btn_y],bx
    mov [btn_w],cx
    mov [btn_h],dx

    box [btn_x],[btn_y],[btn_w],[btn_h],7

    box [btn_x],[btn_y],[btn_w],1,15
    box [btn_x],[btn_y],1,[btn_h],15

    mov ax,[btn_x]
    mov bx,[btn_y]
    add bx,[btn_h]
    dec bx
    mov cx,[btn_w]
    mov dx,1
    mov byte [rect_color],8
    call draw_rect

    mov ax,[btn_x]
    add ax,[btn_w]
    dec ax
    mov bx,[btn_y]
    mov cx,1
    mov dx,[btn_h]
    mov byte [rect_color],8
    call draw_rect

    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_pane:
    push ax
    push bx
    push cx
    push dx

    mov [pane_x],ax
    mov [pane_y],bx
    mov [pane_w],cx
    mov [pane_h],dx

    box [pane_x],[pane_y],[pane_w],[pane_h],15
    frame [pane_x],[pane_y],[pane_w],[pane_h],0

    mov ax,[pane_x]
    inc ax
    mov bx,[pane_y]
    inc bx
    mov cx,[pane_w]
    sub cx,2
    mov dx,1
    mov byte [rect_color],8
    call draw_rect

    mov ax,[pane_x]
    inc ax
    mov bx,[pane_y]
    inc bx
    mov cx,1
    mov dx,[pane_h]
    sub dx,2
    mov byte [rect_color],8
    call draw_rect

    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_rect:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov [rect_x],ax
    mov [rect_y],bx
    mov [rect_w],cx
    mov [rect_h],dx

    cmp cx,0
    je .done

    cmp dx,0
    je .done

    mov ax,0A000h
    mov es,ax

    mov dx,[rect_y]
    mov si,[rect_h]

.row:
    push dx
    push si

    mov ax,dx
    mov bx,320
    mul bx
    add ax,[rect_x]

    mov di,ax
    mov cx,[rect_w]
    mov al,[rect_color]
    rep stosb

    pop si
    pop dx

    inc dx
    dec si
    jnz .row

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_border:
    push ax
    push bx
    push cx
    push dx

    mov [brd_x],ax
    mov [brd_y],bx
    mov [brd_w],cx
    mov [brd_h],dx

    mov ax,[brd_x]
    mov bx,[brd_y]
    mov cx,[brd_w]
    mov dx,1
    call draw_rect

    mov ax,[brd_x]
    mov bx,[brd_y]
    add bx,[brd_h]
    dec bx
    mov cx,[brd_w]
    mov dx,1
    call draw_rect

    mov ax,[brd_x]
    mov bx,[brd_y]
    mov cx,1
    mov dx,[brd_h]
    call draw_rect

    mov ax,[brd_x]
    add ax,[brd_w]
    dec ax
    mov bx,[brd_y]
    mov cx,1
    mov dx,[brd_h]
    call draw_rect

    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_string:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    test si,si
    jz .done

    mov [str_x],ax
    mov [str_y],bx
    mov [str_c],cl

.char_loop:
    lodsb
    test al,al
    jz .done

    call draw_char

    mov ax,[str_x]
    add ax,8
    mov [str_x],ax

    jmp .char_loop

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_char:
    mov [char_code],al

    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov ax,0A000h
    mov es,ax

    mov al,[char_code]
    xor ah,ah
    mov si,ax

    add si,si
    add si,si
    add si,si
    add si,font_data

    mov bp,[str_y]
    mov di,8

.row:
    push di
    push bp
    push si

    mov dl,[si]
    mov bx,[str_x]
    mov cx,8

.col:
    shl dl,1
    jnc .no

    cmp bx,0
    jl .no

    cmp bx,320
    jge .no

    cmp bp,0
    jl .no

    cmp bp,200
    jge .no

    mov ax,bp

    push bx
    mov bx,320
    mul bx
    pop bx

    add ax,bx
    mov di,ax

    mov al,[str_c]
    stosb

.no:
    inc bx
    dec cx
    jnz .col

    pop si
    pop bp
    pop di

    inc si
    inc bp
    dec di
    jnz .row

    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_cursor:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov ax,0A000h
    mov es,ax

    mov ax,[mouse_x]
    inc ax
    mov [cursor_x],ax

    mov ax,[mouse_y]
    inc ax
    mov [cursor_y],ax

    mov byte [cursor_color],15
    call draw_cursor_bitmap

    mov ax,[mouse_x]
    mov [cursor_x],ax

    mov ax,[mouse_y]
    mov [cursor_y],ax

    mov byte [cursor_color],0
    call draw_cursor_bitmap

    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_cursor_bitmap:
    mov si,cursor_bits
    mov di,8
    mov bp,[cursor_y]

.row:
    push di
    push bp
    push si

    mov dl,[si]
    mov bx,[cursor_x]
    mov cx,8

.col:
    shl dl,1
    jnc .no

    cmp bx,0
    jl .no

    cmp bx,320
    jge .no

    cmp bp,0
    jl .no

    cmp bp,200
    jge .no

    mov ax,bp

    push bx
    mov bx,320
    mul bx
    pop bx

    add ax,bx
    mov di,ax

    mov al,[cursor_color]
    stosb

.no:
    inc bx
    dec cx
    jnz .col

    pop si
    pop bp
    pop di

    inc si
    inc bp
    dec di
    jnz .row

    ret

wait_vsync:
    push ax
    push dx

    mov dx,3DAh

.wait_not:
    in al,dx
    test al,8
    jnz .wait_not

.wait:
    in al,dx
    test al,8
    jz .wait

    pop dx
    pop ax
    ret

; ================================================================
; DIALOGS
; ================================================================

show_message:
    call draw_dialog

    mov ah,0
    int 16h

    ret

confirm_box:
    call draw_dialog

    puttext 56,132,0,msg_yesno

.wait:
    mov ah,0
    int 16h

    and al,0DFh

    cmp al,'Y'
    je .yes

    cmp al,'N'
    je .no

    cmp al,1Bh
    je .no

    jmp .wait

.yes:
    clc
    ret

.no:
    stc
    ret

input_box:
    call update_input_len

.key_loop:
    call draw_input_dialog

    mov ah,0
    int 16h

    mov dl,al

    cmp dl,13
    je .ok

    cmp dl,27
    je .cancel

    cmp dl,8
    je .backspace

    cmp dl,20h
    jb .key_loop

    cmp dl,7Eh
    ja .key_loop

    mov al,[input_len]
    xor ah,ah
    mov bx,ax

    cmp bx,INPUT_MAX
    jge .key_loop

    mov [input_buffer+bx],dl
    inc byte [input_len]

    mov byte [input_buffer+bx+1],0
    jmp .key_loop

.backspace:
    cmp byte [input_len],0
    je .key_loop

    dec byte [input_len]

    mov al,[input_len]
    xor ah,ah
    mov bx,ax

    mov byte [input_buffer+bx],0
    jmp .key_loop

.ok:
    mov al,[input_len]
    xor ah,ah
    mov bx,ax
    mov byte [input_buffer+bx],0
    clc
    ret

.cancel:
    stc
    ret

draw_dialog:
    mov ax,50
    mov bx,55
    mov cx,220
    mov dx,95
    call draw_button_up

    box 52,57,216,12,1

    cmp word [dlg_title],0
    je .no_title

    puttext 56,59,15,[dlg_title]

.no_title:
    mov word [dlg_y],78

    cmp word [dlg_line1],0
    je .line2

    puttext 56,[dlg_y],0,[dlg_line1]
    add word [dlg_y],12

.line2:
    cmp word [dlg_line2],0
    je .line3

    puttext 56,[dlg_y],0,[dlg_line2]
    add word [dlg_y],12

.line3:
    cmp word [dlg_line3],0
    je .line4

    puttext 56,[dlg_y],0,[dlg_line3]
    add word [dlg_y],12

.line4:
    cmp word [dlg_line4],0
    je .done

    puttext 56,[dlg_y],0,[dlg_line4]

.done:
    ret

draw_input_dialog:
    mov ax,40
    mov bx,55
    mov cx,240
    mov dx,95
    call draw_button_up

    box 42,57,236,12,1

    cmp word [dlg_title],0
    je .no_title

    puttext 46,59,15,[dlg_title]

.no_title:
    cmp word [dlg_prompt],0
    je .no_prompt

    puttext 46,78,0,[dlg_prompt]

.no_prompt:
    box 46,96,228,16,15
    frame 46,96,228,16,0

    puttext 49,100,0,input_buffer

    mov al,[input_len]
    xor ah,ah
    mov bx,8
    mul bx

    add ax,49

    mov bx,100
    mov cl,0

    mov byte [char_buffer],'_'
    mov byte [char_buffer+1],0

    mov si,char_buffer
    call draw_string

    puttext 46,122,0,input_hint
    ret

update_input_len:
    push ax
    push di

    mov di,input_buffer
    call str_end_di

    mov ax,di
    sub ax,input_buffer

    cmp ax,INPUT_MAX
    jbe .ok

    mov ax,INPUT_MAX
    mov byte [input_buffer+INPUT_MAX],0

.ok:
    mov [input_len],al

    pop di
    pop ax
    ret

show_about:
    mov [dlg_title],about_title
    mov [dlg_line1],about1
    mov [dlg_line2],about2
    mov [dlg_line3],about3
    mov word [dlg_line4],0

    call show_message
    ret

confirm_exit:
    mov [dlg_title],msg_exit_title
    mov [dlg_line1],msg_exit_text
    mov word [dlg_line2],0
    mov word [dlg_line3],0
    mov word [dlg_line4],0

    call confirm_box
    jc .no

    call exit_program

.no:
    ret

show_error:
    mov [dlg_title],msg_error_title
    mov [dlg_line1],si
    mov word [dlg_line2],0
    mov word [dlg_line3],0
    mov word [dlg_line4],0

    call show_message
    ret

show_info:
    mov [dlg_title],msg_info_title
    mov [dlg_line1],si
    mov word [dlg_line2],0
    mov word [dlg_line3],0
    mov word [dlg_line4],0

    call show_message
    ret

; ================================================================
; STRING / NUMBER HELPERS
; ================================================================

str_copy:
    push ds
    pop es

.copy:
    lodsb
    stosb
    test al,al
    jnz .copy
    ret

str_end_di:
    push ax
    push cx

    push ds
    pop es

    xor al,al
    mov cx,0FFFFh
    repne scasb
    dec di

    pop cx
    pop ax
    ret

append_string:
    mov [app_src],si
    mov [app_dst],di

    mov di,[app_dst]
    call str_end_di

    mov si,[app_src]
    call str_copy

    ret

append_char:
    mov [app_char],al
    mov [app_dst],di

    mov di,[app_dst]
    call str_end_di

    mov al,[app_char]
    stosb

    xor al,al
    stosb

    ret

str_equal:
    push si
    push di

.cmp_loop:
    mov al,[si]
    mov bl,[di]

    cmp al,bl
    jne .diff

    test al,al
    jz .same

    inc si
    inc di
    jmp .cmp_loop

.same:
    pop di
    pop si
    mov cx,1
    ret

.diff:
    pop di
    pop si
    xor cx,cx
    ret

make_short_name:
    push ax
    push cx
    push si
    push di

    push ds
    pop es

    mov di,row_buffer

.copy:
    lodsb
    test al,al
    jz .done
    stosb
    loop .copy

.done:
    mov byte [di],0

    pop di
    pop si
    pop cx
    pop ax
    ret

format_word:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov si,di
    mov di,num_rev
    mov cx,10

    test ax,ax
    jnz .conv

    mov byte [di],'0'
    inc di
    jmp .converted

.conv:
    xor dx,dx
    div cx

    add dl,'0'
    mov [di],dl
    inc di

    test ax,ax
    jnz .conv

.converted:
    mov cx,di
    sub cx,num_rev

    mov di,num_rev
    add di,cx
    dec di

.rev:
    mov al,[di]
    mov [si],al
    inc si
    dec di
    loop .rev

    mov byte [si],0

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

format_dword:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov si,di
    mov di,num_rev

    or ax,ax
    jnz .conv

    or dx,dx
    jnz .conv

    mov byte [di],'0'
    inc di
    jmp .converted

.conv:
    call div32_by_10

    add bl,'0'
    mov [di],bl
    inc di

    or ax,ax
    jnz .conv

    or dx,dx
    jnz .conv

.converted:
    mov cx,di
    sub cx,num_rev

    mov di,num_rev
    add di,cx
    dec di

.rev:
    mov al,[di]
    mov [si],al
    inc si
    dec di
    loop .rev

    mov byte [si],0

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

div32_by_10:
    mov [div32_low],ax

    mov ax,dx
    xor dx,dx
    mov cx,10
    div cx

    mov [div32_high],ax

    mov ax,[div32_low]
    div cx

    mov bx,dx
    mov dx,[div32_high]

    ret

;MACROS!

macro box x,y,w,h,c
{
    mov ax,x
    mov bx,y
    mov cx,w
    mov dx,h
    mov byte [rect_color],c
    call draw_rect
}

macro frame x,y,w,h,c
{
    mov ax,x
    mov bx,y
    mov cx,w
    mov dx,h
    mov byte [rect_color],c
    call draw_border
}

macro puttext x,y,c,s
{
    mov ax,x
    mov bx,y
    mov cl,c
    mov si,s
    call draw_string
}

macro menuitem x,y,i,s
{
    mov ax,x
    mov bx,y
    mov cx,i
    mov dx,s
    call draw_menu_item
}

; ================================================================
; DATA
; ================================================================

rect_color          db 0

rect_x              dw 0
rect_y              dw 0
rect_w              dw 0
rect_h              dw 0

brd_x               dw 0
brd_y               dw 0
brd_w               dw 0
brd_h               dw 0

btn_x               dw 0
btn_y               dw 0
btn_w               dw 0
btn_h               dw 0

pane_x              dw 0
pane_y              dw 0
pane_w              dw 0
pane_h              dw 0

str_x               dw 0
str_y               dw 0
str_c               db 0

char_code           db 0
cursor_x            dw 0
cursor_y            dw 0
cursor_color        db 0

mouse_ok            db 0
mouse_x             dw 160
mouse_y             dw 100
prev_buttons        dw 0

menu_open           db 0
menu_selected       db 0
selected_menu_item  dw 0FFFFh

menu_x              dw 0
menu_w              dw 0
menu_count          dw 0

mi_x                dw 0
mi_y                dw 0
mi_index            dw 0
mi_str              dw 0

menu_text_color     db 0

current_drive       db 'C'
current_path        rb 128
path_display        rb 32
dir_buffer          rb 64
is_root             db 0

tree_x              dw 0
tree_w              dw 0
file_x              dw 0
file_w              dw 0

show_tree           db 1
show_hidden         db 0
sort_mode           db 0
active_pane         db 0

file_list           rb MAX_FILES * ENTRY_SIZE
file_count          dw 0
file_start          dw 0
file_selected       dw 0
file_scroll         dw 0

tree_list           rb MAX_TREE * TREE_SIZE
tree_count          dw 0
tree_selected       dw 0
tree_scroll         dw 0

draw_index          dw 0
draw_y              dw 0
entry_ptr           dw 0
row_color           db 0

row_buffer          rb 32
size_str            rb 16
count_str           rb 8
char_buffer         rb 4

tmp_src             dw 0
tmp_dst             dw 0

sort_i              dw 0
cmp_i               dw 0
cmp_j               dw 0

dta_buffer          rb 128
font_data           rb 2048

dotdot_name         db '..',0
dotdot_path         db '..',0
root_path           db '\',0
star_dot_star       db '*.*',0

title_str           db 'File Manager',0

menu_file           db 'File',0
menu_options        db 'Options',0
menu_view           db 'View',0
menu_help           db 'Help',0

file_open           db 'Open',0
file_copy           db 'Copy',0
file_move           db 'Move',0
file_paste          db 'Paste',0
file_delete         db 'Delete',0
file_rename         db 'Rename',0
file_createdir      db 'Create Directory',0
file_props          db 'Properties',0
file_exit           db 'Exit',0

opt_hidden          db 'Show Hidden',0
opt_tree            db 'Show Tree Pane',0

view_refresh        db 'Refresh',0
view_sort_name      db 'Sort by Name',0
view_sort_size      db 'Sort by Size',0

help_about          db 'About',0

tb_open             db 'Open',0
tb_new              db 'New',0
tb_del              db 'Del',0
tb_ren              db 'Ren',0
tb_copy             db 'Copy',0
tb_move             db 'Move',0
tb_paste            db 'Paste',0

drive_label         db 'Drive:',0
drv_x               dw 0
drv_char            db 0

tree_title          db 'Folders',0
name_title          db 'Name',0
size_title          db 'Size',0
dir_str             db '<DIR>',0
no_files            db 'No files',0

status_files        db 'Files:',0
sel_label           db 'Sel:',0

star_str            db '*',0

msg_error_title     db 'Error',0
msg_info_title      db 'Information',0
msg_confirm_title   db 'Confirm',0
msg_props_title     db 'Properties',0
msg_rename_title    db 'Rename',0
msg_mkdir_title     db 'Create Directory',0
msg_exit_title      db 'Exit',0

about_title         db 'About',0
about1              db 'Windows 3.x style File Manager',0
about2              db '16-bit real mode DOS',0
about3              db 'FASM 8086 compatible',0

msg_exit_text       db 'Exit File Manager?',0
msg_yesno           db 'Y/N',0
msg_delete_confirm  db 'Delete this item?',0
msg_new_name        db 'New name:',0
msg_mkdir_prompt    db 'Directory name:',0
msg_cannot_open     db 'Cannot open',0
msg_delete_failed   db 'Delete failed',0
msg_rename_failed   db 'Rename failed',0
msg_mkdir_failed    db 'Create directory failed',0
msg_paste_failed    db 'Paste failed',0
msg_dir_not_supported db 'Only files can be copied/moved',0
msg_clipboard_empty db 'Clipboard is empty',0
msg_same_path       db 'Source and destination are the same',0

msg_name_label      db 'Name: ',0
msg_size_label      db 'Size: ',0
msg_attr_label      db 'Attr: ',0
msg_size_dir        db '<DIR>',0

input_hint          db 'Enter OK   Esc Cancel',0

dlg_title           dw 0
dlg_prompt          dw 0
dlg_line1           dw 0
dlg_line2           dw 0
dlg_line3           dw 0
dlg_line4           dw 0
dlg_y               dw 0

input_buffer        rb 32
input_len           db 0

prop_line1          rb 40
prop_line2          rb 40
prop_line3          rb 40

path_buffer         rb 128
old_path            rb 128
new_path            rb 128
dest_path           rb 128
temp_name           rb 16
del_attr            db 0

clip_count          dw 0
clip_op             db 0
clip_name           rb 16
clip_path           rb 128

copy_src            dw 0
copy_dst            dw 0
src_handle          dw 0
dst_handle          dw 0
copy_buffer         rb COPY_BUF_SIZE

app_src             dw 0
app_dst             dw 0
app_char            db 0

num_rev             rb 16
div32_low           dw 0
div32_high          dw 0

cursor_bits:
    db 128,192,224,240,248,252,254,255
