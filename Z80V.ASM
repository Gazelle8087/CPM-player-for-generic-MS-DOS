;	CP/M 2.2 player for generic MS-DOS Rev. 1.10
;
;	Copyright (C) 2024 by Gazelle
;
;Permission is hereby granted, free of charge, to any person
;obtaining a copy of this software and associated documentation
;files (the "Software"), to deal in the Software without
;restriction, including without limitation the rights to use,
;copy, modify, merge, publish, distribute, sublicense, and/or sell
;copies of the Software, and to permit persons to whom the
;Software is furnished to do so, subject to the following
;conditions:
;
;The above copyright notice and this permission notice shall be
;included in all copies or substantial portions of the Software.
;
;THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;OTHER DEALINGS IN THE SOFTWARE.

;Repository https://github.com/Gazelle8087/CPM-player-for-generic-MS-DOS
;
;2024/8/22 Rev. 1.00 Initial release
;2025/5/18 Rev. 1.10 Convert CP/M arguments to uppercase.
;                    Change CPU instruction execution module to Z80EM.BIN
;                    Change name 80 to Z80
;2025/9/21 Rev. 1.20 combination with Z80EMV.BIN 
;                    (V20/30 8080 emulation mode implemented)

		page 0,150
		.model	tiny
		.code

		org	100h

		assume	ds:nothing,es:nothing,ss:nothing

start:		jmp	hajime
		align	2

save_bp		dw	?
save_di		dw	?
save_si		dw	?
save_cx		dw	?
save_dx		dw	?
z80_seg		dw	?
em_file_handle	dw	?
cpm_file_handle	dw	?
cpm_arg_offset	dw	?
fcb_addr	dw	?
path_flag	db	0
env_flag	db	0
drv_flag	db	0
file_name_end	dw	?

ret_reg		equ	di
entry_SP	equ	bp

int_no		equ	0ffh

com_str			db	'.COM',0
cpm_str			db	'.CPM',0
env_key			db	'Z_EM='
em_file_name0		db	'Z80EMV.BIN',0
em_file_name0_end:
env_str			db	128 dup (0)
em_file_name		db	128 dup (?)
cpm_file_name		db	128 dup (?)
buffer_area		db	128 dup (?)

;---------------------------------------------

hajime:		mov	ax,cs
		mov	es,ax
		mov	ds,ax
		mov	dx,offset open_msg
		mov	ah,9
		int	21h
		mov	ah,4ah		;Free up memory leaving 128KB
		mov	bx,3001h
		int	21h
		jnc	main_read_emulator
		jmp	no_mem
main_read_emulator:
		mov	ax,cs
		mov	ss,ax
		mov	sp,0f000h
		add	ax,1000h
		test	ax,1
		jz	em_seg_even
		inc	ax
em_seg_even:	mov	em_seg,ax
		add	ax,1000h
		mov	z80_seg,ax

		call	search_env

		call	read_emulator

		call	read_cpm_file

		call	setup_cpm_area

;--------------------------------------

		mov	si,100h		;PC reg in Z80
		xor	ret_reg,ret_reg
		mov	es,ret_reg
		mov	es:[int_no*4],si
		mov	ds,z80_seg
		mov	es:[int_no*4+2],ds
		mov	es,z80_seg
		mov	entry_SP,CPM_BDOS-2	;SP
		mov	ds:[entry_SP],word ptr 0
		mov	save_bp,entry_SP

		mov	dx,80h
		mov	ah,1ah
		int	21h
		cld
go_cpm:
no_op:
		mov	entry_SP,save_bp
		xor	ret_reg,ret_reg
		mov	ds,z80_seg
		mov	es,z80_seg
;		mov	cx,save_cx
;		mov	dx,save_dx

		db	09ah	;CALL far
		dw	0c0h	;Z80 emulator entry point
EM_SEG		dw	?	;emulator loading segment

