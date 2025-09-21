;	Z80 instruction executor for x86 Rev. 1.11
;
;	Copyright (C) 2025 by Gazelle
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

;2025/5/18 Rev. 1.00 Initial release
;2025/9/21 Rev. 1.10 8080 emulation mode implemented
;2025/9/21 Rev. 1.11 fix stack pointer issue

		page 0,150
		.model	small
		.code
;		.186

		assume	ds:nothing,es:nothing,ss:nothing

;-------------------------------------
;temp	equ	cx
temp	equ	dx
;-------------------------------------
;;
;		Entry point : nnnn:0e0h (far call)
;;		DS must point base of Z80 instruction code area
;
;		SI have the address where the code here under was fetched.
;		BP have the return code corresponding to the code here under.
;;
;		return code : DI
;
;		0	RETEM
;		1	HLT
;		2	OUT (n),A
;		3	IN  A,(n)
;		4	I/O instruction  RETI  RETN
;		5	undefined code (2 bytes)
;		6	undefined code (4 bytes)
;
;		register assign
;
;		A    : al
;		flag : ah
;		B    : ch
;		C    : cl
;		D    : dh
;		E    : dl
;		H    : bh
;		L    : bl
;
;		PC   : set vector #ff (000:03fcg)
;		SP   : bp
;
;		BC' [00F0]
;		DE' [00F2]
;		HL' [00F4]
;		AF' [00F6]
;		IX  [00F8]
;		IY  [00FA]
;		I   [00FC]
;		R   [00FD]
;		in the segment this emulation module loaded.
;
;-----------------------------------------------
code_EDFD	equ	0
code_HLT	equ	1
code_OUT	equ	2
code_IN		equ	3
code_IO		equ	4
code_undef2	equ	5
code_undef4	equ	6

ifidni		temp,<dx>
temp_h		equ	dh
temp_l		equ	dl
BC		equ	cx
DE		equ	bp
elseifidni	temp,<cx>
temp_h		equ	ch
temp_l		equ	cl
BC		equ	bp
DE		equ	dx
endif
;-----------------------------------------------
ret_reg		equ	di
entry_SP	equ	bp

int_no		equ	0ffh
save_temp	equ	bp
PC80		equ	si
SP80		equ	di
AF		equ	ax
HL		equ	bx

B		equ	ch
C_reg		equ	cl
D		equ	dh
E		equ	dl
H		equ	bh
L		equ	bl
M		equ	byte ptr ds:[HL]
A		equ	al

s_flag		equ	10000000b
z_flag		equ	01000000b
h_flag		equ	00010000b
p_flag		equ	00000100b
v_flag		equ	00000100b ;(=p_flag)
n_flag		equ	00000010b
c_flag		equ	00000001b

;alt_BC		equ	word ptr ds:[0fff0h]
;alt_DE		equ	word ptr ds:[0fff2h]
;alt_HL		equ	word ptr ds:[0fff4h]
;alt_AF		equ	word ptr ds:[0fff6h]
;IX		equ	word ptr ds:[0fff8h]
;XL		equ	byte ptr ds:[0fff8h]
;XH		equ	byte ptr ds:[0fff9h]
;IY		equ	word ptr ds:[0fffah]
;YL		equ	byte ptr ds:[0fffah]
;YH		equ	byte ptr ds:[0fffbh]
;I		equ	byte ptr ds:[0fffch]
;R		equ	byte ptr ds:[0fffdh]

alt_BC		equ	word ptr cs:[00f0h]
alt_DE		equ	word ptr cs:[00f2h]
alt_HL		equ	word ptr cs:[00f4h]
alt_AF		equ	word ptr cs:[00f6h]
IX		equ	word ptr cs:[00f8h]
XL		equ	byte ptr cs:[00f8h]
XH		equ	byte ptr cs:[00f9h]
IY		equ	word ptr cs:[00fah]
YL		equ	byte ptr cs:[00fah]
YH		equ	byte ptr cs:[00fbh]
I		equ	byte ptr cs:[00fch]
R		equ	byte ptr cs:[00fdh]

org_CB		equ	020h
org_CBX		equ	040h
org_DD		equ	060h
org_FD		equ	080h
org_ED		equ	0a0h

;======================================
		org	0c0h
entry_c0:
		xor	ret_reg,ret_reg
		mov	es,ret_reg
		mov	si,es:[int_no*4]
		mov	ret_reg,ds
		mov	es,ret_reg
		mov	SP80,entry_SP
		mov	save_temp,temp
		cld
		mov	temp_h,ds:[PC80]
		mov	temp_l,0
		inc	PC80
		jmp	temp

		org	0e0h
entry:
		mov	SP80,entry_SP
		mov	save_temp,temp
		cld
		mov	temp_h,ds:[PC80]
		mov	temp_l,0
		inc	PC80
		jmp	temp

;======================================
fetch1		macro
		mov	temp_h,ds:[PC80]
		inc	PC80
		jmp	temp
endm

fetch2		macro
		inc	PC80
		mov	temp_h,ds:[PC80]
		inc	PC80
		jmp	temp
endm

fetch3		macro
		mov	temp_h,ds:[PC80+2]
		add	PC80,3
		jmp	temp
endm

;======= M1 cycle ===============================

;--- LD	reg16,imm16
LXI		macro	dst
		mov	dst,ds:[PC80]
		fetch3
endm

;--- LD	reg8,imm8
MVI		macro	dst
ifidni	dst,temp_h
		mov	temp,save_temp
		mov	dst,ds:[PC80]
		mov	save_temp,temp
		mov	temp_l,0
elseifidni	dst,temp_l
		mov	temp,save_temp
		mov	dst,ds:[PC80]
		mov	save_temp,temp
		mov	temp_l,0
else
		mov	dst,ds:[PC80]
endif
		fetch2
endm

;--- INC reg16
INX		macro	src
		inc	src
		fetch1
endm

;--- DEC reg16
DCX		macro	src
		dec	src
		fetch1
endm

;--- INC reg8
INR		macro	src

		sahf

ifidni		src,temp_h

		mov	temp,save_temp
		inc	src
		mov	save_temp,temp
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		inc	src
		mov	save_temp,temp
		mov	temp_l,0
else
		inc	src
endif
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		fetch1
@@:		and	ah,not (n_flag)
		or	ah,v_flag
		fetch1
endm

;--- DEC reg8
DCR		macro	src

		sahf

ifidni		src,temp_h

		mov	temp,save_temp
		dec	src
		mov	save_temp,temp
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		dec	src
		mov	save_temp,temp
		mov	temp_l,0
else
		dec	src
endif
		lahf
		jo	@f
		and	ah,not (v_flag)
;		or	ah,n_flag
		fetch1
@@:		or	ah,(v_flag or n_flag)
		fetch1
endm

;--- ADD HL,reg16
ADDHL		macro	src
		ror	ah,1
		add	HL,src
		rcl	ah,1
		and	ah,not (n_flag)
		fetch1
endm

;--- JR cc,n
JR		macro	cc
ifnb	<cc>
		sahf
		j&cc	@f
		fetch2
@@:
endif
		mov	temp,ax
		lodsb
		cbw
		add	PC80,ax
		mov	ax,temp
		mov	temp_l,0
		fetch1
endm

;--- LD ??,??
LD		macro	dst,src

ifidni		dst,src

elseifidni	dst,temp_h

		mov	temp,save_temp
		mov	dst,src
		mov	save_temp,temp
		mov	temp_l,0

elseifidni	dst,temp_l

		mov	temp,save_temp
		mov	dst,src
		mov	save_temp,temp
		mov	temp_l,0

elseifidni	src,temp_h

		mov	temp,save_temp
		mov	dst,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		mov	dst,src
		mov	temp_l,0
else
		mov	dst,src
endif
		fetch1
endm

;--- ADD A,reg8
ADD8	macro	src
ifidni	src,temp_h

		mov	temp,save_temp
		add	A,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		add	A,src
		mov	temp_l,0
else
		add	A,src
endif
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		fetch1
endm

;--- ADC A,reg8
ADC8		macro	src

		sahf

ifidni		src,temp_h

		mov	temp,save_temp
		adc	A,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		adc	A,src
		mov	temp_l,0
else
		adc	A,src
endif
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		fetch1
endm

;---  SUB reg8
SUB8	macro	src
ifidni		src,temp_h

		mov	temp,save_temp
		sub	A,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		sub	A,src
		mov	temp_l,0
else
		sub	A,src
endif
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		fetch1
@@:		or	ah,(v_flag or n_flag)
		fetch1
endm

;---  SBC A,reg8
SBC8	macro	src

		sahf

ifidni		src,temp_h

		mov	temp,save_temp
		sbb	A,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		sbb	A,src
		mov	temp_l,0
else
		sbb	A,src
endif
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		fetch1
@@:		or	ah,(v_flag or n_flag)
		fetch1
endm

;--- AND reg8
ANA	macro	src
ifidni		src,temp_h

		mov	temp,save_temp
		and	A,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		and	A,src
		mov	temp_l,0
