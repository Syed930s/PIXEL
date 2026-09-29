

format MZ
stack 2000h



; File system limits
MAX_FILES       = 256           ; Maximum number of files in list
MAX_TREE        = 64            ; Maximum number of directories in tree

; Entry sizes
ENTRY_SIZE      = 24            ; Size of file entry in bytes
TREE_SIZE       = 16            ; Size of tree entry in bytes

; File attribute offsets
F_NAME          = 0             ; Filename offset in entry
F_ATTR          = 13            ; File attributes offset
F_SIZE_LO       = 14            ; Low word of file size
F_SIZE_HI       = 16            ; High word of file size

; Display constants
VISIBLE         = 10            ; Visible rows count
ROW_H           = 10            ; Row height in pixels

; UI Layout - Menu region
MENU_TOP        = 26            ; Y position of menu dropdown
TITLE_H         = 12            ; Title bar height
MENU_Y          = 12            ; Menu bar Y position
MENU_H          = 14            ; Menu bar height

; UI Layout - Toolbar region
TOOLBAR_Y       = 27            ; Toolbar Y position
TOOLBAR_H       = 16            ; Toolbar height

; UI Layout - Drive bar region
DRIVE_Y         = 44            ; Drive bar Y position
DRIVE_H         = 14            ; Drive bar height

; UI Layout - Content region
CONTENT_Y       = 58            ; Content area Y position
PANE_Y          = 60            ; Pane border Y position
PANE_H          = 122           ; Pane height
HEADER_Y        = 63            ; Column headers Y position
LIST_TOP        = 74            ; List content starts here

; UI Layout - Status bar
STATUS_Y        = 184           ; Status bar Y position
STATUS_H        = 16            ; Status bar height

; Input/Buffer sizes
INPUT_MAX       = 20            ; Maximum input length
COPY_BUF_SIZE   = 2048          ; Copy buffer size in bytes



segment main
entry main:start


start:
    ; Initialize segment registers
    mov ax,cs
    mov ds,ax
    mov es,ax
    cld

    ; Set video mode to 320x200 256-color (Mode 13h)
    mov ax,13h
    int 10h

    ; Initialize subsystems
    call init_font                ; Load font data
    call init_mouse               ; Initialize mouse driver
    call update_path              ; Get current directory
    call refresh_all              ; Build file/tree lists

main_loop:
    ; Main event loop
    call update_layout            ; Update pane positions
    call render_all               ; Draw all UI elements
    call process_input            ; Handle keyboard/mouse
    call wait_vsync               ; Wait for vertical sync
    jmp main_loop

exit_program:
    ; Restore text mode and exit
    mov ax,3
    int 10h

    mov ax,4C00h
    int 21h


init_mouse:
    push es

    ; Check if mouse driver is installed at BIOS data area
    xor ax,ax
    mov es,ax
    mov ax,[es:0CCh]
    mov bx,[es:0CEh]
    or ax,bx

    pop es
    jz .no_mouse

    ; Reset mouse and check return value
    xor ax,ax
    int 33h
    test ax,ax
    jz .no_mouse

    ; Show mouse cursor
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

    ; Get 8x8 font pointer from INT 10h
    mov ax,1130h
    mov bh,0
    int 10h

    ; Copy font from ES:BP to our buffer
    push ds

    mov ax,es
    mov ds,ax
    mov si,bp

    mov ax,cs
    mov es,ax
    mov di,font_data
    mov cx,2048                   ; 256 chars * 8 bytes each
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

    ; Tree visible: split screen
    mov word [tree_x],2
    mov word [tree_w],84
    mov word [file_x],88
    mov word [file_w],230
    ret

.no_tree:
    ; Tree hidden: file pane uses full width
    mov word [tree_x],0
    mov word [tree_w],0
    mov word [file_x],2
    mov word [file_w],316
    ret

update_path:
    push ax
    push bx
    push cx
    push si
    push di

    ; Get current drive (INT 21h AH=19h)
    mov ah,19h
    int 21h
    add al,'A'
    mov [current_drive],al

    ; Get current directory (INT 21h AH=47h)
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

    ; Build full path string: "X:\PATH"
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
    ; Create truncated display version (max 24 chars)
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

    ; Copy current path
    mov si,current_path
    mov di,[tmp_dst]
    call str_copy

    dec di

    ; Add separator if needed
    cmp di,[tmp_dst]
    je .append

    cmp byte [di-1],'\'
    je .append

    mov al,'\'
    stosb

.append:
    ; Append relative path
    mov si,[tmp_src]
    call str_copy
    ret


refresh_all:
    call refresh_tree
    call refresh_files

    ; Reset selection and scroll positions
    mov word [file_selected],0
    mov word [file_scroll],0
    mov word [tree_selected],0
    mov word [tree_scroll],0

    ret
refresh_files:
    ; Set DTA (Disk Transfer Area)
    mov ah,1Ah
    mov dx,dta_buffer
    int 21h

    mov word [file_count],0
    mov word [file_start],0

    ; Add ".." entry if not at root
    cmp byte [is_root],1
    je .no_parent

    mov si,dotdot_name
    mov bl,10h                    ; Directory attribute
    xor cx,cx                     ; Size = 0
    xor dx,dx
    call add_file_entry

    mov word [file_start],1

.no_parent:
    ; Find first file matching *.*
    mov ah,4Eh
    mov cx,37h                    ; All attributes except volume label
    mov dx,star_dot_star
    int 21h
    jc .done

.next:
    mov al,[dta_buffer+15h]       ; File attributes

    ; Skip volume labels
    test al,08h
    jnz .find_next

    ; Skip entries starting with '.'
    cmp byte [dta_buffer+1Eh],'.'
    je .find_next

    ; Filter hidden/system files if not showing hidden
    cmp byte [show_hidden],0
    jne .include

    test al,06h
    jnz .find_next

.include:
    ; Add file entry
    mov si,dta_buffer+1Eh         ; Filename
    mov bl,al                     ; Attributes
    mov cx,[dta_buffer+1Ah]       ; Size low
    mov dx,[dta_buffer+1Ch]       ; Size high
    call add_file_entry

.find_next:
    mov ah,4Fh
    int 21h
    jnc .next

.done:
    call sort_file_list
    ret

refresh_tree:
    ; Set DTA
    mov ah,1Ah
    mov dx,dta_buffer
    int 21h

    mov word [tree_count],0

    ; Add ".." entry if not at root
    cmp byte [is_root],1
    je .no_parent

    mov si,dotdot_name
    call add_tree_entry

.no_parent:
    ; Find first directory
    mov ah,4Eh
    mov cx,37h
    mov dx,star_dot_star
    int 21h
    jc .done

.next:
    mov al,[dta_buffer+15h]

    ; Only include directories
    test al,10h
    jz .find_next

    ; Skip volume labels
    test al,08h
    jnz .find_next

    ; Filter hidden/system if needed
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

; ----------------------------------------------------------------------------
; add_file_entry - Add a file to the file list
; Input: SI=name, BL=attributes, CX:DX=size
; ----------------------------------------------------------------------------
add_file_entry:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    cmp word [file_count],MAX_FILES
    jge .done

    ; Calculate entry offset
    mov ax,[file_count]
    mov bx,ENTRY_SIZE
    mul bx

    mov di,file_list
    add di,ax

    ; Copy filename (13 chars max)
    call copy_name13

    ; Store attributes and size
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

    ; Calculate entry offset
    mov ax,[tree_count]
    mov bx,TREE_SIZE
    mul bx

    mov di,tree_list
    add di,ax

    ; Copy name
    call copy_name13

    ; Clear padding bytes
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

    ; Get pointers to both entries
    mov bx,[cmp_i]
    call get_file_entry
    mov di,si

    mov bx,[cmp_j]
    call get_file_entry

    ; Compare directory vs file (directories first)
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
    ; Check sort mode
    cmp byte [sort_mode],0
    je .name

    cmp byte [sort_mode],1
    je .size

    clc
    jmp .done

