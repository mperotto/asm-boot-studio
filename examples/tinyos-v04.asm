; ================================================================
; TinyOS v0.4 — 8 setores (4096 bytes)
; VESA 800x600 | PM32 | BIOS 8x8 font | Terminal 100x72
; Teclado + PS/2 Mouse | 256 cores
;
; Teclas: imprimíveis → terminal | Enter | Backspace | ESC=cor
; Mouse: move cursor vermelho 4x4
; ================================================================

; ---- SETOR 1: bootstrap real mode (512 bytes) ----
[BITS 16]
SECTION boot vstart=0x7C00

    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; VESA modo 0x103: 800x600, 256 cores, LFB
    ; Get mode info → buffer em 0x0000:0x0800
    xor ax, ax
    mov es, ax
    mov di, 0x0800
    mov ax, 0x4F01
    mov cx, 0x0103
    int 0x10
    ; Guarda PhysBasePtr (offset 40 no mode info block) em 0x0700
    mov eax, dword [0x0828]     ; 0x0800 + 40 = 0x0828
    mov dword [0x0700], eax
    ; Ativa modo com LFB (bit 14)
    mov ax, 0x4F02
    mov bx, 0x4103              ; 0x0103 | 0x4000
    int 0x10

    ; Init mouse PS/2
    call pw
    mov al, 0xA8              ; habilita porta aux
    out 0x64, al
    call pw
    mov al, 0x20              ; lê CCB
    out 0x64, al
    call pr
    in al, 0x60
    or  al, 0x02              ; habilita IRQ12
    and al, 0xDF              ; habilita clock mouse
    push ax
    call pw
    mov al, 0x60
    out 0x64, al
    call pw
    pop ax
    out 0x60, al
    call pw
    mov al, 0xD4              ; próximo byte → mouse
    out 0x64, al
    call pw
    mov al, 0xF4              ; enable data reporting
    out 0x60, al
    call pr
    in al, 0x60               ; descarta ACK

    ; Carrega setores 2-8 (7 setores) em 0x8000
    xor ax, ax
    mov es, ax
    mov bx, 0x8000
    mov ax, 0x0207
    mov cx, 0x0002
    xor dx, dx          ; dh=head 0, dl=drive 0 (floppy A:)
    int 0x13

    lgdt [gdt_desc]
    mov eax, cr0
    or  al, 1
    mov cr0, eax
    jmp 0x08:0x8000

pw: in al, 0x64
    test al, 0x02
    jnz pw
    ret
pr: in al, 0x64
    test al, 0x01
    jz pr
    ret

align 8
gdt_null: dq 0
gdt_code: dw 0xFFFF, 0x0000, 0x9A00, 0x00CF
gdt_data: dw 0xFFFF, 0x0000, 0x9200, 0x00CF
gdt_end:
gdt_desc: dw gdt_end - gdt_null - 1
          dd gdt_null

times 510-($-$$) db 0
dw 0xAA55


; ================================================================
; SETORES 2-8: Kernel 32-bit (0x8000, até 3584 bytes)
; ================================================================
[BITS 32]
SECTION kernel vstart=0x8000

%define IDT_ADDR   0x0500
%define LFB_STORE  0x0700       ; endereço LFB gravado pelo stage1
%define W          800
%define H          600
%define TEXT_Y1    8
%define TEXT_Y2    592          ; STAT_Y = TEXT_Y2 = H-8
%define STAT_Y     592
%define BG         0x01         ; azul escuro
%define COLS       100          ; 800/8
%define SCROLL_AT  74           ; scroll quando cur_row atinge 74 (última visível: 73)

; ---- Entrada do kernel ----
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9F000
    cld

    ; Lê endereço LFB do stage1 (gravado em 0x0700)
    mov eax, [LFB_STORE]
    mov [vga_base], eax

    ; ---- IDT em IDT_ADDR ----
    mov edi, IDT_ADDR
    mov eax, null_isr
    movzx ebx, ax
    shr eax, 16
    mov ecx, 48