else
		and	A,src
endif
		lahf
		and	ah,not(n_flag or c_flag)
		or	ah,h_flag
		fetch1
endm

;---  OR reg8
ORA	macro	src
ifidni		src,temp_h

		mov	temp,save_temp
		or	A,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		or	A,src
		mov	temp_l,0
else
		or	A,src
endif
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		fetch1
endm

;--- XOR reg8
XRA	macro	src
ifidni		src,temp_h

		mov	temp,save_temp
		xor	A,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		xor	A,src
		mov	temp_l,0
else
		xor	A,src
endif
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		fetch1
endm

;--- CP reg8
CPA	macro	src
ifidni		src,temp_h

		mov	temp,save_temp
		cmp	A,src
		mov	temp_l,0

elseifidni	src,temp_l

		mov	temp,save_temp
		cmp	A,src
		mov	temp_l,0
else
		cmp	A,src
endif
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		fetch1
@@:		or	ah,(v_flag or n_flag)
		fetch1
endm

;--- CALL cc,nn
CALL80		macro	cc
		add	PC80,2
ifnb		<cc>
		sahf
		j&cc	@f
		fetch1
@@:
endif
		sub	SP80,2
		mov	ds:[SP80],PC80
		mov	PC80,ds:[PC80-2]
		fetch1
endm

;--- JP cc,nn
JP80		macro	cc
ifnb		<cc>
		sahf
		j&cc	@f
		fetch3
@@:
endif
		mov	PC80,ds:[PC80]
		fetch1
endm

;--- RET cc
RET80		macro	cc
ifnb		<cc>
		sahf
		j&cc	@f
		fetch1
@@:
endif
		mov	PC80,ds:[SP80]
		add	SP80,2
		fetch1
endm

;--- RST n
RST		macro	nn
		sub	SP80,2
		mov	ds:[SP80],PC80
		mov	PC80,nn
		fetch1
endm

;---  PUSH reg16
PUSH8		macro	src
		sub	SP80,2
ifidni		src,AF
		xchg	ah,al
		mov	ds:[SP80],src
		xchg	ah,al
else
		mov	ds:[SP80],src
endif
		fetch1
endm

;--- POP reg16
POP8		macro	dst
		mov	dst,ds:[SP80]
ifidni		dst,AF
		xchg	ah,al
endif
		add	SP80,2
		fetch1
endm

;======================================
op2	=	0

M1	macro	nn
	rept	nn - op2
		org	op2 * 100h
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,dode_undef2
		retf
		op2	= op2 + 1
	endm
	op2	= nn + 1
	org	nn * 100h
endm

M1	00				;NOP
no_op:
		fetch1
exe_msg1	db	0dh,0ah,'Z80 code executor',0dh,0ah,24h

M1	01				;LD	BC,nn
		LXI	BC

M1	02				;LD	(BC),A
ifidni		BC,<save_temp>
		mov	ds:[BC],A
		fetch1
else
		mov	temp,save_temp
		mov	save_temp,BC
		mov	ds:[save_temp],A
		mov	save_temp,temp
		mov	temp_l,0
		fetch1
endif

M1	03				;INC	BC
		INX	BC

exe_msg2	db	'Copyright (c) Gazelle',24h

M1	04				;INC	B
		INR	B

M1	05				;DEC	B
		DCR	B

M1	06				;LD	B,n
		MVI	B

M1	07				;RLCA
		sahf
		rol	A,1
		lahf
		and	ah,not(h_flag or n_flag)
		fetch1

M1	08				;EX	AF,AF
		xchg	ax,alt_AF
		fetch1

M1	09				;ADD	HL,BC
		ADDHL	BC

M1	0AH				;LD	A,(BC)
ifidni		BC,<save_temp>
		mov	A,ds:[BC]
		fetch1
else
		mov	temp,save_temp
		mov	save_temp,BC
		mov	A,ds:[save_temp]
		mov	save_temp,temp
		mov	temp_l,0
		fetch1
endif

M1	0BH				;DEC	BC
		DCX	BC

exe_msg4	db	'https://github.com/',24h

M1	0CH				;INC	C_reg
		INR	C_reg

M1	0DH				;DEC	C_reg
		DCR	C_reg

M1	0EH				;LD	C,n
		MVI	C_reg

M1	0FH				;RRCA
		sahf
		ror	A,1
		lahf
		and	ah,not(h_flag or n_flag)
		fetch1

M1	10H				;DJNZ	n
ifidni		temp,<cx>
		mov	temp,save_temp
		dec	B
		mov	save_temp,temp
		jnz	@f
		mov	temp_l,0
		fetch2
else
		dec	B
		jnz	@f
		fetch2
endif
@@:		mov	temp,ax
		lodsb
		cbw
		add	PC80,ax
		mov	ax,temp
		mov	temp_l,0
		fetch1

M1	11h				;LD	DE,nn
		LXI	DE

M1	12H				;LD	(DE),A
ifidni		DE,<save_temp>
		mov	ds:[DE],A
		fetch1
else
		mov	temp,save_temp
		mov	save_temp,DE
		mov	ds:[save_temp],A
		mov	save_temp,temp
		mov	temp_l,0
		fetch1
endif

M1	13H				;INC	DE
		INX	DE

exe_msg5	db	'Gazelle8087',0dh,0ah,24h

M1	14H				;INC	D
		INR	D

M1	15H				;DEC	D
		DCR	D

M1	16H				;LD	D,n
		MVI	D

M1	17H				;RLA
		sahf
		rcl	A,1
		lahf
		and	ah,not(h_flag or n_flag)
		fetch1

M1	18H				;JR	n
		JR

M1	19H				;ADD	HL,DE
		ADDHL	DE

M1	1AH				;LD	A,(DE)
ifidni		DE,<save_temp>
		mov	A,ds:[DE]
		fetch1
else
		mov	temp,save_temp
		mov	save_temp,DE
		mov	A,ds:[save_temp]
		mov	save_temp,temp
		mov	temp_l,0
		fetch1
endif

M1	1BH				;DEC	DE
		DCX	DE

exe_msg3	db	' 2025',0dh,0ah,24h

M1	1CH				;INC	E
		INR	E

M1	1DH				;DEC	E
		DCR	E

M1	1EH				;LD	E,n
		MVI	E

M1	1FH				;RRA
		sahf
		rcr	A,1
		lahf
		and	ah,not(h_flag or n_flag)
		fetch1

M1	20H
		JR	NZ

M1	21H				;LD	HL,nn
		LXI	HL

M1	22H				;LD	(nn),HL
		mov	temp,save_temp
		mov	save_temp,ds:[PC80]
		mov	ds:[save_temp],HL
		mov	save_temp,temp
		mov	temp_l,0
		fetch3

M1	23H				;INC	HL
		INX	HL

M1	24H				;INC	H
		INR	H

M1	25H				;DEC	H
		DCR	H

M1	26H				;LD	H,n
		MVI	H

M1	27H				;DAA	*****
		test	ah,n_flag
		jnz	@f
		sahf
		daa
		lahf
		and	ah,not (n_flag)
		fetch1
@@:		sahf
		das
		lahf
		fetch1

M1	28H
		JR	Z

M1	29H				;ADD	HL,HL
		ADDHL	HL

M1	2AH				;LD	HL,(nn)
		mov	HL,ds:[PC80]
		mov	HL,ds:[HL]
		fetch3

M1	2BH				;DEC	HL
		DCX	HL

M1	2CH				;INC	L
		INR	L

M1	2DH				;DEC	L
		DCR	L

M1	2EH				;LD	L,n
		MVI	L

M1	2FH				;CPL	complement A
		not	A
		or	ah,(h_flag or n_flag)
		fetch1

M1	30H
		JR	NC

M1	31H				;LD	SP,nn
		LXI	SP80

M1	32H				;LD	(nn),A
		mov	temp,save_temp
		mov	save_temp,ds:[PC80]
		mov	ds:[save_temp],A
		mov	save_temp,temp
		mov	temp_l,0
		fetch3

M1	33H				;INC	SP
		INX	SP80

M1	34H				;INC	(HL)
		INR	M

M1	35H				;DEC	M
		DCR	M

M1	36H				;LD	(HL),n
		mov	temp_h,ds:[PC80]
		mov	ds:[HL],temp_h
		fetch2

M1	37H				;SCF	set carry flag
		or	ah,c_flag
		and	ah,not(h_flag or n_flag)
		fetch1

M1	38H
		JR	C

M1	39H				;ADD	HL,SP
		ADDHL	SP80

M1	3AH				;LD	A,(nn)
		mov	temp,save_temp
		mov	save_temp,ds:[PC80]
		mov	A,ds:[save_temp]
		mov	save_temp,temp
		mov	temp_l,0
		fetch3

M1	3BH				;DEC	SP
		DCX	SP80

M1	3CH				;INC	A
		INR	A

M1	3DH				;DEC	A
		DCR	A

M1	3EH				;LD	A,n
		lodsb
		fetch1