;		mov	save_dx,dx
;		mov	save_cx,cx
;		mov	save_bp,bp
;		mov	save_si,si
		cmp	ret_reg,0	;exit by ED FD ?
		jnz	z80_error

		xor	si,si
		mov	es,si
		mov	si,ds:[entry_SP]
		mov	es:[int_no*4],si
		add	entry_SP,2
		mov	save_bp,entry_SP

		cmp	al,0			;BDOS模擬ルーチンでは AL=0を設定
		je	to_bdos

		cmp	al,10h			;BIOS1模擬ルーチンでは AL=BIOS番号を設定
		ja	bios_no_error
		mov	bl,al
		mov	bh,0
		add	bx,bx
		jmp	word ptr cs:[bx+bios_table]

to_bdos:	cmp	cl,28h
		ja	bdos_no_error
		mov	bl,cl
		mov	bh,0
		add	bx,bx
		jmp	word ptr cs:[bx+bdos_table]

;---------------------------------
bdos_no_error_msg	db	'Incompatible bdos no $'
bios_no_error_msg	db	'Incompatible bios no $'

BIOS_no_error:
		mov	cl,al
		mov	dx,offset bios_no_error_msg
		jmp	bdos_bios_em_err
BDOS_no_error:
		mov	dx,offset bdos_no_error_msg
bdos_bios_em_err:
		mov	ax,cs
		mov	ds,ax
		mov	ah,9
		int	21h
		mov	al,cl
		call	dsphex2
		mov	ax,4c00h
		int	21h

;---------------------------------
Z80em_undef_msg		db	'Undefined code $'
Z80em_unexec_msg	db	'Unexecutable code $'
Z80em_error_msg		db	' at $'
z80em_err_addr		dw	?

Z80_error:	mov	dx,offset z80em_unexec_msg
		mov	cx,1
		mov	bx,1
		cmp	ret_reg,1
		je	z80_error_0

		mov	cx,2
		mov	bx,1
		cmp	ret_reg,2
		je	z80_error_0

		mov	cx,2
		mov	bx,1
		cmp	ret_reg,3
		je	z80_error_0

		mov	cx,2
		mov	bx,2
		cmp	ret_reg,4
		je	z80_error_0

		mov	dx,offset z80em_undef_msg
		mov	cx,2
		mov	bx,2
		cmp	ret_reg,5
		je	z80_error_0

		mov	cx,4
		mov	bx,4
		cmp	ret_reg,6
		je	z80_error_0

		mov	cx,1
		mov	bx,1
		cmp	ret_reg,7
		je	z80_error_0

		jmp	z80em_internal_error

z80_error_0:	mov	ax,cs
		mov	ds,ax
		mov	ah,9
		int	21h

		sub	si,bx
		mov	z80em_err_addr,si
		mov	es,z80_seg
z80_error_6:
		mov	al,es:[si]
		call	dsphex2
		inc	si
		loop	z80_error_6
		mov	dx,offset z80em_error_msg
		mov	ah,9
		int	21h
		mov	ax,z80em_err_addr
		call	dsphex4
		mov	ax,4c00h
		int	21h

;--------------------------------------
		even
bdos_table	dw	sonomama	;0  system reset
		dw	sonomama	;1  input from console
		dw	sonomama	;2  output to consple
		dw	sonomama	;3  input from reader
		dw	sonomama	;4  output to punch
		dw	sonomama	;5  output to printer
		dw	sonomama	;6  direct console I/O
		dw	get_io_byte	;7  get io byte
		dw	set_io_byte	;8  set io byte
		dw	sonomama	;9  output string to console
		dw	sonomama	;A  bufferd input from console
		dw	bdos_const	;B  check console status
		dw	get_version	;C  get version no
		dw	sonomama	;D  disk reset
		dw	sonomama	;E  disk select
		dw	sonomama	;F  open
		dw	sonomama	;10 close
		dw	file_search1	;11 search first
		dw	file_search2	;12 search next
		dw	sonomama	;13 delete
		dw	bdos_read	;14 read seaquential
		dw	sonomama	;15 write seaquential
		dw	sonomama	;16 create
		dw	sonomama	;17 rename
		dw	get_login_vect	;18 get login vector
		dw	sonomama	;19 get current drive
		dw	sonomama	;1A set DMA addr
		dw	get_alloc_addr	;1B get allocation addr
		dw	set_ro		;1C set R/O
		dw	get_ro_vect	;1D get R/O vector
		dw	set_file_attr	;1E set file attrib
		dw	get_DPB_addr	;1F get DPB addr
		dw	get_set_user	;20 get/set user code
		dw	sonomama	;21 read random
		dw	sonomama	;22 write random
		dw	sonomama	;23 get file size
		dw	sonomama	;24 set random record
		dw	reset_disk2	;25 reset disk by vector
		dw	no_op		;26
		dw	no_op		;27
		dw	sonomama	;28 write random w/zero fill