.name:
    ; Compare by name (lexicographic)
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
    ; Compare by size (larger first)
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

    ; Get pointers to both entries
    mov bx,[cmp_i]
    call get_file_entry
    mov di,si

    mov bx,[cmp_j]
    call get_file_entry

    ; Swap ENTRY_SIZE/2 words
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

process_input:
    ; Check for keyboard input
    mov ah,1
    int 16h
    jz .mouse

    mov ah,0
    int 16h
    call handle_keyboard

.mouse:
    ; Process mouse if available
    cmp byte [mouse_ok],0
    je .done

    ; Get mouse position and buttons
    mov ax,3
    int 33h

    shr cx,1                      ; Scale X coordinate

    mov [mouse_x],cx
    mov [mouse_y],dx

    ; Handle left button press/release
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
    ; If menu is open, handle menu navigation
    cmp byte [menu_open],0
    je .no_menu

    cmp al,1Bh                    ; Escape closes menu
    je .close_menu

    cmp al,0Dh                    ; Enter executes menu item
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
    ; Handle scan codes (extended keys)
    test al,al
    jnz .ascii

    cmp ah,48h                    ; Up arrow
    je .up

    cmp ah,50h                    ; Down arrow
    je .down

    cmp ah,3Fh                    ; F5
    je .f5

    cmp ah,41h                    ; F7
    je .f7

    cmp ah,53h                    ; Delete
    je .del

    ret

.ascii:
    ; Handle ASCII characters
    cmp al,1Bh                    ; Escape
    je .esc

    cmp al,0Dh                    ; Enter
    je .enter

    cmp al,08h                    ; Backspace
    je .backspace

    cmp al,09h                    ; Tab
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
    ; Switch active pane
    mov al,[active_pane]
    xor al,1
    mov [active_pane],al
    ret

.done:
    ret


handle_mouse_down:
    mov ax,[mouse_y]

    ; Check title bar
    cmp ax,TITLE_H
    jl .done

    ; Check menu bar
    cmp ax,MENU_TOP
    jl .menu_bar

    ; If menu already open, check for click outside
    cmp byte [menu_open],0
    jne .menu_click_outside

    ; Check toolbar
    cmp ax,DRIVE_Y
    jl .toolbar

    ; Check drive bar
    cmp ax,CONTENT_Y
    jl .drive

    ; Check content area
    cmp ax,STATUS_Y
    jl .content

    ret

.menu_bar:
    ; Determine which menu was clicked
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

    ; Check if click is within menu bounds
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

    ; Calculate which menu item was clicked
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

; ----------------------------------------------------------------------------
; handle_drive_click - Handle drive button clicks (A-D)
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; handle_content_click - Handle clicks in file/tree pane area
; ----------------------------------------------------------------------------
handle_content_click:
    ; Check if clicking in tree pane
    cmp byte [show_tree],0
    je .file_pane

    mov ax,[mouse_x]
    cmp ax,[tree_x]
    jl .file_pane

    mov bx,[tree_x]
    add bx,[tree_w]
    cmp ax,bx
    jge .file_pane

    ; Tree pane click
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
    ; File pane click
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

; ============================================================================
; SELECTION AND NAVIGATION MODULE
; ============================================================================

; ----------------------------------------------------------------------------
; set_file_selection - Set file selection and ensure visibility
; Input: BX=index
; ----------------------------------------------------------------------------
set_file_selection:
    cmp bx,[file_count]
    jge .done

    mov [file_selected],bx
    call ensure_file_visible

.done:
    ret

; ----------------------------------------------------------------------------
; set_tree_selection - Set tree selection and ensure visibility
; Input: BX=index
; ----------------------------------------------------------------------------
set_tree_selection:
    cmp bx,[tree_count]
    jge .done

    mov [tree_selected],bx
    call ensure_tree_visible

.done:
    ret

; ----------------------------------------------------------------------------
; select_file_next - Move selection to next file
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; select_file_prev - Move selection to previous file
; ----------------------------------------------------------------------------
select_file_prev:
    mov bx,[file_selected]
    cmp bx,0
    jle .done

    dec bx
    mov [file_selected],bx
    call ensure_file_visible

.done:
    ret

; ----------------------------------------------------------------------------
; select_tree_next - Move selection to next directory
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; select_tree_prev - Move selection to previous directory
; ----------------------------------------------------------------------------
select_tree_prev:
    mov bx,[tree_selected]
    cmp bx,0
    jle .done

    dec bx
    mov [tree_selected],bx
    call ensure_tree_visible

.done:
    ret

; ----------------------------------------------------------------------------
; ensure_file_visible - Scroll to keep selected file visible
; ----------------------------------------------------------------------------
ensure_file_visible:
    mov bx,[file_selected]

    mov ax,[file_scroll]
    cmp bx,ax
    jl .up

    add ax,VISIBLE
    cmp bx,ax
    jl .done

    mov ax,bx
    sub ax,VISIBLE-1
    mov [file_scroll],ax
    ret

.up:
    mov ax,bx
    mov [file_scroll],ax

.done:
    ret

; ----------------------------------------------------------------------------
; ensure_tree_visible - Scroll to keep selected tree item visible
; ----------------------------------------------------------------------------
ensure_tree_visible:
    mov bx,[tree_selected]

    mov ax,[tree_scroll]
    cmp bx,ax
    jl .up

    add ax,VISIBLE
    cmp bx,ax
    jl .done

    mov ax,bx
    sub ax,VISIBLE-1
    mov [tree_scroll],ax
    ret

.up:
    mov ax,bx
    mov [tree_scroll],ax

.done:
    ret

; ----------------------------------------------------------------------------
; open_active - Open selected item in active pane
; ----------------------------------------------------------------------------
open_active:
    cmp byte [active_pane],0
    je .file

    call open_selected_tree
    ret

.file:
    call open_selected_file
    ret

; ----------------------------------------------------------------------------
; open_selected_file - Open or enter selected file/directory
; ----------------------------------------------------------------------------
open_selected_file:
    cmp word [file_count],0
    je .done

    mov bx,[file_selected]
    call get_file_entry

    ; Check if directory
    mov al,[si+F_ATTR]
    test al,10h
    jz .open_file

    ; Get directory name
    push ds
    pop es

    mov di,path_buffer
    call build_full_path

    ; Change to directory
    mov dx,path_buffer
    call change_dir
    ret

.open_file:
    ; Get full path to file
    push ds
    pop es

    mov di,path_buffer
    mov si,[si+F_NAME]
    call build_full_path

    ; Try to execute file (INT 21h AH=4Bh)
    mov dx,path_buffer
    mov ax,4B00h
    int 21h
    jc .error

    ret

.error:
    mov si,msg_cannot_open
    call show_error

.done:
    ret

; ----------------------------------------------------------------------------
; open_selected_tree - Enter selected directory from tree
; ----------------------------------------------------------------------------
open_selected_tree:
    cmp word [tree_count],0
    je .done

    mov bx,[tree_selected]
    call get_tree_entry

    ; Get directory name
    push ds
    pop es

    mov di,path_buffer
    call build_full_path

    ; Change to directory
    mov dx,path_buffer
    call change_dir

.done:
    ret

; ----------------------------------------------------------------------------
; get_selected_file_entry - Get pointer to currently selected file
; Output: SI=pointer to entry
; ----------------------------------------------------------------------------
get_selected_file_entry:
    mov bx,[file_selected]
    call get_file_entry
    ret