M1	3FH				;CCF	complement carry flag
		xor	ah,c_flag
		and	ah,not n_flag
		fetch1
;--------------------------------------
M1	40H
		LD	B,B
M1	41H
		LD	B,C_reg
M1	42H
		LD	B,D
M1	43H
		LD	B,E
M1	44H
		LD	B,H
M1	45H
		LD	B,L
M1	46H
		LD	B,M
M1	47H
		LD	B,A

M1	48H
		LD	C_reg,B
M1	49H
		LD	C_reg,C_reg
M1	4AH
		LD	C_reg,D
M1	4BH
		LD	C_reg,E
M1	4CH
		LD	C_reg,H
M1	4DH
		LD	C_reg,L
M1	4EH
		LD	C_reg,M
M1	4FH
		LD	C_reg,A

M1	50H
		LD	D,B
M1	51H
		LD	D,C_reg
M1	52H
		LD	D,D
M1	53H
		LD	D,E
M1	54H
		LD	D,H
M1	55H
		LD	D,L
M1	56H
		LD	D,M
M1	57H
		LD	D,A

M1	58H
		LD	E,B
M1	59H
		LD	E,C_reg
M1	5AH
		LD	E,D
M1	5BH
		LD	E,E
M1	5CH
		LD	E,H
M1	5DH
		LD	E,L
M1	5EH
		LD	E,M
M1	5FH
		LD	E,A

M1	60H
		LD	H,B
M1	61H
		LD	H,C_reg
M1	62H
		LD	H,D
M1	63H
		LD	H,E
M1	64H
		LD	H,H
M1	65H
		LD	H,L
M1	66H
		LD	H,M
M1	67H
		LD	H,A

M1	68H
		LD	L,B
M1	69H
		LD	L,C_reg
M1	6AH
		LD	L,D
M1	6BH
		LD	L,E
M1	6CH
		LD	L,H
M1	6DH
		LD	L,L
M1	6EH
		LD	L,M
M1	6FH
		LD	L,A

M1	70H
		LD	M,B
M1	71H
		LD	M,C_reg
M1	72H
		LD	M,D
M1	73H
		LD	M,E
M1	74H
		LD	M,H
M1	75H
		LD	M,L
M1	76H				;HLT
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_HLT
		retf
M1	77H
		LD	M,A

M1	78H
		LD	A,B
M1	79H
		LD	A,C_reg
M1	7AH
		LD	A,D
M1	7BH
		LD	A,E
M1	7CH
		LD	A,H
M1	7DH
		LD	A,L
M1	7EH
		LD	A,M
M1	7FH
		LD	A,A
;--------------------------------------
M1	80H
		ADD8	B
M1	81H
		ADD8	C_reg
M1	82H
		ADD8	D
M1	83H
		ADD8	E
M1	84H
		ADD8	H
M1	85H
		ADD8	L
M1	86H
		ADD8	M
M1	87H
		ADD8	A

M1	88H
		ADC8	B
M1	89H
		ADC8	C_reg
M1	8AH
		ADC8	D
M1	8BH
		ADC8	E
M1	8CH
		ADC8	H
M1	8DH
		ADC8	L
M1	8EH
		ADC8	M
M1	8FH
		ADC8	A

M1	90H
		SUB8	B
M1	91H
		SUB8	C_reg
M1	92H
		SUB8	D
M1	93H
		SUB8	E
M1	94H
		SUB8	H
M1	95H
		SUB8	L
M1	96H
		SUB8	M
M1	97H
		SUB8	A

M1	98H
		SBC8	B
M1	99H
		SBC8	C_reg
M1	9AH
		SBC8	D
M1	9BH
		SBC8	E
M1	9CH
		SBC8	H
M1	9DH
		SBC8	L
M1	9EH
		SBC8	M
M1	9FH
		SBC8	A

M1	0A0H
		ANA	B
M1	0A1H
		ANA	C_reg
M1	0A2H
		ANA	D
M1	0A3H
		ANA	E
M1	0A4H
		ANA	H
M1	0A5H
		ANA	L
M1	0A6H
		ANA	M
M1	0A7H
		ANA	A

M1	0A8H
		XRA	B
M1	0A9H
		XRA	C_reg
M1	0AAH
		XRA	D
M1	0ABH
		XRA	E
M1	0ACH
		XRA	H
M1	0ADH
		XRA	L
M1	0AEH
		XRA	M
M1	0AFH
		XRA	A

M1	0B0H
		ORA	B
M1	0B1H
		ORA	C_reg
M1	0B2H
		ORA	D
M1	0B3H
		ORA	E
M1	0B4H
		ORA	H
M1	0B5H
		ORA	L
M1	0B6H
		ORA	M
M1	0B7H
		ORA	A

M1	0B8H
		CPA	B
M1	0B9H
		CPA	C_reg
M1	0BAH
		CPA	D
M1	0BBH
		CPA	E
M1	0BCH
		CPA	H
M1	0BDH
		CPA	L
M1	0BEH
		CPA	M
M1	0BFH
		CPA	A
;--------------------------
M1	0C0H
		RET80	NZ

M1	0C1H
		POP8	BC

M1	0C2H
		JP80	NZ

M1	0C3H
		JP80

M1	0C4H
		CALL80	NZ

M1	0C5H
		PUSH8	BC

M1	0C6H				;add	A,n
		add	A,ds:[PC80]
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		fetch2
@@:		and	ah,not n_flag
		or	ah,v_flag
		fetch2

M1	0C7H
		RST	00h

M1	0C8H
		RET80	Z

M1	0C9H
		RET80

M1	0CAH
		JP80	Z

M1	0CBH
		mov	temp_h,ds:[PC80]
		inc	PC80
		mov	temp_l,org_CB
		jmp	temp

M1	0CCH
		CALL80	Z

M1	0CDH
		CALL80

M1	0CEH				;ADC	A,n
		sahf
		adc	A,ds:[PC80]
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		fetch2
@@:		and	ah,not n_flag
		or	ah,v_flag
		fetch2

M1	0CFH
		RST	08h

M1	0D0H
		RET80	NC

M1	0D1H
		POP8	DE

M1	0D2H
		JP80	NC

M1	0D3H				;OUT	(n),A
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_OUT
		retf

M1	0D4H
		CALL80	NC

M1	0D5H
		PUSH8	DE

M1	0D6H				;SUB	n
		sub	A,ds:[PC80]
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		fetch2
@@:		or	ah,(v_flag or n_flag)
		fetch2

M1	0D7H
		RST	10h

M1	0D8H
		RET80	C

M1	0D9H
		xchg	BC,alt_BC	;EXX
		xchg	DE,alt_DE
		xchg	HL,alt_HL
		fetch1

M1	0DAH
		JP80	C

M1	0DBH				;IN	A,(n)
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_IN
		retf

M1	0DCH
		CALL80	C

M1	0DDH
		mov	temp_h,ds:[PC80]
		inc	PC80
		mov	temp_l,org_DD
		jmp	temp

M1	0DEH				;SBC	A,n
		sahf
		sbb	A,ds:[PC80]
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		fetch2
@@:		or	ah,(v_flag or n_flag)
		fetch2

M1	0DFH
		RST	18h

M1	0E0H
		RET80	PO

M1	0E1H
		POP8	HL

M1	0E2H
		JP80	PO

M1	0E3H
		xchg	HL,ds:[SP80]	;EX	(SP),HL
		fetch1

M1	0E4H
		CALL80	PO

M1	0E5H
		PUSH8	HL

M1	0E6H				;AND	n
		and	A,ds:[PC80]
		lahf
		and	ah,not(n_flag or c_flag)
		or	ah,h_flag
		fetch2

M1	0E7H
		RST	20h

M1	0E8H
		RET80	PE

M1	0E9H
		mov	PC80,HL		;JP	(HL)
		fetch1

M1	0EAH
		JP80	PE

M1	0EBH
		xchg	DE,HL		;EX	DE,HL
		fetch1

M1	0ECH
		CALL80	PE

M1	0EDH
		mov	temp_h,ds:[PC80]
		inc	PC80
		mov	temp_l,org_ED
		jmp	temp

M1	0EEH				;XOR	n
		xor	A,ds:[PC80]
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		fetch2

M1	0EFH
		RST	28h

M1	0F0H
		RET80	ns		;RET	P

M1	0F1H
		POP8	AF

M1	0F2H
		JP80	ns		;JP	P,nn

M1	0F3H
;		cli			;DI	****
		fetch1

M1	0F4H
		call80	ns		;CALL	P,nn

M1	0F5H
		PUSH8	AF

M1	0F6H				;OR	n
		or	A,ds:[PC80]
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		fetch2

M1	0F7H
		RST	30h

M1	0F8H
		RET80	s		;RET	M

M1	0F9H
		LD	SP80,HL		;LD	SP,HL

M1	0FAH
		JP80	s		;JP	M,nn

M1	0FBH				;EI	****
;		sti
		fetch1

M1	0FCH
		CALL80	s		;CALL	M,nn