.idt_fill:
    mov word [edi+0], bx
    mov word [edi+2], 0x0008
    mov word [edi+4], 0x8E00
    mov word [edi+6], ax
    add edi, 8
    loop .idt_fill
    mov edi, IDT_ADDR + 0x21*8
    mov eax, kb_isr
    call set_gate
    mov edi, IDT_ADDR + 0x2C*8
    mov eax, mouse_isr
    call set_gate
    lidt [idt_desc]

    ; ---- Remapeia PIC 8259 ----
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 4
    out 0x21, al
    mov al, 2
    out 0xA1, al
    mov al, 1
    out 0x21, al
    out 0xA1, al
    mov al, 0xF9            ; unmask IRQ1 (kb) + IRQ2 (cascade)
    out 0x21, al
    mov al, 0xEF            ; unmask IRQ12 (mouse)
    out 0xA1, al

    ; ---- Gradiente título (y 0-7) ----
    mov edi, [vga_base]
    mov ecx, 8
.title_row:
    push ecx
    push edi
    xor dl, dl
    mov ecx, W
.title_col:
    mov [edi], dl
    inc edi
    inc dl                  ; dl wraps automático em 256
    loop .title_col
    pop edi
    add edi, W
    pop ecx
    loop .title_row

    ; ---- Área de texto: azul escuro ----
    mov edi, [vga_base]
    add edi, TEXT_Y1*W
    mov ecx, (TEXT_Y2 - TEXT_Y1)*W / 4
    mov eax, (BG<<24)|(BG<<16)|(BG<<8)|BG
    rep stosd

    ; ---- Barra de status: preto ----
    mov edi, [vga_base]
    add edi, STAT_Y*W
    mov ecx, (H - STAT_Y)*W / 4
    xor eax, eax
    rep stosd

    ; ---- Título ----
    mov byte [text_fg], 0x0F
    mov esi, str_title
    mov ebx, 4
    mov ecx, 0
    call render_str

    ; ---- Welcome ----
    mov byte [text_fg], 0x0B
    mov esi, str_welcome
    mov ebx, 0
    mov ecx, TEXT_Y1
    call render_str

    ; ---- Estado inicial ----
    mov word [cur_col], 0
    mov word [cur_row], 2
    mov byte [text_fg], 0x0F
    mov byte [mouse_phase], 0

    call save_mouse_bg
    call draw_mouse_cursor
    call update_status

    sti
.idle:
    hlt
    jmp .idle


; ================================================================
; DADOS
; ================================================================

idt_desc:    dw 48*8-1
             dd IDT_ADDR

vga_base:    dd 0                ; LFB address (lido do stage1)

str_title:   db " TinyOS v0.4 | VESA 800x600 | PM32 | KB+Mouse | 256 cores ", 0
str_welcome: db " Type=print  Enter=newline  BS=del  ESC=color  Mouse=move", 0

cur_col:     dw 0
cur_row:     dw 2
text_fg:     db 0x0F

mouse_x:     dw 400
mouse_y:     dw 300
mouse_phase: db 0
mcur_bg:     times 16 db 0
str_status:  times 16 db 0     ; "X:NNN Y:NNN" buffer

scancode_table:
db   0,  27, '1','2','3','4','5','6','7','8','9','0','-','=',  8,  9
db 'q','w','e','r','t','y','u','i','o','p','[',']', 13,  0,'a','s'
db 'd','f','g','h','j','k','l',';', 39,'`',  0, 92,'z','x','c','v'
db 'b','n','m',',','.','/',  0, '*',  0, ' '
scancode_end:


; ================================================================
; FUNÇÕES
; ================================================================

set_gate:
    mov word [edi+0], ax
    shr eax, 16
    mov word [edi+6], ax
    ret

render_char:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov esi, font8x8
    movzx edx, al
    sub edx, 32             ; font começa no char 32 (space)
    imul edx, 8
    add esi, edx
    imul ecx, W
    add ecx, ebx
    add ecx, [vga_base]
    mov edi, ecx
    movzx edx, byte [text_fg]
    mov ecx, 8
.rc_row:
    lodsb
    push ecx
    mov ecx, 8