; ============================================================================
; MENU SYSTEM MODULE
; ============================================================================

; ----------------------------------------------------------------------------
; open_menu - Open a dropdown menu
; Input: AL=menu index (0=File, 1=Options, 2=View, 3=Help)
; ----------------------------------------------------------------------------
open_menu:
    mov [menu_selected],al
    mov byte [menu_open],1
    mov word [selected_menu_item],0FFFFh
    ret

; ----------------------------------------------------------------------------
; close_menu - Close any open menu
; ----------------------------------------------------------------------------
close_menu:
    mov byte [menu_open],0
    mov byte [menu_selected],0
    ret

; ----------------------------------------------------------------------------
; setup_menu - Configure menu items based on selected menu
; ----------------------------------------------------------------------------
setup_menu:
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
    mov word [menu_x],2
    mov word [menu_w],120
    mov word [menu_count],9
    ret

.options:
    mov word [menu_x],74
    mov word [menu_w],140
    mov word [menu_count],2
    ret

.view:
    mov word [menu_x],106
    mov word [menu_w],140
    mov word [menu_count],3
    ret

.help:
    mov word [menu_x],138
    mov word [menu_w],100
    mov word [menu_count],1
    ret

; ----------------------------------------------------------------------------
; execute_menu_item - Execute the currently selected menu item
; ----------------------------------------------------------------------------
execute_menu_item:
    mov al,[menu_selected]
    mov bx,[selected_menu_item]

    cmp al,0
    je .file_menu

    cmp al,1
    je .options_menu

    cmp al,2
    je .view_menu

    cmp al,3
    je .help_menu

    ret

.file_menu:
    cmp bx,0
    je .open

    cmp bx,1
    je .copy

    cmp bx,2
    je .move

    cmp bx,3
    je .paste

    cmp bx,4
    je .delete

    cmp bx,5
    je .rename

    cmp bx,6
    je .createdir

    cmp bx,7
    je .props

    cmp bx,8
    je .exit

    ret

.options_menu:
    cmp bx,0
    je .toggle_hidden

    cmp bx,1
    je .toggle_tree

    ret

.view_menu:
    cmp bx,0
    je .refresh

    cmp bx,1
    je .sort_name

    cmp bx,2
    je .sort_size

    ret

.help_menu:
    cmp bx,0
    je .about

    ret

.open:
    call open_selected_file
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

.delete:
    call delete_selected
    ret

.rename:
    call rename_selected
    ret

.createdir:
    call create_directory
    ret

.props:
    call show_properties
    ret

.exit:
    call confirm_exit
    ret

.toggle_hidden:
    call toggle_hidden
    ret

.toggle_tree:
    call toggle_tree
    ret

.refresh:
    call refresh_all
    ret

.sort_name:
    mov byte [sort_mode],0
    call sort_file_list
    ret

.sort_size:
    mov byte [sort_mode],1
    call sort_file_list
    ret

.about:
    call show_about
    ret

; ----------------------------------------------------------------------------
; toggle_hidden - Toggle show hidden files setting
; ----------------------------------------------------------------------------
toggle_hidden:
    mov al,[show_hidden]
    xor al,1
    mov [show_hidden],al
    call refresh_all
    ret

; ----------------------------------------------------------------------------
; toggle_tree - Toggle tree pane visibility
; ----------------------------------------------------------------------------
toggle_tree:
    mov al,[show_tree]
    xor al,1
    mov [show_tree],al
    ret

; ============================================================================
; FILE OPERATIONS MODULE
; ============================================================================

; ----------------------------------------------------------------------------
; copy_selected - Copy selected file to clipboard
; ----------------------------------------------------------------------------
copy_selected:
    cmp word [file_count],0
    je .done

    call get_selected_file_entry

    ; Check if directory (not supported for copy)
    mov al,[si+F_ATTR]
    test al,10h
    jnz .dir_not_supported

    ; Save source path
    push ds
    pop es

    mov di,clip_path
    mov si,current_path
    call str_copy

    ; Save filename
    mov di,clip_name
    mov si,[si+F_NAME]
    call copy_name13

    ; Set clipboard operation (copy=0)
    mov word [clip_count],1
    mov byte [clip_op],0

    ret

.dir_not_supported:
    mov si,msg_dir_not_supported
    call show_error

.done:
    ret

; ----------------------------------------------------------------------------
; move_selected - Move selected file to clipboard
; ----------------------------------------------------------------------------
move_selected:
    cmp word [file_count],0
    je .done

    call get_selected_file_entry

    ; Check if directory
    mov al,[si+F_ATTR]
    test al,10h
    jnz .dir_not_supported

    ; Save source path
    push ds
    pop es

    mov di,clip_path
    mov si,current_path
    call str_copy

    ; Save filename
    mov di,clip_name
    mov si,[si+F_NAME]
    call copy_name13

    ; Set clipboard operation (move=1)
    mov word [clip_count],1
    mov byte [clip_op],1

    ret

.dir_not_supported:
    mov si,msg_dir_not_supported
    call show_error

.done:
    ret

; ----------------------------------------------------------------------------
; paste_clipboard - Paste file from clipboard to current directory
; ----------------------------------------------------------------------------
paste_clipboard:
    cmp word [clip_count],0
    je .clipboard_empty

    ; Build destination path
    push ds
    pop es

    mov di,dest_path
    mov si,current_path
    call str_copy

    ; Append filename from clipboard
    dec di
    cmp byte [di-1],'\'
    je .append_name

    mov al,'\'
    stosb

.append_name:
    mov si,clip_name
    call str_copy

    ; Check if source and destination are the same
    mov si,clip_path
    mov di,current_path
    call str_equal
    jz .same_path

    ; Perform copy or move based on clipboard operation
    cmp byte [clip_op],0
    je .do_copy

    ; Move operation
    mov si,dest_path
    mov di,temp_name
    call copy_name13_from_entry

    mov si,clip_path
    mov di,old_path
    call append_string

    mov si,dest_path
    mov di,new_path
    call append_string

    call move_file
    jc .paste_failed

    jmp .success

.do_copy:
    mov si,clip_path
    mov di,old_path
    call append_string

    mov si,dest_path
    mov di,new_path
    call append_string

    call copy_file
    jc .paste_failed

.success:
    call refresh_all
    ret

.clipboard_empty:
    mov si,msg_clipboard_empty
    call show_error
    ret

.same_path:
    mov si,msg_same_path
    call show_error
    ret

.paste_failed:
    mov si,msg_paste_failed
    call show_error
    ret

; ----------------------------------------------------------------------------
; delete_selected - Delete selected file or directory
; ----------------------------------------------------------------------------
delete_selected:
    cmp word [file_count],0
    je .done

    call get_selected_file_entry

    ; Confirm deletion
    mov ax,msg_confirm_title
    mov bx,msg_delete_confirm
    call confirm_box
    cmp al,0
    je .done

    ; Get full path
    push ds
    pop es

    mov di,path_buffer
    call build_full_path

    ; Check if directory
    mov al,[si+F_ATTR]
    test al,10h
    jnz .delete_dir

    ; Delete file (INT 21h AH=11h requires FCB, use 41h instead)
    mov dx,path_buffer
    mov ah,41h
    int 21h
    jc .delete_failed

    jmp .success

.delete_dir:
    ; Remove directory (must be empty)
    mov dx,path_buffer
    mov ah,3Ah
    int 21h
    jc .delete_failed

.success:
    call refresh_all
    ret

.delete_failed:
    mov si,msg_delete_failed
    call show_error

.done:
    ret