M1	0FDH
		mov	temp_h,ds:[PC80]
		inc	PC80
		mov	temp_l,org_FD
		jmp	temp

M1	0FEH				;CP	n
		cmp	A,ds:[PC80]
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		fetch2
@@:		or	ah,(v_flag or n_flag)
		fetch2

M1	0FFH
		RST	38h

;================================================
;================  bit operation  ===============
;================================================
op2	=	0

CB	macro	nn
	rept	nn - op2
		org	org_CB + op2 * 100h
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_undef2
		retf
		op2	= op2 + 1
	endm
	op2	= nn + 1
	org	org_CB + nn * 100h
endm

;--- RLC ---
RLC		macro	src

ifidni		src,M
		mov	temp_l,src
		rol	temp_l,1
		mov	src,temp_l
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	temp_l,temp_l
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h

elseifidni	src,temp_h

		mov	temp,save_temp
		rol	src,1
		mov	save_temp,temp
		lahf
		mov	temp_l,ah
		and	temp_l,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_l

elseifidni	src,temp_l

		mov	temp,save_temp
		rol	src,1
		mov	save_temp,temp
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
else
		rol	src,1
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
endif
		mov	temp_l,0
		fetch1
endm

;--- RRC
RRC		macro	src
ifidni		src,M

		mov	temp_l,src
		ror	temp_l,1
		mov	src,temp_l
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	temp_l,temp_l
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h

elseifidni	src,temp_h

		mov	temp,save_temp
		ror	src,1
		mov	save_temp,temp
		lahf
		mov	temp_l,ah
		and	temp_l,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_l

elseifidni	src,temp_l

		mov	temp,save_temp
		ror	src,1
		mov	save_temp,temp
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
else
		ror	src,1
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
endif
		mov	temp_l,0
		fetch1
endm

;-----  RL  -----
RL		macro	src

		sahf

ifidni		src,M

		mov	temp_l,src
		rcl	temp_l,1
		mov	src,temp_l
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	temp_l,temp_l
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h

elseifidni	src,temp_h

		mov	temp,save_temp
		rcl	src,1
		mov	save_temp,temp
		lahf
		mov	temp_l,ah
		and	temp_l,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_l

elseifidni	src,temp_l

		mov	temp,save_temp
		rcl	src,1
		mov	save_temp,temp
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
else
		rcl	src,1
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
endif
		mov	temp_l,0
		fetch1
endm

;-----  RR -----
RR		macro	src

		sahf

ifidni		src,M

		mov	temp_l,src
		rcr	temp_l,1
		mov	src,temp_l
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	temp_l,temp_l
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h

elseifidni	src,temp_h

		mov	temp,save_temp
		rcr	src,1
		mov	save_temp,temp
		lahf
		mov	temp_l,ah
		and	temp_l,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_l

elseifidni	src,temp_l

		mov	temp,save_temp
		rcr	src,1
		mov	save_temp,temp
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
else
		rcr	src,1
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
endif
		mov	temp_l,0
		fetch1
endm

;-----  SLA  -----
SLA		macro	src

ifidni		src,temp_h

		mov	temp,save_temp
		sal	src,1
		mov	save_temp,temp

elseifidni	src,temp_l

		mov	temp,save_temp
		sal	src,1
		mov	save_temp,temp
else
		sal	src,1
endif
		lahf
		and	ah,not (h_flag or n_flag)
		mov	temp_l,0
		fetch1
endm

;-----  SRA  -----
SRA		macro	src
ifidni		src,temp_h

		mov	temp,save_temp
		sar	src,1
		mov	save_temp,temp

elseifidni	src,temp_l

		mov	temp,save_temp
		sar	src,1
		mov	save_temp,temp
else
		sar	src,1
endif
		lahf
		and	ah,not (h_flag or n_flag)
		mov	temp_l,0
		fetch1
endm

;-----  SLL  -----
SLL		macro	src

		stc

ifidni		src,temp_h

		mov	temp,save_temp
		rcl	src,1
		mov	save_temp,temp
		lahf
		mov	temp_l,ah
		and	temp_l,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_l

elseifidni	src,temp_l

		mov	temp,save_temp
		rcl	src,1
		mov	save_temp,temp
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h

elseifidni	src,M

		mov	temp_l,src
		rcl	temp_l,1
		mov	src,temp_l
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	temp_l,temp_l
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
else
		rcl	temp_l,1
		lahf
		mov	temp_h,ah
		and	temp_h,c_flag
		and	src,src
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,temp_h
endif
		mov	temp_l,0
		fetch1
endm

;-----  SRL  -----
SRL		macro	src
ifidni		src,temp_h

		mov	temp,save_temp
		shr	src,1
		mov	save_temp,temp

elseifidni	src,temp_l

		mov	temp,save_temp
		shr	src,1
		mov	save_temp,temp
else
		shr	src,1
endif
		lahf
		and	ah,not (h_flag or n_flag)
		mov	temp_l,0
		fetch1
endm

;-----  BIT  -----
BIT		macro	n,src
ifidni		src,temp_h

		mov	temp,save_temp
		test	src,1 shl n

elseifidni	src,temp_l

		mov	temp,save_temp
		test	src,1 shl n
else
		test	src,1 shl n
endif
		mov	temp_h,ah
		lahf
		and	temp_h,(s_flag or p_flag or c_flag)
		and	ah,z_flag
		or	temp_h,h_flag
		or	ah,temp_h
		mov	temp_l,0
		fetch1
endm

;-----  RES  -----
RES		macro	n,src
ifidni		src,temp_h

		mov	temp,save_temp
		and	src,not (1 shl n)
		mov	save_temp,temp

elseifidni	src,temp_l

		mov	temp,save_temp
		and	src,not (1 shl n)
		mov	save_temp,temp
else
		and	src,not (1 shl n)
endif
		mov	temp_l,0
		fetch1
endm

;-----  SET  -----
SET		macro	n,src
ifidni		src,temp_h
		mov	temp,save_temp
		or	src,1 shl n
		mov	save_temp,temp
elseifidni	src,temp_l
		mov	temp,save_temp
		or	src,1 shl n
		mov	save_temp,temp
else
		or	src,1 shl n
endif
		mov	temp_l,0
		fetch1
endm

;--------------------------------------
CB	00H
		RLC	B
CB	01H
		RLC	C_reg
CB	02H
		RLC	D
CB	03H
		RLC	E
CB	04H
		RLC	H
CB	05H
		RLC	L
CB	06H
		RLC	M
CB	07H
		RLC	A

CB	08H
		RRC	B
CB	09H
		RRC	C_reg
CB	0aH
		RRC	D
CB	0bH
		RRC	E
CB	0cH
		RRC	H
CB	0dH
		RRC	L
CB	0eH
		RRC	M
CB	0fH
		RRC	A

CB	10H
		RL	B
CB	11H
		RL	C_reg
CB	12H
		RL	D
CB	13H
		RL	E
CB	14H
		RL	H
CB	15H
		RL	L
CB	16H
		RL	M
CB	17H
		RL	A

CB	18H
		RR	B
CB	19H
		RR	C_reg
CB	1aH
		RR	D
CB	1bH
		RR	E
CB	1cH
		RR	H
CB	1dH
		RR	L
CB	1eH
		RR	M
CB	1fH
		RR	A

CB	20H
		SLA	B
CB	21H
		SLA	C_reg
CB	22H
		SLA	D
CB	23H
		SLA	E
CB	24H
		SLA	H
CB	25H
		SLA	L
CB	26H
		SLA	M
CB	27H
		SLA	A

CB	28H
		SRA	B
CB	29H
		SRA	C_reg
CB	2aH
		SRA	D
CB	2bH
		SRA	E
CB	2cH
		SRA	H
CB	2dH
		SRA	L
CB	2eH
		SRA	M
CB	2fH
		SRA	A

CB	30H
		SLL	B
CB	31H
		SLL	C_reg
CB	32H
		SLL	D
CB	33H
		SLL	E
CB	34H
		SLL	H
CB	35H
		SLL	L
CB	36H
		SLL	M
CB	37H
		SLL	A

CB	38H
		SRL	B
CB	39H
		SRL	C_reg
CB	3aH
		SRL	D
CB	3bH
		SRL	E
CB	3cH
		SRL	H
CB	3dH
		SRL	L
CB	3eH
		SRL	M
CB	3fH
		SRL	A
;--------------------------------------
CB	40H
		BIT	0,B
CB	41H
		BIT	0,C_reg
CB	42H
		BIT	0,D
CB	43H
		BIT	0,E
CB	44H
		BIT	0,H
CB	45H
		BIT	0,L
CB	46H
		BIT	0,M
CB	47H
		BIT	0,A

CB	48H
		BIT	1,B
CB	49H
		BIT	1,C_reg
CB	4aH
		BIT	1,D
CB	4bH
		BIT	1,E
CB	4cH
		BIT	1,H
CB	4dH
		BIT	1,L
CB	4eH
		BIT	1,M
CB	4fH
		BIT	1,A