sonomama:	mov	ah,cl
		int	21h
		jmp	go_cpm

bdos_const:	mov	ah,0bh
		mov	bx,1
		int	21h
		cmp	al,0
		je	bdos_noready
		mov	al,1
bdos_noready:	jmp	go_cpm

get_io_byte:	mov	al,ds:[0003]
		jmp	go_cpm

set_io_byte:	mov	ds:[0003],dl
		jmp	go_cpm

get_version:	mov	bx,22h
		jmp	go_cpm

file_search1:	mov	fcb_addr,dx
		mov	ah,11h
		int	21h
		jmp	go_cpm

file_search2:	mov	dx,fcb_addr
		mov	ah,12h
		int	21h
		jmp	go_cpm

bdos_read:	mov	ah,14h
		int	21h
		cmp	al,3
		jne	bdos_read_exit
		mov	al,0
bdos_read_exit:	jmp	go_cpm

get_set_user:
		cmp	dl,0ffh
		jne	set_user_code
		mov	al,0
		jmp	go_cpm

set_user_code:	cmp	dl,0
		je	set_user_code_0
		jmp	bdos_no_error
set_user_code_0:jmp	go_cpm

bdos_reader:	;3  input from reader
bdos_punch:	;4  output to punch
get_login_vect:	;18 get login vector
get_alloc_addr:	;1B get allocation addr
set_ro:		;1C set R/O
get_ro_vect:	;1D get R/O vector
set_file_attr:	;1E set file attrib
get_DPB_addr:	;1F get DPB addr
reset_disk2:	;25 reset disk by vector

		jmp	bdos_no_error
;--------------------------------------
bios_table	dw	bios_boot
		dw	bios_wboot
		dw	bios_const
		dw	bios_conin
		dw	bios_conout
		dw	bios_list
		dw	bios_punch
		dw	bios_reader
		dw	bios_home
		dw	bios_seldsk
		dw	bios_settrk
		dw	bios_setsec
		dw	bios_setdma
		dw	bios_read
		dw	bios_write
		dw	bios_listst
		dw	bios_sectran

bios_boot:
bios_wboot:	mov	ax,4c00h
		int	21h

bios_const:	mov	ax,4406h
		mov	bx,1
		int	21h
		jmp	go_cpm

bios_conin:	mov	ah,7
		int	21h
		jmp	go_cpm

bios_conout:	mov	ah,6
		cmp	cl,0ffh
		je	bios_conout1
		mov	dl,cl
		int	21h
		jmp	go_cpm

bios_conout1:	mov	dl,00
		int	21h
		jmp	go_cpm

bios_list:
bios_punch:
bios_reader:
bios_listst:
bios_home:
bios_seldsk:
bios_settrk:
bios_setsec:
bios_setdma:
bios_read:
bios_write:
bios_sectran:
		jmp	bios_no_error
;======================================
open_msg		db	'CP/M 2.2 player for generic MS-DOS and V20/30 Rev. 1.00',0dh,0ah
			db	'Copyright (c) 2025 by Gazelle',0dh,0ah,0ah,24h
no_mem_msg		db	'No enough memory.$'
em_open_error_msg	db	'Z80EM.BIN open error.$'
em_read_error_msg	db	'Z80EM.BIN read error.$'
em_close_error_msg	db	'Z80EM.BIN close error.$'
cpm_open_error_msg	db	'CPM file open error.$'
cpm_read_error_msg	db	'CPM file read error.$'
cpm_close_error_msg	db	'CPM file close error.$'
too_long_path_msg	db	'too long path.$'
too_large_com_msg	db	'too large COM file.$'
internal_error_msg	db	'Z80EM.BIN internal error.$'

em_close_error:	mov	dx,offset em_close_error_msg
		jmp	error_exit