; ----------------------------------------------------------------------------
; rename_selected - Rename selected file or directory
; ----------------------------------------------------------------------------
rename_selected:
    cmp word [file_count],0
    je .done

    call get_selected_file_entry

    ; Prompt for new name
    mov ax,msg_rename_title
    mov bx,msg_new_name
    mov cx,13
    mov dx,input_buffer
    call input_box

    test al,al
    jz .done

    ; Validate input
    cmp byte [input_len],0
    je .done

    ; Build old and new paths
    push ds
    pop es

    mov di,old_path
    call build_full_path

    ; Build new path with new name
    mov di,new_path
    mov si,current_path
    call str_copy

    dec di
    cmp byte [di-1],'\'
    je .append_new_name

    mov al,'\'
    stosb

.append_new_name:
    mov si,input_buffer
    call str_copy

    ; Rename file/directory (INT 21h AH=56h)
    mov dx,old_path
    mov si,new_path
    mov ax,5600h
    int 21h
    jc .rename_failed

    call refresh_all
    ret

.rename_failed:
    mov si,msg_rename_failed
    call show_error

.done:
    ret

; ----------------------------------------------------------------------------
; create_directory - Create new directory
; ----------------------------------------------------------------------------
create_directory:
    ; Prompt for directory name
    mov ax,msg_mkdir_title
    mov bx,msg_mkdir_prompt
    mov cx,13
    mov dx,input_buffer
    call input_box

    test al,al
    jz .done

    ; Validate input
    cmp byte [input_len],0
    je .done

    ; Build full path
    push ds
    pop es

    mov di,path_buffer
    mov si,current_path
    call str_copy

    dec di
    cmp byte [di-1],'\'
    je .append_dir_name

    mov al,'\'
    stosb

.append_dir_name:
    mov si,input_buffer
    call str_copy

    ; Create directory (INT 21h AH=39h)
    mov dx,path_buffer
    mov ah,39h
    int 21h
    jc .mkdir_failed

    call refresh_all
    ret

.mkdir_failed:
    mov si,msg_mkdir_failed
    call show_error

.done:
    ret

; ----------------------------------------------------------------------------
; show_properties - Show properties dialog for selected file
; ----------------------------------------------------------------------------
show_properties:
    cmp word [file_count],0
    je .done

    call get_selected_file_entry

    ; Format file name
    push ds
    pop es

    mov di,prop_line1
    mov si,msg_name_label
    call append_string

    mov si,[si+F_NAME]
    call make_short_name
    mov si,app_dst
    call append_string

    ; Format file size
    mov di,prop_line2
    mov si,msg_size_label
    call append_string

    mov al,[si+F_ATTR]
    test al,10h
    jnz .is_dir

    ; Format numeric size
    mov ax,[si+F_SIZE_LO]
    mov dx,[si+F_SIZE_HI]
    mov di,size_str
    call format_dword
    mov si,size_str
    call append_string
    jmp .after_size

.is_dir:
    mov si,msg_size_dir
    call append_string

.after_size:
    ; Format attributes
    mov di,prop_line3
    mov si,msg_attr_label
    call append_string

    movzx ax,byte [si+F_ATTR]
    mov di,char_buffer
    call format_word
    mov si,char_buffer
    call append_string

    ; Show properties dialog
    mov ax,msg_props_title
    mov bx,prop_line1
    mov cx,prop_line2
    mov dx,prop_line3
    call show_message

.done:
    ret

; ----------------------------------------------------------------------------
; copy_name13_from_entry - Copy name from file entry to buffer
; Input: SI=entry pointer, DI=destination
; ----------------------------------------------------------------------------
copy_name13_from_entry:
    push cx
    push si
    push di

    mov cx,13

.copy:
    mov al,[si]
    test al,al
    jz .fill
    stosb
    inc si
    loop .copy
    jmp .done

.fill:
    stosb
    dec cx
    jz .done

    xor al,al
    rep stosb

.done:
    pop di
    pop si
    pop cx
    ret

; ----------------------------------------------------------------------------
; copy_file - Copy file from old_path to new_path
; ----------------------------------------------------------------------------
copy_file:
    push ds
    push es

    ; Open source file
    mov dx,old_path
    mov ax,3D00h                  ; Open for read
    int 21h
    jc .error

    mov [src_handle],ax

    ; Create destination file
    mov dx,new_path
    mov ah,3Ch
    xor cx,cx                     ; Normal file
    int 21h
    jc .close_src

    mov [dst_handle],ax

    ; Copy in chunks
.copy_loop:
    mov bx,[src_handle]
    mov dx,copy_buffer
    mov cx,COPY_BUF_SIZE
    mov ah,3Fh
    int 21h
    jc .close_dst

    test ax,ax
    jz .close_dst                 ; EOF

    mov cx,ax                     ; Bytes read
    mov bx,[dst_handle]
    mov dx,copy_buffer
    mov ah,40h
    int 21h
    jc .close_dst

    cmp ax,cx                     ; Verify all bytes written
    jne .close_dst

    jmp .copy_loop

.close_dst:
    mov bx,[dst_handle]
    mov ah,3Eh
    int 21h

.close_src:
    mov bx,[src_handle]
    mov ah,3Eh
    int 21h

    pop es
    pop ds
    ret

.error:
    pop es
    pop ds
    stc
    ret

; ----------------------------------------------------------------------------
; move_file - Move/rename file from old_path to new_path
; ----------------------------------------------------------------------------
move_file:
    mov dx,old_path
    mov si,new_path
    mov ax,5600h
    int 21h
    ret

; ============================================================================
; RENDERING MODULE
; ============================================================================

; ----------------------------------------------------------------------------
; render_all - Draw all UI components
; ----------------------------------------------------------------------------
render_all:
    call draw_title_bar
    call draw_menu_bar
    call draw_toolbar
    call draw_drive_bar
    call draw_content
    call draw_status_bar
    call draw_active_menu
    call draw_cursor
    ret

; ----------------------------------------------------------------------------
; draw_title_bar - Draw top title bar
; ----------------------------------------------------------------------------
draw_title_bar:
    box 0,0,320,TITLE_H,1         ; Blue background
    puttext 2,2,15,title_str
    ret

; ----------------------------------------------------------------------------
; draw_menu_bar - Draw menu bar (File, Options, View, Help)
; ----------------------------------------------------------------------------
draw_menu_bar:
    box 0,TITLE_H,320,MENU_H,7    ; White background

    puttext 2,MENU_Y,0,menu_file
    puttext 34,MENU_Y,0,menu_options
    puttext 74,MENU_Y,0,menu_view
    puttext 106,MENU_Y,0,menu_help

    ; Highlight active menu
    cmp byte [menu_open],0
    je .done

    movzx ax,byte [menu_selected]
    mov bx,32
    mul bx
    add ax,2

    cmp byte [menu_selected],0
    je .file

    cmp byte [menu_selected],1
    je .options

    cmp byte [menu_selected],2
    je .view

    cmp byte [menu_selected],3
    je .help

    ret

.file:
    box ax,MENU_Y,30,MENU_H,0     ; Black highlight
    ret

.options:
    box ax,MENU_Y,30,MENU_H,0
    ret

.view:
    box ax,MENU_Y,30,MENU_H,0
    ret

.help:
    box ax,MENU_Y,30,MENU_H,0

.done:
    ret

; ----------------------------------------------------------------------------
; draw_toolbar - Draw toolbar buttons
; ----------------------------------------------------------------------------
draw_toolbar:
    box 0,TOOLBAR_Y,320,TOOLBAR_H,7

    ; Draw buttons
    draw_button_up 2,TOOLBAR_Y+1,tb_open
    draw_button_up 38,TOOLBAR_Y+1,tb_new
    draw_button_up 70,TOOLBAR_Y+1,tb_del
    draw_button_up 102,TOOLBAR_Y+1,tb_ren
    draw_button_up 136,TOOLBAR_Y+1,tb_copy
    draw_button_up 174,TOOLBAR_Y+1,tb_move
    draw_button_up 214,TOOLBAR_Y+1,tb_paste

    ret