CB	50H
		BIT	2,B
CB	51H
		BIT	2,C_reg
CB	52H
		BIT	2,D
CB	53H
		BIT	2,E
CB	54H
		BIT	2,H
CB	55H
		BIT	2,L
CB	56H
		BIT	2,M
CB	57H
		BIT	2,A

CB	58H
		BIT	3,B
CB	59H
		BIT	3,C_reg
CB	5aH
		BIT	3,D
CB	5bH
		BIT	3,E
CB	5cH
		BIT	3,H
CB	5dH
		BIT	3,L
CB	5eH
		BIT	3,M
CB	5fH
		BIT	3,A

CB	60H
		BIT	4,B
CB	61H
		BIT	4,C_reg
CB	62H
		BIT	4,D
CB	63H
		BIT	4,E
CB	64H
		BIT	4,H
CB	65H
		BIT	4,L
CB	66H
		BIT	4,M
CB	67H
		BIT	4,A

CB	68H
		BIT	5,B
CB	69H
		BIT	5,C_reg
CB	6aH
		BIT	5,D
CB	6bH
		BIT	5,E
CB	6cH
		BIT	5,H
CB	6dH
		BIT	5,L
CB	6eH
		BIT	5,M
CB	6fH
		BIT	5,A

CB	70H
		BIT	6,B
CB	71H
		BIT	6,C_reg
CB	72H
		BIT	6,D
CB	73H
		BIT	6,E
CB	74H
		BIT	6,H
CB	75H
		BIT	6,L
CB	76H
		BIT	6,M
CB	77H
		BIT	6,A

CB	78H
		BIT	7,B
CB	79H
		BIT	7,C_reg
CB	7aH
		BIT	7,D
CB	7bH
		BIT	7,E
CB	7cH
		BIT	7,H
CB	7dH
		BIT	7,L
CB	7eH
		BIT	7,M
CB	7fH
		BIT	7,A
;--------------------------------------
CB	80H
		RES	0,B
CB	81H
		RES	0,C_reg
CB	82H
		RES	0,D
CB	83H
		RES	0,E
CB	84H
		RES	0,H
CB	85H
		RES	0,L
CB	86H
		RES	0,M
CB	87H
		RES	0,A

CB	88H
		RES	1,B
CB	89H
		RES	1,C_reg
CB	8aH
		RES	1,D
CB	8bH
		RES	1,E
CB	8cH
		RES	1,H
CB	8dH
		RES	1,L
CB	8eH
		RES	1,M
CB	8fH
		RES	1,A

CB	90H
		RES	2,B
CB	91H
		RES	2,C_reg
CB	92H
		RES	2,D
CB	93H
		RES	2,E
CB	94H
		RES	2,H
CB	95H
		RES	2,L
CB	96H
		RES	2,M
CB	97H
		RES	2,A

CB	98H
		RES	3,B
CB	99H
		RES	3,C_reg
CB	9aH
		RES	3,D
CB	9bH
		RES	3,E
CB	9cH
		RES	3,H
CB	9dH
		RES	3,L
CB	9eH
		RES	3,M
CB	9fH
		RES	3,A

CB	0a0H
		RES	4,B
CB	0a1H
		RES	4,C_reg
CB	0a2H
		RES	4,D
CB	0a3H
		RES	4,E
CB	0a4H
		RES	4,H
CB	0a5H
		RES	4,L
CB	0a6H
		RES	4,M
CB	0a7H
		RES	4,A

CB	0a8H
		RES	5,B
CB	0a9H
		RES	5,C_reg
CB	0aaH
		RES	5,D
CB	0abH
		RES	5,E
CB	0acH
		RES	5,H
CB	0adH
		RES	5,L
CB	0aeH
		RES	5,M
CB	0afH
		RES	5,A

CB	0b0H
		RES	6,B
CB	0b1H
		RES	6,C_reg
CB	0b2H
		RES	6,D
CB	0b3H
		RES	6,E
CB	0b4H
		RES	6,H
CB	0b5H
		RES	6,L
CB	0b6H
		RES	6,M
CB	0b7H
		RES	6,A

CB	0b8H
		RES	7,B
CB	0b9H
		RES	7,C_reg
CB	0baH
		RES	7,D
CB	0bbH
		RES	7,E
CB	0bcH
		RES	7,H
CB	0bdH
		RES	7,L
CB	0beH
		RES	7,M
CB	0bfH
		RES	7,A
;--------------------------------------
CB	0c0H
		SET	0,B
CB	0c1H
		SET	0,C_reg
CB	0c2H
		SET	0,D
CB	0c3H
		SET	0,E
CB	0c4H
		SET	0,H
CB	0c5H
		SET	0,L
CB	0c6H
		SET	0,M
CB	0c7H
		SET	0,A

CB	0c8H
		SET	1,B
CB	0c9H
		SET	1,C_reg
CB	0caH
		SET	1,D
CB	0CBH
		SET	1,E
CB	0ccH
		SET	1,H
CB	0cdH
		SET	1,L
CB	0ceH
		SET	1,M
CB	0cfH
		SET	1,A

CB	0d0H
		SET	2,B
CB	0d1H
		SET	2,C_reg
CB	0d2H
		SET	2,D
CB	0d3H
		SET	2,E
CB	0d4H
		SET	2,H
CB	0d5H
		SET	2,L
CB	0d6H
		SET	2,M
CB	0d7H
		SET	2,A

CB	0d8H
		SET	3,B
CB	0d9H
		SET	3,C_reg
CB	0daH
		SET	3,D
CB	0dbH
		SET	3,E
CB	0dcH
		SET	3,H
CB	0ddH
		SET	3,L
CB	0deH
		SET	3,M
CB	0dfH
		SET	3,A

CB	0e0H
		SET	4,B
CB	0e1H
		SET	4,C_reg
CB	0e2H
		SET	4,D
CB	0e3H
		SET	4,E
CB	0e4H
		SET	4,H
CB	0e5H
		SET	4,L
CB	0e6H
		SET	4,M
CB	0e7H
		SET	4,A

CB	0e8H
		SET	5,B
CB	0e9H
		SET	5,C_reg
CB	0eaH
		SET	5,D
CB	0ebH
		SET	5,E
CB	0ecH
		SET	5,H
CB	0edH
		SET	5,L
CB	0eeH
		SET	5,M
CB	0efH
		SET	5,A

CB	0f0H
		SET	6,B
CB	0f1H
		SET	6,C_reg
CB	0f2H
		SET	6,D
CB	0f3H
		SET	6,E
CB	0f4H
		SET	6,H
CB	0f5H
		SET	6,L
CB	0f6H
		SET	6,M
CB	0f7H
		SET	6,A

CB	0f8H
		SET	7,B
CB	0f9H
		SET	7,C_reg
CB	0faH
		SET	7,D
CB	0fbH
		SET	7,E
CB	0fcH
		SET	7,H
CB	0fdH
		SET	7,L
CB	0feH
		SET	7,M
CB	0ffH
		SET	7,A

;================================================
;=============  bit op width (X+d)  =============
;================================================

op2	=	0

CBX	macro	nn
	rept	nn - op2
		org	org_CBX + op2 * 100h
		add	sp,2
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_undef4
		retf
	op2	= op2 + 1
	endm
	op2	= nn + 1
		org	org_CBX + nn * 100h
endm

CBX	06H			;RLC (IX+d)
		mov	temp,bx
		pop	bx
		rol	byte ptr ds:[bx],1
		lahf
		mov	bl,byte ptr ds:[bx]
		mov	bh,ah
		and	bh,c_flag
		and	bl,bl
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,bh
		mov	bx,temp
		mov	temp_l,0
		fetch1

CBX	0eH			;RRC (IX+d)
		mov	temp,bx
		pop	bx
		ror	byte ptr ds:[bx],1
		lahf
		mov	bl,byte ptr ds:[bx]
		mov	bh,ah
		and	bh,c_flag
		and	bl,bl
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,bh
		mov	bx,temp
		mov	temp_l,0
		fetch1

CBX	16H			;RL (IX+d)
		mov	temp,bx
		pop	bx
		sahf
		rcl	byte ptr ds:[bx],1
		lahf
		mov	bl,byte ptr ds:[bx]
		mov	bh,ah
		and	bh,c_flag
		and	bl,bl
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,bh
		mov	bx,temp
		mov	temp_l,0
		fetch1

CBX	1eH			;RR (IX+d)
		mov	temp,bx
		pop	bx
		sahf
		rcr	byte ptr ds:[bx],1
		lahf
		mov	bl,byte ptr ds:[bx]
		mov	bh,ah
		and	bh,c_flag
		and	bl,bl
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,bh
		mov	bx,temp
		mov	temp_l,0
		fetch1

CBX	26H			;SLA (IX+d)
		mov	temp,bx
		pop	bx
		sal	byte ptr ds:[bx],1
		mov	bx,temp
		lahf
		and	ah,not (h_flag or n_flag)
		mov	temp_l,0
		fetch1