.rc_col:
    shl al, 1
    jnc .rc_bg
    mov byte [edi], dl
    jmp .rc_next
.rc_bg:
    mov byte [edi], BG
.rc_next:
    inc edi
    loop .rc_col
    add edi, W-8
    pop ecx
    loop .rc_row
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

render_str:
    push eax
    push ebx
    push ecx
.rs_next:
    cmp ebx, W
    jge .rs_done
    lodsb
    test al, al
    jz .rs_done
    call render_char
    add ebx, 8
    jmp .rs_next
.rs_done:
    pop ecx
    pop ebx
    pop eax
    ret

put_char:
    push eax
    push ebx
    push ecx
    cmp al, 8
    je .bs
    cmp al, 13
    je .nl
    cmp al, 27
    je .esc
    cmp al, ' '
    jl .done
    cmp al, 127
    jge .done
    movzx ebx, word [cur_col]
    shl ebx, 3
    movzx ecx, word [cur_row]
    imul ecx, 8
    call render_char
    inc word [cur_col]
    cmp word [cur_col], COLS
    jl .done
    mov word [cur_col], 0
    jmp .newline
.nl:
    mov word [cur_col], 0
.newline:
    inc word [cur_row]
    cmp word [cur_row], SCROLL_AT
    jl .done
    dec word [cur_row]
    call scroll_up
    jmp .done
.bs:
    cmp word [cur_col], 0
    jne .bs_same
    cmp word [cur_row], 2
    je .done
    dec word [cur_row]
    mov word [cur_col], COLS-1
    jmp .bs_erase
.bs_same:
    dec word [cur_col]
.bs_erase:
    push eax
    movzx ebx, word [cur_col]
    shl ebx, 3
    movzx ecx, word [cur_row]
    imul ecx, 8
    mov al, ' '
    call render_char
    pop eax
    jmp .done
.esc:
    inc byte [text_fg]
    cmp byte [text_fg], 0
    jne .done
    mov byte [text_fg], 1
.done:
    pop ecx
    pop ebx
    pop eax
    ret

scroll_up:
    push esi
    push edi
    push ecx
    push eax
    mov esi, [vga_base]
    add esi, TEXT_Y1*W + 8*W
    mov edi, [vga_base]
    add edi, TEXT_Y1*W
    mov ecx, (TEXT_Y2 - TEXT_Y1 - 8)*W / 4
    rep movsd
    mov edi, [vga_base]
    add edi, (TEXT_Y2 - 8)*W
    mov ecx, 8*W / 4
    mov eax, (BG<<24)|(BG<<16)|(BG<<8)|BG
    rep stosd
    pop eax
    pop ecx
    pop edi
    pop esi
    ret

save_mouse_bg:
    push esi
    push edi
    push ecx
    push eax
    movzx esi, word [mouse_y]
    imul esi, W
    movzx eax, word [mouse_x]
    add esi, eax
    add esi, [vga_base]
    mov edi, mcur_bg
    mov ecx, 4
.smb:
    mov eax, [esi]
    mov [edi], eax
    add esi, W
    add edi, 4
    loop .smb
    pop eax
    pop ecx
    pop edi
    pop esi
    ret

restore_mouse_bg:
    push esi
    push edi
    push ecx
    push eax
    mov esi, mcur_bg
    movzx edi, word [mouse_y]
    imul edi, W
    movzx eax, word [mouse_x]
    add edi, eax
    add edi, [vga_base]
    mov ecx, 4
.rmb:
    mov eax, [esi]
    mov [edi], eax
    add esi, 4
    add edi, W
    loop .rmb
    pop eax
    pop ecx
    pop edi
    pop esi
    ret

draw_mouse_cursor:
    push edi
    push ecx
    push eax
    movzx edi, word [mouse_y]
    imul edi, W
    movzx eax, word [mouse_x]
    add edi, eax
    add edi, [vga_base]
    mov ecx, 4
.dmc:
    mov dword [edi], 0x0C0C0C0C
    add edi, W
    loop .dmc
    pop eax
    pop ecx
    pop edi
    ret