em_open_error:	mov	dx,offset em_open_error_msg
		jmp	error_exit
em_read_error:	mov	dx,offset em_read_error_msg
		jmp	error_exit
cpm_close_error:mov	dx,offset cpm_close_error_msg
		jmp	error_exit
cpm_open_error:	mov	dx,offset cpm_open_error_msg
		jmp	error_exit
cpm_read_error:	mov	dx,offset cpm_read_error_msg
		jmp	error_exit
no_mem:		mov	dx,offset no_mem_msg
		jmp	error_exit
too_long_path:	mov	dx,offset too_long_path_msg
		jmp	error_exit
too_large_com:	mov	dx,offset too_large_com_msg
		jmp	error_exit
z80em_internal_error:
		mov	dx,offset internal_error_msg
		jmp	error_exit

error_exit:
		mov	ax,cs
		mov	ds,ax
		mov	ah,9
		int	21h
		mov	ax,4c00h
		int	21h
;======================================

search_env:	mov	ax,cs
		mov	es,ax
		mov	ax,cs:[002ch]
		mov	ds,ax
		mov	si,0
		cld

search_env_next_4:
		mov	bx,0ffffh
		mov	di,offset env_key
		mov	dl,es:[di]
		lodsb
search_env_next_2:
		cmp	al,dl
		je	search_env_match_1
search_env_next_3:
		cmp	al,0
		je	search_env_next_5
search_env_next_1:
		lodsb
		and	si,si
		je	search_env_exit_1
		cmp	al,0
		jne	search_env_next_1
search_env_next_5:
		lodsb
		and	si,si
		je	search_env_exit_1
		cmp	al,0
		je	search_env_exit
		jmp	search_env_next_2

search_env_match_1:
		mov	bx,si
		dec	bx

search_env_match_3:
		lodsb
		and	si,si
		je	search_env_exit_1
		inc	di
		mov	dl,es:[di]
		cmp	al,dl
		je	search_env_match_2
search_env_match_4:
		cmp	al,0
		je	search_env_next_4
		lodsb
		and	si,si
		je	search_env_exit_1
		jmp	search_env_match_4
search_env_match_2:
		cmp	al,'='
		jne	search_env_match_3

		mov	cx,128
		mov	di,offset env_str
search_env_get:
		lodsb
		stosb
		cmp	al,0
		je	search_env_exit
		loop	search_env_get
		jmp	search_env_exit_1

search_env_exit_1:
		mov	bx,0ffffh
search_env_exit:
		mov	ax,cs
		mov	ds,ax
		ret
;================================================

read_emulator:
		mov	ax,cs
		mov	ds,ax
		mov	es,ax
		mov	ax,3d00h
		mov	dx,offset em_file_name0		;search current dir
;		call	disp_file_name
		int	21h
		jnc	read_em_4

		mov	si,offset env_str
		mov	di,offset em_file_name
		cld
		lodsb
		and	al,al
		jnz	read_em_31
		jmp	em_open_error
read_em_31:
		stosb
		mov	cx,117
read_em_1:
		lodsb
		and	al,al
		jz	read_em_2
		stosb
		loop	read_em_1
		jmp	too_long_path
read_em_2:
		mov	al,'\'
		stosb
read_em_3:
		mov	si,offset em_file_name0
		mov	cx,offset em_file_name0_end - offset em_file_name0
		rep	movsb

		mov	ax,3d00h
		mov	dx,offset em_file_name
;		call	disp_file_name
		int	21h
		jnc	read_em_4
		jmp	em_open_error
read_em_4:
		mov	em_file_handle,ax
		mov	bx,ax
		mov	ah,3fh
		mov	cx,0ffffh
		mov	ds,em_seg
		mov	dx,0
		int	21h
		jnc	read_em_5
		jmp	em_read_error
read_em_5:
		mov	ax,cs
		mov	ds,ax
		mov	ah,3eh
		mov	bx,em_file_handle
		int	21h
		jnc	read_em_exit
		jmp	em_close_error
read_em_exit:
		mov	ax,cs
		mov	ds,ax
		mov	es,ax
		ret