CBX	2eH			;SRA (IX+d)
		mov	temp,bx
		pop	bx
		sar	byte ptr ds:[bx],1
		mov	bx,temp
		lahf
		and	ah,not (h_flag or n_flag)
		mov	temp_l,0
		fetch1

CBX	36H			;SLL (IX+d)
		mov	temp,bx
		pop	bx
		stc
		rcl	byte ptr ds:[bx],1
		lahf
		mov	bl,byte ptr ds:[bx]
		mov	bh,ah
		and	bh,c_flag
		and	bl,bl
		lahf
		and	ah,not (h_flag or n_flag or c_flag)
		or	ah,bh
		mov	bx,temp
		mov	temp_l,0
		fetch1

CBX	3eH			;SRL (IX+d)
		mov	temp,bx
		pop	bx
		shr	byte ptr ds:[bx],1
		mov	bx,temp
		lahf
		and	ah,not (h_flag or n_flag)
		mov	temp_l,0
		fetch1

;-----------------------------------
BITX	macro	n

		mov	temp,save_temp
		pop	save_temp
		test	byte ptr ds:[save_temp],1 shl n
		mov	save_temp,temp
		mov	temp_h,ah
		lahf
		and	temp_h,(s_flag or p_flag or c_flag)
		or	temp_h,h_flag
		and	ah,z_flag
		or	ah,temp_h
		mov	temp_l,0
		fetch1
endm

CBX	46H
		BITX	0
CBX	4EH
		BITX	1
CBX	56H
		BITX	2
CBX	5EH
		BITX	3
CBX	66H
		BITX	4
CBX	6EH
		BITX	5
CBX	76H
		BITX	6
CBX	7EH
		BITX	7

;-----------------------------------
RESX	macro	n
		mov	temp,save_temp
		pop	save_temp
		and	byte ptr ds:[save_temp],not(1 shl n)
		mov	save_temp,temp
		mov	temp_l,0
		fetch1
endm

CBX	86H
		RESX	0
CBX	8eH
		RESX	1
CBX	96H
		RESX	2
CBX	9eH
		RESX	3
CBX	0a6H
		RESX	4
CBX	0aeH
		RESX	5
CBX	0b6H
		RESX	6
CBX	0beH
		RESX	7

;----------------------------------
SETX	macro	n
		mov	temp,save_temp
		pop	save_temp
		or	byte ptr ds:[save_temp],1 shl n
		mov	save_temp,temp
		mov	temp_l,0
		fetch1
endm

CBX	0c6H
		SETX	0
CBX	0ceH
		SETX	1
CBX	0d6H
		SETX	2
CBX	0deH
		SETX	3
CBX	0e6H
		SETX	4
CBX	0eeH
		SETX	5
CBX	0f6H
		SETX	6
CBX	0feH
		SETX	7

CBX	0ffh
		add	sp,2
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_undef4
		retf

;================================================
;=============  code ED xx  =====================
;================================================

op2	=	0

ED	macro	nn
	rept	nn - op2
		org	org_ED + op2 * 100h
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_undef2
		retf
		op2	= op2 + 1
	endm
	op2	= nn + 1
	org	org_ED + nn * 100h
endm

IO	macro
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_IO
		retf
endm

MLT		macro	src
		mov	temp,ax
		mov	ax,src
		mul	ah
		mov	src,ax
		mov	ax,temp
		mov	temp_l,0
		fetch1
endm

TST		macro	src
ifidni		src,temp_h
		mov	temp,save_temp
		test	A,src
elseifidni	src,temp_l
		mov	temp,save_temp
		test	A,src
else
		test	A,src
endif
		lahf
		or	ah,h_flag
		and	ah,not (n_flag or c_flag)
		mov	temp_l,0
		fetch1
endm

SBC8x	macro	dst,src
		sahf
		sbb	dst,src
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1
endm

ADC8x	macro	dst,src
		sahf
		adc	dst,src
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		mov	temp_l,0
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		mov	temp_l,0
		fetch1
endm

;--- LD ??,??
LD2		macro	dst,src

ifidni		dst,src

elseifidni	dst,temp_h

		mov	temp,save_temp
		mov	dst,src
		mov	save_temp,temp

elseifidni	dst,temp_l

		mov	temp,save_temp
		mov	dst,src
		mov	save_temp,temp

elseifidni	src,temp_h

		mov	temp,save_temp
		mov	dst,src

elseifidni	src,temp_l

		mov	temp,save_temp
		mov	dst,src
else
		mov	dst,src
endif
		mov	temp_l,0
		fetch1
endm

;--------------------------------------
ED	04H
		TST	B
ED	0cH
		TST	C_reg
ED	14H
		TST	D
ED	1cH
		TST	E
ED	24H
		TST	H
ED	2cH
		TST	L
ED	34H
		TST	M
ED	3cH
		TST	A

ED	40H				;IN	B,(C)
		IO
ED	41H				;OUT	(C),B
		IO
ED	42H				;SBC	HL,BC
		SBC8x	HL,BC

ED	43H				;LD	(nn),BC
		mov	temp,save_temp
		mov	save_temp,ds:[PC80]
		mov	ds:[save_temp],BC
		mov	save_temp,temp
		mov	temp_l,0
		fetch3

ED	44H				;NEG
		neg	A
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1

ED	45H				;RETN
		IO
ED	46H				;IM	0(do nothing)
		mov	temp_l,0
		fetch1

ED	47H				;LD	I,A
		mov	I,A
		mov	temp_l,0
		fetch1
ED	48H				;IN	C,(C)
		IO
ED	49H				;OUT	(C),C
		IO
ED	4aH				;ADC	HL,BC
		ADC8x	HL,BC

ED	4bH				;LD	BC,(nn)
ifidni	BC,temp
		mov	BC,ds:[PC80]
		mov	temp_l,0
		mov	BC,ds:[BC]
		fetch3
else
		mov	temp,save_temp
		mov	save_temp,ds:[PC80]
		mov	BC,ds:[save_temp]
		mov	save_temp,temp
		mov	temp_l,0
		fetch3
endif

ED	4cH				;MLT	BC
		MLT	BC

ED	4dH				;RETI
		IO

ED	4fH				;LD	R,A
		mov	R,A
		mov	temp_l,0
		fetch1

ED	50H				;IN	D,(C)
		IO
ED	51H				;OUT	(C),D
		IO
ED	52H				;SBC	HL,DE
		SBC8x	HL,DE
ED	53H				;LD	(nn),DE
		mov	temp,save_temp
		mov	save_temp,ds:[PC80]
		mov	ds:[save_temp],DE
		mov	save_temp,temp
		mov	temp_l,0
		fetch3
ED	56H				;IM	1(do nothing)
		mov	temp_l,0
		fetch1
ED	57H				;LD	A,I
		mov	A,I
		mov	temp_l,0
		fetch1
ED	58H				;IN	E,(C)
		IO
ED	59H				;OUT	(C),E
		IO
ED	5aH				;ADC	HL,DE
		ADC8x	HL,DE
ED	5bH				;LD	DE,(nn)
ifidni	DE,temp
		mov	DE,ds:[PC80]
		mov	temp_l,0
		mov	DE,ds:[DE]
		fetch3
else
		mov	temp,save_temp
		mov	save_temp,ds:[PC80]
		mov	DE,ds:[save_temp]
		mov	save_temp,temp
		mov	temp_l,0
		fetch3
endif

ED	5cH				;MLT	DE
		MLT	DE
ED	5eH				;IM	2(do nothing)
		mov	temp_l,0
		fetch1	
ED	5fH				;LD	A,R
		mov	A,R
		inc	A
		add	A,B
		mov	R,A
		mov	temp_l,0
		fetch1

ED	60H				;IN	H,(C)
		IO
ED	61H				;OUT	(C),H
		IO
ED	62H				;SBC	HL,HL
		SBC8x	HL,HL
ED	64H				;TST	n
		test	A,ds:[PC80]
		lahf
		mov	temp_l,0
		fetch2
ED	67H				;RRD	****
		mov	temp,ax
		and	temp_l,0f0h
		mov	ah,ds:[HL]
;		ror	ax,4
		ror	ax,1
		ror	ax,1
		ror	ax,1
		ror	ax,1
		mov	ds:[HL],ah
;		shr	al,4
		shr	al,1
		shr	al,1
		shr	al,1
		shr	al,1
		or	al,temp_l
		lahf
		and	ah,(s_flag or z_flag or	p_flag)
		and	temp_h,c_flag
		or	ah,temp_h
		mov	temp_l,0
		fetch1

ED	68H				;IN	L,(C)
		IO
ED	69H				;OUT	(C),L
		IO
ED	6aH				;ADC	HL,HL
		ADC8x	HL,HL
ED	6cH				;MLT	HL
		MLT	HL
ED	6fH				;RLD	****
		mov	temp,ax
		and	temp_l,0f0h
;		shl	al,4
		shl	al,1
		shl	al,1
		shl	al,1
		shl	al,1
		mov	ah,ds:[HL]