update_status:
    push eax
    push ecx
    push edx
    push edi
    push esi

    ; Build "X:NNN Y:NNN" in str_status
    mov edi, str_status
    mov byte [edi], 'X'
    inc edi
    mov byte [edi], ':'
    inc edi
    movzx eax, word [mouse_x]
    call dec3_str
    mov byte [edi], ' '
    inc edi
    mov byte [edi], 'Y'
    inc edi
    mov byte [edi], ':'
    inc edi
    movzx eax, word [mouse_y]
    call dec3_str
    mov byte [edi], 0

    ; Clear status area
    mov edi, [vga_base]
    add edi, STAT_Y*W
    mov ecx, (H - STAT_Y)*W / 4
    xor eax, eax
    rep stosd

    ; Render em amarelo, preserva text_fg
    movzx ecx, byte [text_fg]
    push ecx
    mov byte [text_fg], 0x0E
    mov esi, str_status
    mov ebx, 4
    mov ecx, STAT_Y
    call render_str
    pop ecx
    mov [text_fg], cl

    pop esi
    pop edi
    pop edx
    pop ecx
    pop eax
    ret

dec3_str:
    ; Convert eax (0-999) → 3 decimal chars at [edi], edi += 3
    push edx
    push ecx
    mov ecx, 100
    xor edx, edx
    div ecx
    add al, '0'
    mov [edi], al
    inc edi
    mov eax, edx
    mov ecx, 10
    xor edx, edx
    div ecx
    add al, '0'
    mov [edi], al
    inc edi
    mov al, dl
    add al, '0'
    mov [edi], al
    inc edi
    pop ecx
    pop edx
    ret


; ================================================================
; ISRs
; ================================================================

kb_isr:
    push eax
    push ebx
    in al, 0x60
    test al, 0x80
    jnz .eoi
    movzx ebx, al
    cmp ebx, scancode_end - scancode_table
    jge .eoi
    mov al, [scancode_table + ebx]
    test al, al
    jz .eoi
    call put_char
.eoi:
    mov al, 0x20
    out 0x20, al
    pop ebx
    pop eax
    iret

mouse_isr:
    push eax
    push ebx
    in al, 0x60
    movzx ebx, byte [mouse_phase]
    cmp ebx, 0
    je .p0
    cmp ebx, 1
    je .p1
    ; fase 2: delta Y
    movsx eax, al
    neg eax
    movsx ebx, word [mouse_y]
    add ebx, eax
    cmp ebx, 0
    jge .y0
    xor ebx, ebx
.y0:
    cmp ebx, H-5
    jle .y1
    mov ebx, H-5
.y1:
    mov [mouse_y], bx
    mov byte [mouse_phase], 0
    call save_mouse_bg
    call draw_mouse_cursor
    call update_status
    jmp .eoi
.p1:
    ; fase 1: delta X — apaga cursor ANTES de mover
    call restore_mouse_bg
    movsx eax, al
    movsx ebx, word [mouse_x]
    add ebx, eax
    cmp ebx, 0
    jge .x0
    xor ebx, ebx
.x0:
    cmp ebx, W-5
    jle .x1
    mov ebx, W-5
.x1:
    mov [mouse_x], bx
    inc byte [mouse_phase]
    jmp .eoi
.p0:
    inc byte [mouse_phase]
.eoi:
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop ebx
    pop eax
    iret

null_isr:
    push eax
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop eax
    iret