; ----------------------------------------------------------------------------
; draw_drive_bar - Draw drive selection buttons
; ----------------------------------------------------------------------------
draw_drive_bar:
    box 0,DRIVE_Y,320,DRIVE_H,7

    puttext 2,DRIVE_Y+2,0,drive_label

    ; Draw drive buttons A-D
    mov byte [drv_char],'A'
    mov word [drv_x],40

.draw_drives:
    call draw_drive_button

    inc byte [drv_char]
    add word [drv_x],16

    cmp byte [drv_char],'E'
    jl .draw_drives

    ret

; ----------------------------------------------------------------------------
; draw_drive_button - Draw single drive button
; ----------------------------------------------------------------------------
draw_drive_button:
    push ax
    push bx
    push cx

    mov ax,[drv_x]
    mov bx,DRIVE_Y+1
    mov cx,14

    ; Check if this is current drive
    mov dl,[current_drive]
    cmp dl,[drv_char]
    jne .normal

    ; Active drive: sunken button
    frame ax,bx,cx,12,15
    box ax+1,bx+1,cx-2,10,0
    mov byte [rect_color],7
    jmp .draw_char

.normal:
    ; Inactive drive: raised button
    frame ax,bx,cx,12,0
    box ax+1,bx+1,cx-2,10,15
    mov byte [rect_color],0

.draw_char:
    mov [brd_x],ax
    mov [brd_y],bx
    mov [brd_w],cx
    mov [brd_h],12

    movzx ax,byte [drv_char]
    mov [app_char],al

    mov si,star_str
    call draw_string

    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; draw_content - Draw main content area (tree and file panes)
; ----------------------------------------------------------------------------
draw_content:
    ; Draw tree pane if visible
    cmp byte [show_tree],0
    je .skip_tree

    frame [tree_x],[pane_y],[tree_w],[pane_h],0
    box [tree_x]+1,[pane_y]+1,[tree_w]-2,[pane_h]-2,7

    puttext [tree_x]+2,HEADER_Y,0,tree_title
    call draw_tree_list

.skip_tree:
    ; Draw file pane
    frame [file_x],[pane_y],[file_w],[pane_h],0
    box [file_x]+1,[pane_y]+1,[file_w]-2,[pane_h]-2,7

    ; Draw column headers
    puttext [file_x]+2,HEADER_Y,0,name_title
    puttext [file_x]+150,HEADER_Y,0,size_title

    call draw_file_list

    ret

; ----------------------------------------------------------------------------
; draw_tree_list - Draw directory tree list
; ----------------------------------------------------------------------------
draw_tree_list:
    cmp word [tree_count],0
    je .done

    mov word [draw_index],0
    mov word [draw_y],LIST_TOP

    ; Calculate visible range
    mov ax,[tree_scroll]
    mov [draw_index],ax

    cmp ax,[tree_count]
    jge .done

.draw_loop:
    mov bx,[draw_index]
    cmp bx,[tree_count]
    jge .done

    mov ax,[draw_y]
    cmp ax,STATUS_Y
    jge .done

    ; Get tree entry
    call get_tree_entry

    ; Draw row background if selected
    mov bx,[tree_selected]
    cmp bx,[draw_index]
    jne .draw_name

    box [tree_x]+1,[draw_y],[tree_w]-2,ROW_H,0

.draw_name:
    mov ax,[tree_x]+2
    mov bx,[draw_y]
    mov cl,0
    mov si,si                     ; Entry pointer in SI
    call draw_string

    ; Advance to next row
    inc word [draw_index]
    add word [draw_y],ROW_H
    jmp .draw_loop

.done:
    ret

; ----------------------------------------------------------------------------
; draw_file_list - Draw file list with name and size columns
; ----------------------------------------------------------------------------
draw_file_list:
    cmp word [file_count],0
    je .no_files

    mov word [draw_index],0
    mov word [draw_y],LIST_TOP

    ; Apply scroll offset
    mov ax,[file_scroll]
    mov [draw_index],ax

    cmp ax,[file_count]
    jge .done

.draw_loop:
    mov bx,[draw_index]
    cmp bx,[file_count]
    jge .done

    mov ax,[draw_y]
    cmp ax,STATUS_Y
    jge .done

    ; Get file entry
    call get_file_entry

    ; Draw row background if selected
    mov bx,[file_selected]
    cmp bx,[draw_index]
    jne .draw_row

    box [file_x]+1,[draw_y],[file_w]-2,ROW_H,0

.draw_row:
    ; Determine color based on attributes
    movzx ax,byte [si+F_ATTR]
    test al,10h                 ; Directory?
    jnz .is_dir

    test al,06h                 ; Hidden or system?
    jnz .hidden

    mov byte [row_color],0      ; Normal: black
    jmp .draw_fields

.is_dir:
    mov byte [row_color],1      ; Directory: blue
    jmp .draw_fields

.hidden:
    mov byte [row_color],8      ; Hidden: gray

.draw_fields:
    ; Draw filename
    mov ax,[file_x]+2
    mov bx,[draw_y]
    mov cl,[row_color]
    mov si,si
    call draw_string

    ; Draw size (skip directories and "..")
    mov bx,[draw_index]
    cmp bx,0
    je .next_row

    mov al,[si+F_ATTR]
    test al,10h
    jnz .next_row

    ; Format size
    mov ax,[si+F_SIZE_LO]
    mov dx,[si+F_SIZE_HI]
    mov di,size_str
    call format_dword

    mov ax,[file_x]+150
    mov bx,[draw_y]
    mov cl,[row_color]
    mov si,size_str
    call draw_string

.next_row:
    inc word [draw_index]
    add word [draw_y],ROW_H
    jmp .draw_loop

.no_files:
    puttext [file_x]+2,LIST_TOP,0,no_files

.done:
    ret

; ----------------------------------------------------------------------------
; draw_status_bar - Draw status bar at bottom
; ----------------------------------------------------------------------------
draw_status_bar:
    box 0,STATUS_Y,320,STATUS_H,7

    ; File count
    puttext 2,STATUS_Y+2,0,status_files
    mov ax,[file_count]
    mov di,count_str
    call format_word
    mov si,count_str
    puttext 40,STATUS_Y+2,0,si

    ; Selected indicator
    puttext 100,STATUS_Y+2,0,sel_label

    ret

; ----------------------------------------------------------------------------
; draw_active_menu - Draw open dropdown menu
; ----------------------------------------------------------------------------
draw_active_menu:
    cmp byte [menu_open],0
    je .done

    ; Draw menu background
    frame [menu_x],MENU_TOP,[menu_w],[menu_count]*ROW_H+4,0
    box [menu_x]+1,MENU_TOP+1,[menu_w]-2,[menu_count]*ROW_H+2,7

    ; Draw menu items
    mov word [draw_index],0
    mov word [draw_y],MENU_TOP+4

.draw_items:
    mov bx,[draw_index]
    cmp bx,[menu_count]
    jge .done

    mov ax,[draw_y]
    cmp ax,STATUS_Y
    jge .done

    ; Highlight selected item
    mov bx,[selected_menu_item]
    cmp bx,[draw_index]
    jne .draw_item

    ; Selected item background
    box [menu_x]+1,[draw_y],[menu_w]-2,ROW_H,0
    mov byte [menu_text_color],7    ; White text