;		rol	ax,4
		rol	ax,1
		rol	ax,1
		rol	ax,1
		rol	ax,1
		mov	ds:[HL],ah
		or	al,temp_l
		lahf
		and	ah,(s_flag or z_flag or	p_flag)
		and	temp_h,c_flag
		or	ah,temp_h
		mov	temp_l,0
		fetch1

ED	70H				;IN	(C)
		IO
ED	72H				;SBC	HL,SP
		SBC8x	HL,SP80
ED	73H				;LD	(nn),SP
		mov	temp,save_temp
		mov	save_temp,ds:[PC80]
		mov	ds:[save_temp],SP80
		mov	save_temp,temp
		mov	temp_l,0
		fetch3

ED	78H				;IN	A,(C)
		IO

ED	79H				;OUT	(C),A
		IO

ED	7aH				;ADC	HL,SP
		ADC8x	HL,SP80

ED	7bH				;LD	SP,(nn)
		mov	SP80,ds:[PC80]
		mov	temp_l,0
		mov	SP80,ds:[SP80]
		fetch3

ED	7cH				;MLT	SP
		MLT	SP80

ED	0a0H				;LDI
		xchg	di,DE
		xchg	si,HL
		movsb
		xchg	si,HL
		xchg	di,DE
		dec	BC
		mov	temp_h,0
		jz	@f
		mov	temp_h,v_flag
@@:		and	ah,not (h_flag or v_flag or n_flag)
		or	ah,temp_h
		mov	temp_l,0
		fetch1

ED	0a1H				;CPI
		mov	temp_h,ah
		and	temp_h,c_flag
;		or	temp_h,n_flag
		cmp	A,ds:[HL]
		lahf
		inc	HL
		dec	BC
		jz	@f
		or	temp_h,v_flag
@@:		and	ah,not (v_flag or c_flag)
		or	ah,temp_h
		mov	temp_l,0
		fetch1

ED	0a2H				;INI
		IO
ED	0a3H				;OUTI
		IO

ED	0a8H				;LDD
		xchg	di,DE
		xchg	si,HL
		std
		movsb
		cld
		xchg	si,HL
		xchg	di,DE
		dec	BC
		mov	temp_h,0
		jz	@f
		mov	temp_h,v_flag
@@:		and	ah,not (h_flag or v_flag or n_flag)
		or	ah,temp_h
		mov	temp_l,0
		fetch1

ED	0a9H				;CPD
		mov	temp_h,ah
		and	temp_h,c_flag
;		or	temp_h,n_flag
		cmp	A,ds:[HL]
		lahf
		dec	HL
		dec	BC
		jz	@f
		or	temp_h,v_flag
@@:		and	ah,not (v_flag or c_flag)
		or	ah,temp_h
		mov	temp_l,0
		fetch1

ED	0aaH				;IND
		IO
ED	0abH				;OUTD
		IO

ED	0b0H				;LDIR
		xchg	di,DE
		xchg	si,HL
ifdifi		BC,<cx>
		xchg	cx,BC
endif
		rep	movsb
ifdifi		BC,<cx>
		xchg	cx,BC
endif
		xchg	si,HL
		xchg	di,DE
		and	ah,not (h_flag or v_flag or n_flag)
		mov	temp_l,0
		fetch1

ED	0b1H				;CPIR
		mov	temp_h,ah
		and	temp_h,c_flag
;		or	temp_h,n_flag
cpir_loop:	cmp	A,[HL]
		lahf
		je	short cpir_z
		inc	HL
		dec	BC
		jnz	short cpir_loop
		and	ah,not (z_flag or v_flag or c_flag)
		or	ah,temp_h
		mov	temp_l,0
		fetch1

cpir_z:		inc	HL
		dec	BC
		jz	short cpir_end
		or	temp_h,v_flag
cpir_end:	and	ah,not (z_flag or v_flag or c_flag)
		or	ah,temp_h
		mov	temp_l,0
		fetch1

ED	0b2H				;INIR
		IO
ED	0b3H				;OTIR
		IO

ED	0b8H				;LDDR
		xchg	si,HL
		xchg	di,DE
ifdifi		BC,<cx>
		xchg	cx,BC
endif
		std
		rep	movsb
		cld
ifdifi		BC,<cx>
		xchg	cx,BC
endif
		xchg	si,HL
		xchg	di,DE
		and	ah,not (h_flag or v_flag or n_flag)
		mov	temp_l,0
		fetch1

ED	0b9H				;CPDR

		mov	temp_h,ah
		and	temp_h,c_flag
;		or	temp_h,n_flag
cpdr_loop:	cmp	A,[HL]
		lahf
		je	short cpdr_z
		dec	HL
		dec	BC
		jnz	short cpdr_loop
		and	ah,not (z_flag or v_flag or c_flag)
		or	ah,temp_h
		mov	temp_l,0
		fetch1

cpdr_z:		dec	HL
		dec	BC
		jz	short cpdr_end
		or	temp_h,v_flag
cpdr_end:	and	ah,not (z_flag or v_flag or c_flag)
		or	ah,temp_h
		mov	temp_l,0
		fetch1

ED	0baH				;INDR
		IO
ED	0bbH				;OTDR
		IO

ED	0edh				;CALLN
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	temp_h,ds:[si]
		inc	si
		mov	cs:CALLN_vect,temp_h
		db	0cdh
CALLN_vect	db	0
		mov	temp_l,0
		fetch1

ED	0fdh				;RETEM
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_EDFD
		retf

ED	0ffh
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_undef2
		retf

;================================================
;=============  using IX IY =====================
;================================================

DDFD		macro	nn

	rept	nn - op2
		org	org_DDFD + op2 * 100h
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_undef2
		retf
		op2	= op2 + 1
	endm
	op2	= nn + 1
		org	org_DDFD + nn * 100h
endm

LDIXY		macro	dst		;LD	r,(IXY+d)

ifidni		dst,temp_h

		mov	temp,save_temp
		mov	save_temp,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,save_temp
		mov	dst,ds:[save_temp]
		mov	save_temp,temp

elseifidni	dst,temp_l

		mov	temp,save_temp
		mov	save_temp,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,save_temp
		mov	dst,ds:[save_temp]
		mov	save_temp,temp
else
		mov	temp,save_temp
		mov	save_temp,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,save_temp
		mov	dst,ds:[save_temp]
		mov	save_temp,temp
endif
		mov	temp_l,0
		fetch1
endm

STIXY		macro	src		;LD	(IXY+d),r

ifidni		src,temp_h

		mov	temp,save_temp
		mov	save_temp,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,save_temp
		mov	ds:[save_temp],src
		mov	save_temp,temp

elseifidni	src,temp_l

		mov	temp,save_temp
		mov	save_temp,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,save_temp
		mov	ds:[save_temp],src
		mov	save_temp,temp
else
		mov	temp,save_temp
		mov	save_temp,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,save_temp
		mov	ds:[save_temp],src
		mov	save_temp,temp
endif
		mov	temp_l,0
		fetch1
endm

;--- ADD IX/IY,reg16
ADDXY		macro	dst,src
		ror	ah,1
		add	dst,src
		rcl	ah,1
		and	ah,not (n_flag)
		mov	temp_l,0
		fetch1
endm

;=============  using IX    =====================
org_DDFD	=	org_DD

IXY		equ	IX
XYL		equ	XL
XYH		equ	XH

;--------------------------------------

rept	2

local	inc_x,dec_x,add_x,adc_x,sub_x,sbc_x,cmp_x

op2	=	0

DDFD	09H				;ADD	IXY,BC
		ADDXY	IXY,BC
DDFD	19H				;ADD	IXY,DE
		ADDXY	IXY,DE
DDFD	21H				;LD	IXY,nn
		mov	temp,ds:[PC80]
		mov	IXY,temp
		mov	temp_l,0
		fetch3
DDFD	22H				;LD	(nn),IXY
		push	ax
		mov	temp,bx
		lodsw
		mov	bx,ax
		mov	ax,IXY
		mov	ds:[bx],ax
		mov	bx,temp
		pop	ax
		mov	temp_l,0
		fetch1

DDFD	23H				;INC	IXY
		inc	IXY
		mov	temp_l,0
		fetch1

DDFD	24H				;INC	XYH
		sahf
		inc	XYH
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		mov	temp_l,0
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		mov	temp_l,0
		fetch1

DDFD	25H				;DEC	XYH
		sahf
		dec	XYH
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1
DDFD	26H				;LD	XYH,n
		mov	temp_h,ds:[PC80]
		mov	XYH,temp_h
		mov	temp_l,0
		fetch2
DDFD	29H				;ADD	IXY,IXY
		ror	ah,1
		shl	IXY,1
		rcl	ah,1
		and	ah,not (n_flag)
		mov	temp_l,0
		fetch1
DDFD	2aH				;LD	IXY,(nn)
		mov	temp,bx
		mov	bx,ds:[PC80]
		mov	bx,ds:[bx]
		mov	IXY,bx
		mov	bx,temp
		mov	temp_l,0
		fetch3