; ================================================================
; FONT 8x8 embutida — ASCII 32-127 (96 chars × 8 bytes = 768 bytes)
; ================================================================
font8x8:
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  ; ' '
    db 0x18, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x18, 0x00  ; '!'
    db 0x66, 0x66, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00  ; '"'
    db 0x6C, 0x6C, 0xFE, 0x6C, 0xFE, 0x6C, 0x6C, 0x00  ; '#'
    db 0x18, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x18, 0x00  ; '$'
    db 0x00, 0xC6, 0xCC, 0x18, 0x30, 0x66, 0xC6, 0x00  ; '%'
    db 0x38, 0x6C, 0x38, 0x76, 0xDC, 0xCC, 0x76, 0x00  ; '&'
    db 0x18, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00  ; '''
    db 0x0C, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00  ; '('
    db 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00  ; ')'
    db 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00  ; '*'
    db 0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00  ; '+'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x30  ; ','
    db 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00  ; '-'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00  ; '.'
    db 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80, 0x00  ; '/'
    db 0x38, 0x6C, 0xC6, 0xD6, 0xC6, 0x6C, 0x38, 0x00  ; '0'
    db 0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00  ; '1'
    db 0x7C, 0xC6, 0x06, 0x1C, 0x30, 0x66, 0xFE, 0x00  ; '2'
    db 0x7C, 0xC6, 0x06, 0x3C, 0x06, 0xC6, 0x7C, 0x00  ; '3'
    db 0x1C, 0x3C, 0x6C, 0xCC, 0xFE, 0x0C, 0x1E, 0x00  ; '4'
    db 0xFE, 0xC0, 0xC0, 0xFC, 0x06, 0xC6, 0x7C, 0x00  ; '5'
    db 0x38, 0x60, 0xC0, 0xFC, 0xC6, 0xC6, 0x7C, 0x00  ; '6'
    db 0xFE, 0xC6, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x00  ; '7'
    db 0x7C, 0xC6, 0xC6, 0x7C, 0xC6, 0xC6, 0x7C, 0x00  ; '8'
    db 0x7C, 0xC6, 0xC6, 0x7E, 0x06, 0x0C, 0x78, 0x00  ; '9'
    db 0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x00  ; ':'
    db 0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x30  ; ';'
    db 0x06, 0x0C, 0x18, 0x30, 0x18, 0x0C, 0x06, 0x00  ; '<'
    db 0x00, 0x00, 0x7E, 0x00, 0x00, 0x7E, 0x00, 0x00  ; '='
    db 0x60, 0x30, 0x18, 0x0C, 0x18, 0x30, 0x60, 0x00  ; '>'
    db 0x7C, 0xC6, 0x0C, 0x18, 0x18, 0x00, 0x18, 0x00  ; '?'
    db 0x7C, 0xC6, 0xDE, 0xDE, 0xDE, 0xC0, 0x78, 0x00  ; '@'
    db 0x38, 0x6C, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00  ; 'A'
    db 0xFC, 0x66, 0x66, 0x7C, 0x66, 0x66, 0xFC, 0x00  ; 'B'
    db 0x3C, 0x66, 0xC0, 0xC0, 0xC0, 0x66, 0x3C, 0x00  ; 'C'
    db 0xF8, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0xF8, 0x00  ; 'D'
    db 0xFE, 0x62, 0x68, 0x78, 0x68, 0x62, 0xFE, 0x00  ; 'E'
    db 0xFE, 0x62, 0x68, 0x78, 0x68, 0x60, 0xF0, 0x00  ; 'F'
    db 0x3C, 0x66, 0xC0, 0xC0, 0xCE, 0x66, 0x3A, 0x00  ; 'G'
    db 0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00  ; 'H'
    db 0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00  ; 'I'
    db 0x1E, 0x0C, 0x0C, 0x0C, 0xCC, 0xCC, 0x78, 0x00  ; 'J'
    db 0xE6, 0x66, 0x6C, 0x78, 0x6C, 0x66, 0xE6, 0x00  ; 'K'
    db 0xF0, 0x60, 0x60, 0x60, 0x62, 0x66, 0xFE, 0x00  ; 'L'
    db 0xC6, 0xEE, 0xFE, 0xFE, 0xD6, 0xC6, 0xC6, 0x00  ; 'M'
    db 0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0x00  ; 'N'
    db 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00  ; 'O'
    db 0xFC, 0x66, 0x66, 0x7C, 0x60, 0x60, 0xF0, 0x00  ; 'P'
    db 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xCE, 0x7C, 0x0E  ; 'Q'
    db 0xFC, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0xE6, 0x00  ; 'R'
    db 0x3C, 0x66, 0x30, 0x18, 0x0C, 0x66, 0x3C, 0x00  ; 'S'
    db 0x7E, 0x7E, 0x5A, 0x18, 0x18, 0x18, 0x3C, 0x00  ; 'T'
    db 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00  ; 'U'
    db 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00  ; 'V'
    db 0xC6, 0xC6, 0xC6, 0xD6, 0xD6, 0xFE, 0x6C, 0x00  ; 'W'
    db 0xC6, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0xC6, 0x00  ; 'X'
    db 0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x3C, 0x00  ; 'Y'
    db 0xFE, 0xC6, 0x8C, 0x18, 0x32, 0x66, 0xFE, 0x00  ; 'Z'
    db 0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00  ; '['
    db 0xC0, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x02, 0x00  ; '\'
    db 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00  ; ']'
    db 0x10, 0x38, 0x6C, 0xC6, 0x00, 0x00, 0x00, 0x00  ; '^'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF  ; '_'
    db 0x30, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00  ; '`'
    db 0x00, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0x76, 0x00  ; 'a'
    db 0xE0, 0x60, 0x7C, 0x66, 0x66, 0x66, 0xDC, 0x00  ; 'b'
    db 0x00, 0x00, 0x7C, 0xC6, 0xC0, 0xC6, 0x7C, 0x00  ; 'c'
    db 0x1C, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x00  ; 'd'
    db 0x00, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0x7C, 0x00  ; 'e'
    db 0x3C, 0x66, 0x60, 0xF8, 0x60, 0x60, 0xF0, 0x00  ; 'f'
    db 0x00, 0x00, 0x76, 0xCC, 0xCC, 0x7C, 0x0C, 0xF8  ; 'g'
    db 0xE0, 0x60, 0x6C, 0x76, 0x66, 0x66, 0xE6, 0x00  ; 'h'
    db 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x3C, 0x00  ; 'i'
    db 0x06, 0x00, 0x06, 0x06, 0x06, 0x66, 0x66, 0x3C  ; 'j'
    db 0xE0, 0x60, 0x66, 0x6C, 0x78, 0x6C, 0xE6, 0x00  ; 'k'
    db 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00  ; 'l'
    db 0x00, 0x00, 0xEC, 0xFE, 0xD6, 0xD6, 0xD6, 0x00  ; 'm'
    db 0x00, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x00  ; 'n'
    db 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0x7C, 0x00  ; 'o'
    db 0x00, 0x00, 0xDC, 0x66, 0x66, 0x7C, 0x60, 0xF0  ; 'p'
    db 0x00, 0x00, 0x76, 0xCC, 0xCC, 0x7C, 0x0C, 0x1E  ; 'q'
    db 0x00, 0x00, 0xDC, 0x76, 0x60, 0x60, 0xF0, 0x00  ; 'r'
    db 0x00, 0x00, 0x7E, 0xC0, 0x7C, 0x06, 0xFC, 0x00  ; 's'
    db 0x30, 0x30, 0xFC, 0x30, 0x30, 0x36, 0x1C, 0x00  ; 't'
    db 0x00, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00  ; 'u'
    db 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00  ; 'v'
    db 0x00, 0x00, 0xC6, 0xD6, 0xD6, 0xFE, 0x6C, 0x00  ; 'w'
    db 0x00, 0x00, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0x00  ; 'x'
    db 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0x7E, 0x06, 0xFC  ; 'y'
    db 0x00, 0x00, 0x7E, 0x4C, 0x18, 0x32, 0x7E, 0x00  ; 'z'
    db 0x0E, 0x18, 0x18, 0x70, 0x18, 0x18, 0x0E, 0x00  ; '{'
    db 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00  ; '|'
    db 0x70, 0x18, 0x18, 0x0E, 0x18, 0x18, 0x70, 0x00  ; '}'
    db 0x76, 0xDC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  ; '~'
    db 0xC6, 0x00, 0xFE, 0xC0, 0xFC, 0xC0, 0xFE, 0x00  ; DEL

times 512*7-($-$$) db 0