.draw_item:
    push bx
    push cx
    push dx

    mov ax,[menu_x]+4
    mov bx,[draw_y]
    mov cx,[draw_index]
    mov dx,0                        ; Will be set by menuitem macro

    ; Get menu text based on menu type and index
    mov al,[menu_selected]

    cmp al,0
    je .file_menu_text

    cmp al,1
    je .options_menu_text

    cmp al,2
    je .view_menu_text

    cmp al,3
    je .help_menu_text

    jmp .after_text

.file_menu_text:
    cmp cx,0
    je .use_file_open
    cmp cx,1
    je .use_file_copy
    cmp cx,2
    je .use_file_move
    cmp cx,3
    je .use_file_paste
    cmp cx,4
    je .use_file_delete
    cmp cx,5
    je .use_file_rename
    cmp cx,6
    je .use_file_createdir
    cmp cx,7
    je .use_file_props
    cmp cx,8
    je .use_file_exit
    jmp .after_text

.use_file_open:
    mov dx,file_open
    jmp .draw_it

.use_file_copy:
    mov dx,file_copy
    jmp .draw_it

.use_file_move:
    mov dx,file_move
    jmp .draw_it

.use_file_paste:
    mov dx,file_paste
    jmp .draw_it

.use_file_delete:
    mov dx,file_delete
    jmp .draw_it

.use_file_rename:
    mov dx,file_rename
    jmp .draw_it

.use_file_createdir:
    mov dx,file_createdir
    jmp .draw_it

.use_file_props:
    mov dx,file_props
    jmp .draw_it

.use_file_exit:
    mov dx,file_exit
    jmp .draw_it

.options_menu_text:
    cmp cx,0
    je .use_opt_hidden
    cmp cx,1
    je .use_opt_tree
    jmp .after_text

.use_opt_hidden:
    mov dx,opt_hidden
    jmp .draw_it

.use_opt_tree:
    mov dx,opt_tree
    jmp .draw_it

.view_menu_text:
    cmp cx,0
    je .use_view_refresh
    cmp cx,1
    je .use_view_sort_name
    cmp cx,2
    je .use_view_sort_size
    jmp .after_text

.use_view_refresh:
    mov dx,view_refresh
    jmp .draw_it

.use_view_sort_name:
    mov dx,view_sort_name
    jmp .draw_it

.use_view_sort_size:
    mov dx,view_sort_size
    jmp .draw_it

.help_menu_text:
    cmp cx,0
    je .use_help_about

.use_help_about:
    mov dx,help_about

.draw_it:
    mov ax,[menu_x]+4
    mov bx,[draw_y]
    mov cl,[menu_text_color]
    mov si,dx
    call draw_string

    ; Reset text color
    mov byte [menu_text_color],0

    pop dx
    pop cx
    pop bx

    inc word [draw_index]
    add word [draw_y],ROW_H
    jmp .draw_items

.done:
    ret

; ----------------------------------------------------------------------------
; draw_menu_item - Draw individual menu item (legacy, kept for compatibility)
; ----------------------------------------------------------------------------
draw_menu_item:
    ret

; ============================================================================
; GRAPHICS PRIMITIVES (Windows 3.x Style)
; ============================================================================

; ----------------------------------------------------------------------------
; draw_button_up - Draw raised 3D button
; ----------------------------------------------------------------------------
draw_button_up:
    push ax
    push bx
    push cx
    push dx

    mov [btn_x],ax
    mov [btn_y],bx
    mov [brd_w],cx

    ; Draw outer border (white top/left, black bottom/right)
    mov ax,[btn_x]
    mov bx,[btn_y]
    mov cx,[brd_w]
    mov dx,12
    mov byte [rect_color],15    ; White
    call draw_border

    ; Draw inner fill
    mov ax,[btn_x]+1
    mov bx,[btn_y]+1
    mov cx,[brd_w]-2
    mov dx,10
    mov byte [rect_color],7     ; Light gray
    call draw_rect

    ; Draw button text
    mov si,dx                   ; Text pointer in DX
    mov ax,[btn_x]+2
    mov bx,[btn_y]+2
    mov cl,0                    ; Black text
    call draw_string

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; draw_pane - Draw 3D pane border
; ----------------------------------------------------------------------------
draw_pane:
    mov [pane_x],ax
    mov [pane_y],bx
    mov [pane_w],cx
    mov [pane_h],dx
    ret

; ----------------------------------------------------------------------------
; draw_rect - Draw filled rectangle
; Input: AX=x, BX=y, CX=width, DX=height, [rect_color]=color
; ----------------------------------------------------------------------------
draw_rect:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    mov [rect_x],ax
    mov [rect_y],bx
    mov [rect_w],cx
    mov [rect_h],dx

    ; Calculate bytes per row
    mov cx,[rect_h]

.row_loop:
    push cx

    mov di,[rect_y]
    mov ax,320
    mul di
    add ax,[rect_x]

    mov di,ax
    mov cx,[rect_w]

    mov al,[rect_color]
    rep stosb

    inc word [rect_y]

    pop cx
    loop .row_loop

    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; draw_border - Draw 3D border (white top/left, black bottom/right)
; ----------------------------------------------------------------------------
draw_border:
    push ax
    push bx
    push cx
    push dx

    mov [brd_x],ax
    mov [brd_y],bx
    mov [brd_w],cx
    mov [brd_h],dx

    ; Top edge (white)
    mov ax,[brd_x]
    mov bx,[brd_y]
    mov cx,[brd_w]
    mov dx,1
    mov byte [rect_color],15
    call draw_rect

    ; Left edge (white)
    mov ax,[brd_x]
    mov bx,[brd_y]
    mov cx,1
    mov dx,[brd_h]
    mov byte [rect_color],15
    call draw_rect

    ; Bottom edge (black)
    mov ax,[brd_x]
    mov bx,[brd_y]
    add bx,[brd_h]
    dec bx
    mov cx,[brd_w]
    mov dx,1
    mov byte [rect_color],0
    call draw_rect

    ; Right edge (black)
    mov ax,[brd_x]
    add ax,[brd_w]
    dec ax
    mov bx,[brd_y]
    mov cx,1
    mov dx,[brd_h]
    mov byte [rect_color],0
    call draw_rect

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; draw_string - Draw text string using 8x8 font
; Input: AX=x, BX=y, CL=color, SI=string pointer
; ----------------------------------------------------------------------------
draw_string:
    push ax
    push bx
    push cx
    push si
    push di
    push bp

    mov [str_x],ax
    mov [str_y],bx
    mov [str_c],cl

.draw_loop:
    lodsb
    test al,al
    jz .done

    ; Draw character
    movzx bp,al
    shl bp,3                    ; Multiply by 8 (bytes per char)

    mov ax,[str_x]
    mov bx,[str_y]
    mov cl,[str_c]
    mov di,bp
    call draw_char

    add word [str_x],8          ; Advance by character width

    jmp .draw_loop

.done:
    pop bp
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; draw_char - Draw single character from font
; Input: AX=x, BX=y, CL=color, DI=font offset
; ----------------------------------------------------------------------------
draw_char:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov [cursor_x],ax
    mov [cursor_y],bx
    mov [cursor_color],cl

    ; Get font bitmap
    mov si,font_data
    add si,di

    mov cx,8                    ; 8 rows

.row_loop:
    push cx

    lodsb                       ; Get font row
    mov [char_code],al

    mov di,[cursor_y]
    mov ax,320
    mul di
    add ax,[cursor_x]
    mov di,ax

    mov byte [char_buffer],8    ; 8 bits per row

.bit_loop:
    shl byte [char_code],1
    jc .draw_pixel

    jmp .next_pixel

.draw_pixel:
    mov byte [es:di],cl