;================================================
read_cpm_file:
read_cpm_00:
		mov	di,offset cpm_file_name
read_cpm_0:
		mov	si,81h
		mov	cl,ds:[80h]
		mov	ch,0
read_cpm_01:	lodsb
		cmp	al,' '
		je	read_cpm_01
		cmp	al,09h
		je	read_cpm_01
		dec	si

read_cpm_02:	lodsb
		cmp	al,' '
		je	read_cpm_03
		cmp	al,0dh
		je	read_cpm_03
		cmp	al,0
		je	read_cpm_03
		cmp	al,09h
		je	read_cpm_03
		cmp	al,':'
		jne	read_cpm_04
		cmp	ah,'A'
		jb	read_cpm_04
		cmp	ah,'Z'
		jbe	read_cpm_06
		cmp	ah,'z'
		ja	read_cpm_04
		cmp	ah,'a'
		jb	read_cpm_04
read_cpm_06:	mov	drv_flag,1
read_cpm_04:	cmp	al,'\'
		jne	read_cpm_05
		mov	path_flag,1
read_cpm_05:	stosb
		mov	ah,al
		loop	read_cpm_02

read_cpm_03:	dec	si
		mov	cpm_arg_offset,si
		mov	file_name_end,di

		dec	si
		mov	cx,4
read_cpm_08:	std
		lodsb
		cmp	al,'.'
		je	read_cpm_09
		loop	read_cpm_08

		mov	di,file_name_end
		mov	si,offset cpm_str
		cld
		movsw
		movsw
		movsb

		mov	ax,3d00h
		mov	dx,offset cpm_file_name
;		call	disp_file_name
		int	21h
		jc	read_cpm_10
		jmp	read_cpm_6

read_cpm_10:	mov	di,file_name_end
		mov	si,offset com_str
		cld
		movsw
		movsw
read_cpm_09:
		mov	al,0
		stosb
		mov	ax,3d00h
		mov	dx,offset cpm_file_name
;		call	disp_file_name
		int	21h
		jc	read_cpm_11
		jmp	read_cpm_6
read_cpm_11:
		cmp	env_flag,1
		je	read_cpm_111
		cmp	drv_flag,1
		je	read_cpm_111
		cmp	path_flag,1
		je	read_cpm_111
		jmp	read_cpm_12
read_cpm_111:
		jmp	cpm_open_error

read_cpm_12:	mov	env_flag,1
		mov	si,offset env_str
		mov	di,offset cpm_file_name
		cld
		lodsb
		and	al,al
		jz	read_cpm_111
		stosb
		mov	cx,127
read_cpm_1:
		lodsb
		and	al,al
		jz	read_cpm_2
		stosb
		loop	read_cpm_1
		jmp	too_long_path
read_cpm_2:
		mov	al,'\'
		stosb
read_cpm_3:
		jmp	read_cpm_0

read_cpm_6:
		mov	cpm_file_handle,ax
		mov	bx,ax
		mov	ah,3fh
		mov	cx,0fe00h
		mov	ds,z80_seg
		mov	dx,100h
		int	21h
		jnc	read_cpm_7
		jmp	cpm_read_error
read_cpm_7:
		and	ax,ax
		jnz	read_cpm_71
		jmp	cpm_read_error
read_cpm_71:
		cmp	ax,0fe00h
		jne	read_cpm_8
		jmp	too_large_com
read_cpm_8:
		mov	ax,cs
		mov	ds,ax
		mov	ah,3eh
		mov	bx,cpm_file_handle
		int	21h
		jnc	read_cpm_exit
		jmp	cpm_close_error
read_cpm_exit:
		ret
;================================================
setup_cpm_area:
		mov	es,z80_seg
		mov	di,0
		mov	cx,80h
		mov	ax,0
		rep	stosw

		mov	si,cpm_arg_offset
		mov	di,80h
		mov	cl,ds:[di]
		mov	ch,0
		add	cx,81h
		sub	cx,si
		jbe	set_cpm_11

		mov	al,cl
		cld
		stosb
		and	cx,7fh

set_cpm_loop:	lodsb
		cmp	al,60h
		jbe	set_cpm_10
		cmp	al,7bh
		jae	set_cpm_10
		sub	al,20h