DDFD	2bH				;DEC	IXY
		dec	IXY
		mov	temp_l,0
		fetch1
DDFD	2cH				;INC	XYL
		sahf
		inc	XYL
inc_x:		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		mov	temp_l,0
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		mov	temp_l,0
		fetch1
DDFD	2dH				;DEC	XYL
		sahf
		dec	XYL
dec_x:		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1
DDFD	2eH
		mov	temp_h,ds:[PC80]	;LD	XYL,n
		mov	XYL,temp_h
		mov	temp_l,0
		fetch2
DDFD	34H				;INC	(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		sahf
		inc	byte ptr ds:[bx]
		mov	bx,temp
		jmp	inc_x

DDFD	35H				;DEC	(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		sahf
		dec	byte ptr ds:[bx]
		mov	bx,temp
		jmp	dec_x

DDFD	36H				;LD	(IXY+d),n
		push	ax
		mov	temp,bx
		lodsb
		cbw
		add	ax,IXY
		mov	bx,ax
		lodsb
		mov	ds:[bx],al
		mov	bx,temp
		pop	ax
		mov	temp_l,0
		fetch1

DDFD	39H				;ADD	IXY,SP
		ADDXY	IXY,SP80
DDFD	44H
		LD2	B,XYH
DDFD	45H
		LD2	B,XYL
DDFD	46H
		LDIXY	B
DDFD	4cH
		LD2	C_reg,XYH
DDFD	4dH
		LD2	C_reg,XYL
DDFD	4eH
		LDIXY	C_reg
DDFD	54H
		LD2	D,XYH
DDFD	55H
		LD2	D,XYL
DDFD	56H
		LDIXY	D
DDFD	5cH
		LD2	E,XYH
DDFD	5dH
		LD2	E,XYL
DDFD	5eH
		LDIXY	E
DDFD	60H
		LD2	XYH,B
DDFD	61H
		LD2	XYH,C_reg
DDFD	62H
		LD2	XYH,D
DDFD	63H
		LD2	XYH,E
DDFD	64H
		LD2	XYH,XYH
DDFD	65H				;LD	XYH,XYL
		mov	temp_h,XYL
		mov	XYH,temp_h
		mov	temp_l,0
		fetch1
DDFD	66H
		LDIXY	H
DDFD	67H
		LD2	XYH,A
DDFD	68H
		LD2	XYL,B
DDFD	69H
		LD2	XYL,C_reg
DDFD	6aH
		LD2	XYL,D
DDFD	6bH
		LD2	XYL,E
DDFD	6cH				;LD	XYL,XYH
		mov	temp_h,XYH
		mov	XYL,temp_h
		mov	temp_l,0
		fetch1
DDFD	6dH
		LD2	XYL,XYL
DDFD	6eH
		LDIXY	L
DDFD	6fH
		LD2	XYL,A
DDFD	70H
		STIXY	B
DDFD	71H
		STIXY	C_reg
DDFD	72H
		STIXY	D
DDFD	73H
		STIXY	E
DDFD	74H
		STIXY	H
DDFD	75H
		STIXY	L
DDFD	77H
		STIXY	A
DDFD	7cH
		LD2	A,XYH
DDFD	7dH
		LD2	A,XYL
DDFD	7eH
		LDIXY	A
DDFD	84H				;ADD	A,XYH
		add	A,XYH
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		mov	temp_l,0
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		mov	temp_l,0
		fetch1

DDFD	85H				;ADD	A,XYL
		add	A,XYL
add_x:		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		mov	temp_l,0
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		mov	temp_l,0
		fetch1

DDFD	86H				;ADD	A,(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		add	A,ds:[bx]
		mov	bx,temp
		jmp	add_x

DDFD	8cH				;ADC	A,XYH
		sahf
		adc	A,XYL
		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		mov	temp_l,0
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		mov	temp_l,0
		fetch1

DDFD	8dH				;ADC	A,XYL
		sahf
		adc	A,XYL
adc_x:		lahf
		jo	@f
		and	ah,not (v_flag or n_flag)
		mov	temp_l,0
		fetch1
@@:		and	ah,not n_flag
		or	ah,v_flag
		mov	temp_l,0
		fetch1

DDFD	8eH				;ADC	A,(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		sahf
		adc	A,ds:[bx]
		mov	bx,temp
		jmp	adc_x

DDFD	94H				;SUB	A,XYH
		sub	A,XYH
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1

DDFD	95H				;SUB	A,XYL
		sub	A,XYL
sub_x:		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1

DDFD	96H				;SUB	A,(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		sub	A,ds:[bx]
		mov	bx,temp
		jmp	sub_x

DDFD	9cH				;SBC	A,XYH
		sahf
		sbb	A,XYH
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1

DDFD	9dH				;SBC	A,XYL
		sahf
		sbb	A,XYL
sbc_x:		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1

DDFD	9eH				;SBC	A,(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		sahf
		sbb	A,ds:[bx]
		mov	bx,temp
		jmp	sbc_x

DDFD	0a4H				;AND	XYH
		and	A,XYH
		lahf
		and	ah,not(n_flag or c_flag)
		or	ah,h_flag
		mov	temp_l,0
		fetch1
DDFD	0a5H				;AND	XYL
		and	A,XYH
		lahf
		and	ah,not(n_flag or c_flag)
		or	ah,h_flag
		mov	temp_l,0
		fetch1
DDFD	0a6H				;AND	(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		and	A,ds:[bx]
		mov	bx,temp
		lahf
		and	ah,not(n_flag or c_flag)
		or	ah,h_flag
		mov	temp_l,0
		fetch1

DDFD	0acH				;XOR	XYH
		xor	A,XYH
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		mov	temp_l,0
		fetch1

DDFD	0adH				;XOR	XYL
		xor	A,XYL
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		mov	temp_l,0
		fetch1

DDFD	0aeH				;XOR	(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		xor	A,ds:[bx]
		mov	bx,temp
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		mov	temp_l,0
		fetch1

DDFD	0b4H				;OR	XYH
		or	A,XYH
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		mov	temp_l,0
		fetch1
DDFD	0b5H				;OR	XYL
		or	A,XYL
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		mov	temp_l,0
		fetch1
DDFD	0b6H				;OR	(IXY+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		or	A,ds:[bx]
		mov	bx,temp
		lahf
		and	ah,not(h_flag or n_flag or c_flag)
		mov	temp_l,0
		fetch1

DDFD	0bcH				;CP	XYH
		cmp	A,XYH
		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1

DDFD	0bdH				;CP	XYL
		cmp	A,XYL
cmp_x:		lahf
		jo	@f
		and	ah,not(v_flag)
;		or	ah,n_flag
		mov	temp_l,0
		fetch1
@@:		or	ah,(v_flag or n_flag)
		mov	temp_l,0
		fetch1

DDFD	0beH				;CP	(IX+d)
		mov	temp,bx
		mov	bx,ax
		lodsb
		cbw
		add	ax,IXY
		xchg	ax,bx
		cmp	A,ds:[bx]
		mov	bx,temp
		jmp	cmp_x

DDFD	0cbH				;code DDCB
                mov     temp,ax
		lodsb
                cbw
                add     ax,IXY
                push	ax
                lodsb
                mov     ah,al
                mov     al,org_CBX
                xchg    ax,temp
                jmp	temp

DDFD	0e1H				;POP	IXY
		mov	temp,ds:[SP80]
		mov	IXY,temp
		add	SP80,2
		mov	temp_l,0
		fetch1
DDFD	0e3H				;EX	(SP),IXY
		mov	temp,ds:[SP80]
		xchg	temp,IXY
		mov	ds:[SP80],temp
		mov	temp_l,0
		fetch1
DDFD	0e5H				;PUSH	IXY
		mov	temp,IXY
		sub	SP80,2
		mov	ds:[SP80],temp
		mov	temp_l,0
		fetch1
DDFD	0e9H				;JP	(IXY)
		mov	PC80,IXY
		mov	temp_l,0
		fetch1
DDFD	0f9H				;LD	SP,IXY
		mov	SP80,IXY
		mov	temp_l,0
		fetch1

DDFD	0ffh
		mov	temp,save_temp
		mov	entry_SP,SP80
		mov	ret_reg,code_undef2
		retf

;=============  using IY    =====================

org_DDFD	=	org_FD

IXY		equ	IY
XYL		equ	YL
XYH		equ	YH

endm
;================================================

		org	0ffc0h
exe_start:
		mov	ax,cs
		mov	ds,ax
		mov	dx,offset exe_msg1
		mov	ah,9
		int	21h
		mov	dx,offset exe_msg2
		mov	ah,9
		int	21h
		mov	dx,offset exe_msg3
		mov	ah,9
		int	21h
		mov	dx,offset exe_msg4
		mov	ah,9
		int	21h
		mov	dx,offset exe_msg5
		mov	ah,9
		int	21h
		mov	ax,4c00h
		int	21h

		.data
		.stack

		end	exe_start
 