.next_pixel:
    inc di
    dec byte [char_buffer]
    jnz .bit_loop

    add word [cursor_y],320     ; Next row

    pop cx
    loop .row_loop

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; draw_cursor - Draw mouse cursor
; ----------------------------------------------------------------------------
draw_cursor:
    cmp byte [mouse_ok],0
    je .done

    mov ax,[mouse_x]
    mov bx,[mouse_y]
    mov cl,15                   ; White cursor
    call draw_cursor_bitmap

.done:
    ret

; ----------------------------------------------------------------------------
; draw_cursor_bitmap - Draw cursor bitmap at position
; ----------------------------------------------------------------------------
draw_cursor_bitmap:
    push ax
    push bx
    push cx
    push si
    push di
    push es

    mov [cursor_x],ax
    mov [cursor_y],bx
    mov [cursor_color],cl

    mov si,cursor_bits
    mov cx,8

.row_loop:
    push cx

    lodsb
    mov [char_code],al

    mov di,[cursor_y]
    mov ax,320
    mul di
    add ax,[cursor_x]
    mov di,ax

    mov byte [char_buffer],8

.bit_loop:
    shl byte [char_code],1
    jc .draw_pixel

    jmp .next_pixel

.draw_pixel:
    mov byte [es:di],cl

.next_pixel:
    inc di
    dec byte [char_buffer]
    jnz .bit_loop

    add word [cursor_y],320

    pop cx
    loop .row_loop

    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; wait_vsync - Wait for vertical retrace
; ----------------------------------------------------------------------------
wait_vsync:
    push ax
    push dx

    ; Wait for VBLANK end
.wait_end:
    in dx,3DAh
    test dl,8
    jnz .wait_end

    ; Wait for VBLANK start
.wait_start:
    in dx,3DAh
    test dl,8
    jz .wait_start

    pop dx
    pop ax
    ret

; ============================================================================
; DIALOG BOXES
; ============================================================================

; ----------------------------------------------------------------------------
; show_message - Show message dialog
; Input: AX=title, BX=line1, CX=line2, DX=line3
; ----------------------------------------------------------------------------
show_message:
    mov [dlg_title],ax
    mov [dlg_prompt],bx
    mov [dlg_line1],cx
    mov [dlg_line2],dx
    mov word [dlg_line3],0
    mov word [dlg_line4],0

    call draw_dialog

    ; Wait for keypress
.wait_key:
    mov ah,1
    int 16h
    jz .wait_key

    mov ah,0
    int 16h
    ret

; ----------------------------------------------------------------------------
; confirm_box - Show yes/no confirmation dialog
; Returns: AL=1 for Yes, 0 for No
; ----------------------------------------------------------------------------
confirm_box:
    mov [dlg_title],ax
    mov [dlg_prompt],bx
    mov word [dlg_line1],0
    mov word [dlg_line2],0
    mov word [dlg_line3],0
    mov word [dlg_line4],0

    call draw_dialog
    puttext 120,160,0,msg_yesno

.wait_key:
    mov ah,1
    int 16h
    jz .wait_key

    mov ah,0
    int 16h

    cmp al,'Y'
    je .yes

    cmp al,'y'
    je .yes

    xor al,al
    ret

.yes:
    mov al,1
    ret

; ----------------------------------------------------------------------------
; input_box - Show input dialog
; Input: AX=title, BX=prompt, CX=max_len, DX=buffer
; Returns: AL=1 if OK, 0 if Cancel
; ----------------------------------------------------------------------------
input_box:
    mov [dlg_title],ax
    mov [dlg_prompt],bx
    mov [input_len],0
    mov si,dx
    mov byte [ds:si],0

    call draw_input_dialog

.input_loop:
    call draw_input_dialog

    ; Check for input
    mov ah,1
    int 16h
    jz .input_loop

    mov ah,0
    int 16h

    cmp al,1Bh                    ; Escape = Cancel
    je .cancel

    cmp al,0Dh                    ; Enter = OK
    je .ok

    cmp al,08h                    ; Backspace
    je .backspace

    cmp al,' '
    jb .input_loop                ; Ignore control chars

    ; Add character if room
    cmp byte [input_len],cl
    jge .input_loop

    mov si,dx
    add si,[input_len]
    mov [ds:si],al
    inc byte [input_len]
    mov si,dx
    add si,[input_len]
    mov byte [ds:si],0

    jmp .input_loop

.backspace:
    cmp byte [input_len],0
    je .input_loop

    dec byte [input_len]
    mov si,dx
    add si,[input_len]
    mov byte [ds:si],0
    jmp .input_loop

.ok:
    mov al,1
    ret

.cancel:
    xor al,al
    ret

; ----------------------------------------------------------------------------
; draw_dialog - Draw standard dialog box
; ----------------------------------------------------------------------------
draw_dialog:
    push ax
    push bx
    push cx
    push dx

    ; Draw dialog background
    frame 40,80,240,100,0
    box 41,81,238,98,7

    ; Draw title
    mov si,[dlg_title]
    puttext 45,82,0,si

    ; Draw prompt/lines
    mov si,[dlg_prompt]
    test si,si
    jz .line1

    puttext 50,95,0,si

.line1:
    mov si,[dlg_line1]
    test si,si
    jz .line2

    puttext 50,105,0,si

.line2:
    mov si,[dlg_line2]
    test si,si
    jz .done

    puttext 50,115,0,si

.line3:
    mov si,[dlg_line3]
    test si,si
    jz .done

    puttext 50,125,0,si

.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; draw_input_dialog - Draw input dialog with cursor
; ----------------------------------------------------------------------------
draw_input_dialog:
    call draw_dialog

    ; Draw input field
    frame 50,135,200,12,15
    box 51,136,198,10,0

    ; Draw current input
    mov si,input_buffer
    puttext 52,136,7,si

    ; Draw hint
    puttext 50,155,0,input_hint

    ; Draw cursor
    movzx ax,byte [input_len]
    add ax,52
    mov bx,136
    mov cl,7
    call draw_cursor

    ret

; ----------------------------------------------------------------------------
; update_input_len - Update input buffer length
; ----------------------------------------------------------------------------
update_input_len:
    mov byte [input_len],0
    mov si,input_buffer

.count:
    lodsb
    test al,al
    jz .done
    inc byte [input_len]
    jmp .count

.done:
    ret

; ----------------------------------------------------------------------------
; show_about - Show about dialog
; ----------------------------------------------------------------------------
show_about:
    mov ax,about_title
    mov bx,about1
    mov cx,about2
    mov dx,about3
    call show_message
    ret

; ----------------------------------------------------------------------------
; confirm_exit - Show exit confirmation
; ----------------------------------------------------------------------------
confirm_exit:
    mov ax,msg_exit_title
    mov bx,msg_exit_text
    call confirm_box

    test al,al
    jz .done

    jmp exit_program

.done:
    ret

; ----------------------------------------------------------------------------
; show_error - Show error message
; Input: SI=message pointer
; ----------------------------------------------------------------------------
show_error:
    mov ax,msg_error_title
    mov bx,si
    mov cx,0
    mov dx,0
    call show_message
    ret

; ----------------------------------------------------------------------------
; show_info - Show information message
; Input: SI=message pointer
; ----------------------------------------------------------------------------
show_info:
    mov ax,msg_info_title
    mov bx,si
    mov cx,0
    mov dx,0
    call show_message
    ret

; ============================================================================
; STRING AND NUMBER UTILITY FUNCTIONS
; ============================================================================

; ----------------------------------------------------------------------------
; str_copy - Copy null-terminated string
; Input: DS:SI=source, ES:DI=destination
; ----------------------------------------------------------------------------
str_copy:
    push cx

.copy:
    lodsb
    stosb
    test al,al
    jnz .copy

    pop cx
    ret