set_cpm_10:	stosb
		loop	set_cpm_loop
		mov	al,0
		stosb
set_cpm_11:
		mov	si,cpm_arg_offset

		mov	di,5ch
		mov	ax,2901h
		int	21h

		mov	di,6ch
		mov	ax,2901h
		int	21h

		mov	ax,cs
		mov	ds,ax
		mov	es,z80_seg
		mov	si,OFFSET CPM_zero_page_0
		mov	di,0
		movsw
		movsw
		movsw
		movsw

		mov	di,CPM_BDOS
		mov	si,offset CPM_BDOS_code
		mov	cx,CPM_BDOS_end - CPM_BDOS_code
		rep	movsb

		mov	di,CPM_BIOS
		mov	si,offset CPM_BIOS_code
		mov	cx,CPM_BIOS_end - CPM_BIOS_code
		rep	movsb

		mov	es:[10h],es
		mov	es:[14h],cs
		mov	ax,EM_SEG
		mov	es:[12h],ax

		ret
;------------------------------------------------
;	CPM	memory image

CPM_BDOS	equ	0ff84h
CPM_BIOS	equ	0ff88h

JP80		macro	addr
		db	0c3h		;JP instruction for Z80
		dw	addr - CPM_BIOS_code + CPM_BIOS
		endm

BIOS80		macro	bios_code
		db	03eh,bios_code	;LD A,bios_code
		db	0edh,0fdh	;RETEM
		endm

CPM_zero_page_0	db	0c3h
		dw	CPM_BIOS+3
io_byte		db	0
login_disk	db	2
jmp_bdos	db	0c3h
		dw	CPM_BDOS

CPM_BDOS_code:
		db	03eh,00		;LD A,0
		db	0edh,0fdh	;RETEM
CPM_BDOS_end:

CPM_BIOS_code:
		JP80	bios80_1
		JP80	bios80_1
		JP80	bios80_2
		JP80	bios80_3
		JP80	bios80_4
		JP80	bios80_5
		JP80	bios80_6
		JP80	bios80_7
		JP80	bios80_8
		JP80	bios80_9
		JP80	bios80_10
		JP80	bios80_11
		JP80	bios80_12
		JP80	bios80_13
		JP80	bios80_14
		JP80	bios80_15
		JP80	bios80_16

bios80_1:	BIOS80	1
bios80_2:	BIOS80	2
bios80_3:	BIOS80	3
bios80_4:	BIOS80	4
bios80_5:	BIOS80	5
bios80_6:	BIOS80	6
bios80_7:	BIOS80	7
bios80_8:	BIOS80	8
bios80_9:	BIOS80	9
bios80_10:	BIOS80	10
bios80_11:	BIOS80	11
bios80_12:	BIOS80	12
bios80_13:	BIOS80	13
bios80_14:	BIOS80	14
bios80_15:	BIOS80	15
bios80_16:	BIOS80	16

CPM_bios_end:
;======================================
dsphex4:	push	dx
		mov	dx,ax
		mov	al,ah
		call	dsphex2
		mov	ax,dx
		pop	dx

dsphex2:	push	dx
		mov	dl,al
		shr	al,1
		shr	al,1
		shr	al,1
		shr	al,1
		call	dsphex1
		mov	al,dl
		pop	dx

dsphex1:	push	dx
		and	al,0fh
		cmp	al,9
		jbe	dsphex1_1
		add	al,'@'-'9'
dsphex1_1:	add	al,'0'
		mov	dl,al
		mov	ah,2
		int	21h
		pop	dx
		ret
;======================================
disp_file_name:
		push	ax
		push	cx
		push	dx
		push	si
		mov	si,dx
		cld
		mov	cx,128
disp_file_name_loop:
		lodsb
		cmp	al,0
		je	disp_file_name_exit
		mov	dl,al
		mov	ah,2
		int	21h
		loop	disp_file_name_loop
disp_file_name_exit:
		mov	dl,0dh
		mov	ah,02
		int	21h
		mov	dl,0ah
		mov	ah,2
		int	21h
		pop	si
		pop	dx
		pop	cx
		pop	ax
		ret
;======================================
	end	start