; ----------------------------------------------------------------------------
; str_end_di - Find end of string at ES:DI
; Output: DI points to null terminator
; ----------------------------------------------------------------------------
str_end_di:
    push ax

.find:
    mov al,[es:di]
    test al,al
    jz .done
    inc di
    jmp .find

.done:
    pop ax
    ret

; ----------------------------------------------------------------------------
; append_string - Append string to existing string at DI
; Input: SI=source string
; ----------------------------------------------------------------------------
append_string:
    push si
    push di

    call str_end_di
    mov si,[app_src]
    call str_copy

    pop di
    pop si
    ret

; ----------------------------------------------------------------------------
; append_char - Append single character to string at DI
; Input: AL=character
; ----------------------------------------------------------------------------
append_char:
    push di

    call str_end_di
    stosb
    xor al,al
    stosb

    pop di
    ret

; ----------------------------------------------------------------------------
; str_equal - Compare two strings
; Input: DS:SI=str1, DS:DI=str2
; Returns: ZF=1 if equal
; ----------------------------------------------------------------------------
str_equal:
    push ax

.compare:
    lodsb
    mov bl,[di]
    cmp al,bl
    jne .not_equal

    test al,al
    jz .equal

    inc di
    jmp .compare

.equal:
    pop ax
    ret

.not_equal:
    pop ax
    ret

; ----------------------------------------------------------------------------
; make_short_name - Convert filename to short 8.3 format
; Input: SI=source, Output: app_dst=destination
; ----------------------------------------------------------------------------
make_short_name:
    push si
    push di

    mov di,app_dst
    mov cx,8

.copy_name:
    lodsb
    test al,al
    jz .pad_name
    cmp al,'.'
    je .done
    stosb
    loop .copy_name

.pad_name:
    mov cx,8

.pad:
    mov al,' '
    stosb
    loop .pad

.done:
    pop di
    pop si
    ret

; ----------------------------------------------------------------------------
; format_word - Format 16-bit number as decimal string
; Input: AX=number, DI=destination buffer
; ----------------------------------------------------------------------------
format_word:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    test ax,ax
    jnz .convert

    ; Handle zero
    mov byte [es:di],'0'
    inc di
    mov byte [es:di],0
    jmp .done

.convert:
    mov si,num_rev
    mov cx,0

.digit_loop:
    xor dx,dx
    mov bx,10
    div bx

    add dl,'0'
    mov [si],dl
    inc si
    inc cx

    test ax,ax
    jnz .digit_loop

    ; Reverse digits
.reverse:
    dec si
    mov al,[si]
    stosb
    loop .reverse

    mov byte [es:di],0

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; format_dword - Format 32-bit number as decimal string
; Input: DX:AX=number, DI=destination buffer
; ----------------------------------------------------------------------------
format_dword:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    test dx,ax
    jnz .convert

    ; Handle zero
    mov byte [es:di],'0'
    inc di
    mov byte [es:di],0
    jmp .done

.convert:
    mov si,num_rev
    mov cx,0

.digit_loop:
    call div32_by_10

    add dl,'0'
    mov [si],dl
    inc si
    inc cx

    test dx,ax
    jnz .digit_loop

    ; Reverse digits
.reverse:
    dec si
    mov al,[si]
    stosb
    loop .reverse

    mov byte [es:di],0

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------------------
; div32_by_10 - Divide 32-bit number by 10
; Input: DX:AX=dividend, Output: DX:AX=quotient, DL=remainder
; ----------------------------------------------------------------------------
div32_by_10:
    push bx
    push cx

    mov bx,10
    xor cx,cx

    ; Divide high word
    xchg ax,dx
    div bx
    xchg ax,dx

    ; Divide low word with remainder
    div bx

    ; Remainder in DX -> DL
    mov dl,dl

    pop cx
    pop bx
    ret

; ============================================================================
; MACROS
; ============================================================================

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

macro draw_button_up x,y,s
{
    push ax
    push bx
    push cx
    push dx
    
    mov ax,x
    mov bx,y
    mov cx,30
    mov dx,s
    call draw_button_up
    
    pop dx
    pop cx
    pop bx
    pop ax
}

; ============================================================================
; DATA SEGMENT
; ============================================================================

; Graphics state variables
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

; Mouse state
mouse_ok            db 0
mouse_x             dw 160
mouse_y             dw 100
prev_buttons        dw 0

; Menu state
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

; Path and directory state
current_drive       db 'C'
current_path        rb 128
path_display        rb 32
dir_buffer          rb 64
is_root             db 0

; Layout state
tree_x              dw 0
tree_w              dw 0
file_x              dw 0
file_w              dw 0

show_tree           db 1
show_hidden         db 0
sort_mode           db 0
active_pane         db 0

; File list
file_list           rb MAX_FILES * ENTRY_SIZE
file_count          dw 0
file_start          dw 0
file_selected       dw 0
file_scroll         dw 0

; Tree list
tree_list           rb MAX_TREE * TREE_SIZE
tree_count          dw 0
tree_selected       dw 0
tree_scroll         dw 0

; Drawing helpers
draw_index          dw 0
draw_y              dw 0
entry_ptr           dw 0
row_color           db 0

; Buffers
row_buffer          rb 32
size_str            rb 16
count_str           rb 8
char_buffer         rb 4

tmp_src             dw 0
tmp_dst             dw 0

; Sorting helpers
sort_i              dw 0
cmp_i               dw 0
cmp_j               dw 0

; System buffers
dta_buffer          rb 128          ; Disk Transfer Area
font_data           rb 2048         ; 8x8 font (256 chars * 8 bytes)

; Constants and literals
dotdot_name         db '..',0
dotdot_path         db '..',0
root_path           db '\',0
star_dot_star       db '*.*',0

title_str           db 'File Manager',0

; Menu labels
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

; Toolbar labels
tb_open             db 'Open',0
tb_new              db 'New',0
tb_del              db 'Del',0
tb_ren              db 'Ren',0
tb_copy             db 'Copy',0
tb_move             db 'Move',0
tb_paste            db 'Paste',0

; UI labels
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

; Message titles
msg_error_title     db 'Error',0
msg_info_title      db 'Information',0
msg_confirm_title   db 'Confirm',0
msg_props_title     db 'Properties',0
msg_rename_title    db 'Rename',0
msg_mkdir_title     db 'Create Directory',0
msg_exit_title      db 'Exit',0

; About dialog
about_title         db 'About',0
about1              db 'Windows 3.x style File Manager',0
about2              db '16-bit real mode DOS',0
about3              db 'FASM 8086 compatible',0

; Messages
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

; Dialog variables
dlg_title           dw 0
dlg_prompt          dw 0
dlg_line1           dw 0
dlg_line2           dw 0
dlg_line3           dw 0
dlg_line4           dw 0
dlg_y               dw 0

input_buffer        rb 32
input_len           db 0

; Property display lines
prop_line1          rb 40
prop_line2          rb 40
prop_line3          rb 40

; Path buffers
path_buffer         rb 128
old_path            rb 128
new_path            rb 128
dest_path           rb 128
temp_name           rb 16
del_attr            db 0

; Clipboard
clip_count          dw 0
clip_op             db 0
clip_name           rb 16
clip_path           rb 128

; Copy/move buffers
copy_src            dw 0
copy_dst            dw 0
src_handle          dw 0
dst_handle          dw 0
copy_buffer         rb COPY_BUF_SIZE

; String append helpers
app_src             dw 0
app_dst             dw 0
app_char            db 0

; Number formatting
num_rev             rb 16
div32_low           dw 0
div32_high          dw 0

; 8x8 cursor bitmap (arrow shape)
cursor_bits:
    db 128,192,224,240,248,252,254,255
