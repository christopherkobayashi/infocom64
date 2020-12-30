; $Id$

;
; Commodore 64 Infocom v3 interpreter, version I
; Build 2014110401 Christopher Kobayashi <lemon64@disavowed.jp>
;
; This was disassembled from the officially released version H interpreter,
; and modified thusly:
;
; * The 1541/1571 fastload routines were removed.
; * The story file is loaded from "STORY.DAT" instead of raw blocks.
; * To accomodate the above, an REU is now required.
; * The number of save slots has been increased from five to nine.
; * Save games are 49-block seq files named "SAVEn", where n is 1 through 9
; * The game can be run from any device number, not just device 8.
; * REU mirrored register access has been fixed.
; * EasyFlash can be used as a read-only REU substitute :)
;
; These changes were made so that games could be easily played using an uIEC,
; but would also be useful with any larger-capacity drive (1581, FD-2000, etc).
;

; Compile with: xa65 -M -o i-v3 i-v3.s
;
; Crunch with: exomizer sfx 0x0e00 i-v3 -o infocom3
;

#include "c64.inc"

MAP_RAM =               %11111101
MAP_ROM =               %00000010

REU_PRESENT =		$02	; 0 (0000) = no REU (death mode)
				; 1 (x001) = CBM REU
				; 2 (x010) = GeoRAM
				; 3 (x100) = EasyFlash
				; 4 (1xxx) = uIEC present

Z_CURRENT_OPCODE =	$03
Z_OPERAND1 =		$05
Z_OPERAND2 =		$07

Z_VECTOR0 =		$09
Z_VECTOR1 =		$0F
Z_VECTOR2 =		$11
Z_VECTOR3 =		$13
Z_VECTOR4 =		$15
Z_STACK_POINTER =	$17

Z_PC =			$19
Z_BASE_PAGE =		$26
Z_RESIDENT_ADDR =	$27
Z_STORY_INDEX =		$2a
Z_GLOBALS_ADDR =	$2F
Z_DICT_ADDR =		$31
Z_ABBREV_ADDR =		$33
Z_OBJECTS_ADDR =	$35
Z_FLAGS =		$5F
Z_STORY_SIDE =		$62
Z_TEMP1 =		$67

STORY_INDEX =		$70
PAGE_VECTOR = 		$72

INPUT_BUFFER =		$0200
SECTOR_BUFFER =		$0800
Z_STACK_LO =		$0900
Z_STACK_HI =		$0A00
Z_STORY_PAGE_INDEX =	$0c50
Z_LOCAL_VARIABLES = 	$0D00

Z_HDR_CODE_VERSION =	Z_HEADER + 0
Z_HDR_MODE_BITS =	Z_HEADER + 1
Z_HDR_RESIDENT_SIZE =	Z_HEADER + 4
Z_HDR_START_PC =	Z_HEADER + 6
Z_HDR_DICTIONARY = 	Z_HEADER + 8
Z_HDR_OBJECTS =		Z_HEADER + $0a
Z_HDR_GLOBALS =		Z_HEADER + $0c
Z_HDR_DYN_SIZE =	Z_HEADER + $0e
Z_HDR_FLAGS2 =		Z_HEADER + $10
Z_HDR_ABBREV =		Z_HEADER + $18
Z_HDR_FILE_LENGTH =	Z_HEADER + $1a
Z_HDR_CHKSUM =		Z_HEADER + $1c
Z_HDR_INTERP_NUMBER =	Z_HEADER + $1e
Z_HDR_INTERP_VERSION =	Z_HEADER + $1f
Z_HDR_SCREEN_ROWS =	Z_HEADER + $20
Z_HDR_SCREEN_COLS =	Z_HEADER + $21

SCREEN_WIDTH =		40
MAX_RAM_PAGE =		$CF

; compile-time constants that are modified for version I

SAVE_SLOTS =		9
REU_TXT_LEN =	$52

.word	$0e00
* = $0e00

	jsr	PREP_SYSTEM

STARTUP
.(
	cld
        ldx     #$FF
        txs
        jsr     CLALL
        ldy     #$08
        ldx     #$0B
        clc
        jsr     PLOT

        lda     REU_PRESENT
	and	#%00001111	; we have to have at least a uIEC ...
	bne	L0a
	lda	#$89
	jmp	$FCE2		; this should be FATAL_ERROR

L0a     ldx     #<STORY_LOADING_TEXT
        lda     #>STORY_LOADING_TEXT
        ldy     #$19
;        ldx     #<PATIENT
;        lda     #>PATIENT
;        ldy     #$28
        jsr     PRINT_MESSAGE

L1	lda     #$00
        ldx     #$03
L2	sta     $00,x		; initialize $03 - $93 to 0
        inx
        cpx     #$8F
        bcc     L2
        tax
        lda     #$FF
L3	sta     $0B00,x
        sta     $0BA0,x
        inx
        cpx     #$A0
        bcc     L3
        lda     #$00
        tax
L4	sta     Z_STORY_PAGE_INDEX,x
        inx
        cpx     #$A0
        bcc     L4
        inc     Z_STACK_POINTER
        inc     $18
        inc     $2D

; load in first page of story file

        lda     #>Z_HEADER
        sta     Z_BASE_PAGE
        sta     PAGE_VECTOR+1

	lda	REU_PRESENT
	and	#%00000100
	beq	L5
				; set EasyFlash bank to 1, prepping for load
        lda     #$80
        sta     EF_VEC1+2
	lda	EF_START_BANK
	sta	EF_BANK
	jmp	L7
L5
	jsr	UIEC_ONLY
	bcc	L6
	clc
	jsr	COMMAND_OPEN	; so that we can seek around ...
L6
	jsr	STORY_OPEN
L7
	ldx	#5
        jsr     READ_BUFFER
	bcc	L8
	jmp	FATAL_ERROR_0E

L8	lda	Z_HDR_CODE_VERSION
	cmp	#4		; handle v1-3
	bcc	L9
	lda	#$10
	jmp	FATAL_ERROR

L9	ldx     Z_HDR_RESIDENT_SIZE
        inx
        stx     Z_RESIDENT_ADDR
        txa
        clc
        adc     Z_BASE_PAGE
        sta     Z_RESIDENT_ADDR+1
        jsr     GET_MAX_PAGE
        sec
        sbc     Z_RESIDENT_ADDR+1
        beq     Z_ERROR_0	; resident too big to fit 2e00-cfff
        bcs     L10
Z_ERROR_0
	lda     #0
        jmp     FATAL_ERROR

L10	cmp     #$A0		; magic number - under BASIC ROM?
        bcc     L11
        lda     #$A0
L11	sta     $29
        lda     Z_HDR_MODE_BITS
        ora     #$20
        sta     Z_HDR_MODE_BITS
        and     #$02		; we care only about status display format
        sta     Z_FLAGS
        lda     Z_HDR_GLOBALS
        clc
        adc     Z_BASE_PAGE
        sta     Z_GLOBALS_ADDR+1
        lda     Z_HDR_GLOBALS+1
        sta     Z_GLOBALS_ADDR
        lda     Z_HDR_ABBREV
        clc
        adc     Z_BASE_PAGE
        sta     Z_ABBREV_ADDR+1
        lda     Z_HDR_ABBREV+1
        sta     Z_ABBREV_ADDR
        lda     Z_HDR_DICTIONARY
        clc
        adc     Z_BASE_PAGE
        sta     Z_DICT_ADDR+1
        lda     Z_HDR_DICTIONARY+1
        sta     Z_DICT_ADDR
        lda     Z_HDR_OBJECTS
        clc
        adc     Z_BASE_PAGE
        sta     Z_OBJECTS_ADDR+1
        lda     Z_HDR_OBJECTS+1
        sta     Z_OBJECTS_ADDR

; continue loading resident portion into RAM, regardless of REU presence.

L12	lda     STORY_INDEX
        cmp     Z_RESIDENT_ADDR
        bcs     L13
;	lda	REU_PRESENT
;	and	#%00000100
;	bne	L12a
;	jsr	DO_TWIRLY
;L12a
	ldx	#5
        jsr     READ_BUFFER
        jmp     L12

; If we have an REU, load everything else into it.

L13
	lda	REU_PRESENT
	tax
	and	#%00000100
	beq	L13a
			; at this point, EF_VEC1+2 has non-res base page and
			; EF_BANK has non-res base bank ...
	lda	EF_VEC1+2
	sta	EF_NONRES_PAGE_BASE
	lda	EF_BANK
	sta	EF_NONRES_BANK_BASE
	jmp	PREP_FOR_RUN
L13a
	txa
	and	#%00001111
	cmp	#$08
	beq	PREP_FOR_RUN		; uIEC-only, so we jump right in
        jsr     REU_LOAD_STORY
	jsr	CLOSE_STORY_FILE
.)

;
; At this point we've got enough in memory to start execution.  Prep for run.
;

PREP_FOR_RUN
.(
	lda     Z_HDR_START_PC
        sta     Z_PC+1
        lda     Z_HDR_START_PC+1
        sta     Z_PC
        lda     Z_HDR_FLAGS2+1
        ora     INTERP_FLAGS
        sta     Z_HDR_FLAGS2+1
        jsr     CLEAR_SCREEN
.)

MAIN_LOOP
.(
	lda     #$00
        sta     $04
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_CURRENT_OPCODE
        tax
        bmi     *+5
        jmp     DO_TWO_OPERAND	; handle two operands (< 176/$b0)

	cmp     #$B0	; is this opcode below 176 (thus one-operand)
        bcs     *+5
        jmp     DO_ONE_OPERAND	; handle one-operand

	cmp     #$C0	; is this an opcode below 192 (thus zero-operand)?
        bcs     *+5
        jmp     DO_ZERO_OPERAND

	jsr     FETCH_NEXT_ZBYTE	; must be a variable operand
        sta     $0D
        ldx     #$00
        stx     $0E
        beq     L0FAA
L0FA4:  lda     $0D
        asl
        asl
        sta     $0D
L0FAA:  and     #$C0
        bne     L0FB4
        jsr     L1092
        jmp     L0FC5

L0FB4:  cmp     #$40
        bne     L0FBE
        jsr     L108E
        jmp     L0FC5

L0FBE:  cmp     #$80
        bne     L0FD9
        jsr     FETCH_NEXT_AND_READ_WORD
L0FC5:  ldx     $0E
        lda     Z_VECTOR1
        sta     Z_OPERAND1,x
        lda     Z_VECTOR1+1
        sta     Z_OPERAND1+1,x
        inc     $04
        inx
        inx
        stx     $0E
        cpx     #$08
        bcc     L0FA4
L0FD9:  lda     Z_CURRENT_OPCODE
        cmp     #$E0		; variable opcode (greater than 224)?
        bcs     DO_VARIABLE_OPERAND
        jmp     L106F
.)

DO_VARIABLE_OPERAND
.(
	ldx     #<JUMP_TABLE_VAR
        ldy     #>JUMP_TABLE_VAR
        and     #$1F
        cmp     #$0C		; we only handle the first 12 variable opcodes
        bcc     DO_JUMP
        lda     #$01
        jmp     FATAL_ERROR
.)

DO_JUMP
.(
	stx     Z_VECTOR2
        sty     Z_VECTOR2+1
        asl
        tay
        lda     (Z_VECTOR2),y
        sta     JUMP1+1
        iny
        lda     (Z_VECTOR2),y
        sta     JUMP1+2
JUMP1	jsr	!$0000
        jmp     MAIN_LOOP
.)

DO_ZERO_OPERAND
.(
	ldx     #<JUMP_TABLE_ZERO
        ldy     #>JUMP_TABLE_ZERO
        and     #$0F
        cmp     #$0E		; guess we don't handle the piracy opcode
        bcc     DO_JUMP
        lda     #$02
        jmp     FATAL_ERROR
.)

DO_ONE_OPERAND
.(
	and     #$30
        bne     L1021
        jsr     L1092
        jmp     L1032
.)

L1021:  cmp     #$10
        bne     L102B
        jsr     L108E
        jmp     L1032

L102B:  cmp     #$20
        bne     Z_CALL_LS
        jsr     FETCH_NEXT_AND_READ_WORD
L1032:  jsr     L1083
        ldx     #<JUMP_TABLE_ONE
        ldy     #>JUMP_TABLE_ONE
        lda     Z_CURRENT_OPCODE
        and     #$0F
        cmp     #$10		; only first sixteen one-byters
        bcc     DO_JUMP
Z_CALL_LS:  lda     #$03
        jmp     FATAL_ERROR

DO_TWO_OPERAND:  and     #$40
        bne     L1050
        jsr     L108E
        jmp     L1053
L1050:  jsr     FETCH_NEXT_AND_READ_WORD
L1053:  jsr     L1083
        lda     Z_CURRENT_OPCODE
        and     #$20
        bne     L1062
        jsr     L108E
        jmp     L1065

L1062:  jsr     FETCH_NEXT_AND_READ_WORD
L1065:  lda     Z_VECTOR1
        sta     Z_OPERAND2
        lda     Z_VECTOR1+1
        sta     Z_OPERAND2+1
        inc     $04
L106F:  ldx     #<JUMP_TABLE_TWO
        ldy     #>JUMP_TABLE_TWO
        lda     Z_CURRENT_OPCODE
        and     #$1F
        cmp     #$19		; only the first eighteen
        bcs     Z_ERROR_4
        jmp     DO_JUMP

Z_ERROR_4:  lda     #$04
        jmp     FATAL_ERROR

;
; End opcode jumptable logic.
;

L1083:  lda     Z_VECTOR1
        sta     Z_OPERAND1
        lda     Z_VECTOR1+1
        sta     Z_OPERAND1+1
        inc     $04
        rts

L108E:  lda     #$00
        beq     L1095
L1092:  jsr     FETCH_NEXT_ZBYTE
L1095:  sta     Z_VECTOR1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR1
        rts

L109D:  tax
        bne     L10AB
        jsr     Z_POP
        jmp     Z_PUSH_STACK1

FETCH_NEXT_AND_READ_WORD:  jsr     FETCH_NEXT_ZBYTE
        beq     Z_POP
L10AB:  cmp     #$10
        bcs     READ_GLOBAL_WORD
        sec
        sbc     #$01
        asl
        tax
        lda     Z_LOCAL_VARIABLES,x
        sta     Z_VECTOR1
        lda     Z_LOCAL_VARIABLES+1,x
        sta     Z_VECTOR1+1
        rts

READ_GLOBAL_WORD:  jsr     CALCULATE_GLOBAL_WORD_ADDRESS
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR1+1
        iny
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR1
        rts

; 0OP:185 9 1 pop
; Throws away the top item on the stack.

Z_POP:  dec     Z_STACK_POINTER
        beq     Z_ERROR_5		; stack should always be > 0
        ldy     Z_STACK_POINTER
        ldx     Z_STACK_LO,y
        stx     Z_VECTOR1
        lda     Z_STACK_HI,y
        sta     Z_VECTOR1+1
        rts

Z_ERROR_5:
	lda     #5			; stack underflow
        jmp     FATAL_ERROR

Z_PUSH_STACK1:
	ldx     Z_VECTOR1
        lda     Z_VECTOR1+1
Z_PUSH_STACK2:
	ldy     Z_STACK_POINTER
        sta     Z_STACK_HI,y
        txa
        sta     Z_STACK_LO,y
        inc     Z_STACK_POINTER
        beq     Z_ERROR_6		; stack must be < 256
        rts

Z_ERROR_6:
	lda     #6		; stack overflow
        jmp     FATAL_ERROR

; This sets both globals and locals, depending on next zbyte

SET_GLOBAL_OR_LOCAL_WORD:  tax
        bne     L110F
        dec     Z_STACK_POINTER
        bne     Z_PUSH_STACK1
        beq     Z_ERROR_5
L1102:  lda     #$00
L1104:  sta     Z_VECTOR1
        lda     #$00
        sta     Z_VECTOR1+1
L110A:  jsr     FETCH_NEXT_ZBYTE
        beq     Z_PUSH_STACK1
L110F:  cmp     #$10		; is it a global variable?
        bcs     SET_GLOBAL_WORD
        sec
        sbc     #$01
        asl
        tax
        lda     Z_VECTOR1
        sta     Z_LOCAL_VARIABLES,x
        lda     Z_VECTOR1+1
        sta     Z_LOCAL_VARIABLES+1,x
        rts

; store a word in Z_VECTOR1 to (Z_GLOBALS_ADDR)


SET_GLOBAL_WORD:
	jsr     CALCULATE_GLOBAL_WORD_ADDRESS
        lda     Z_VECTOR1+1
        sta     (Z_VECTOR2),y
        iny
        lda     Z_VECTOR1
        sta     (Z_VECTOR2),y
        rts

CALCULATE_GLOBAL_WORD_ADDRESS:
	sec
        sbc     #$10		; assume a is now $05 (orig 15)
        ldy     #$00
        sty     Z_VECTOR2+1	; highbyte now 00
        asl			; a is now $10
        rol     Z_VECTOR2+1	; if carry was set, it's now $01
        clc			
        adc     Z_GLOBALS_ADDR	; a = Z_GLOBALS + 10
        sta     Z_VECTOR2	; to lowbyte
        lda     Z_VECTOR2+1	; add in overflow
        adc     Z_GLOBALS_ADDR+1
        sta     Z_VECTOR2+1	; to highbyte
L1145:  rts

L1146:  jsr     FETCH_NEXT_ZBYTE
        bpl     L1157
L114B:  and     #$40
        bne     L1145
        jmp     FETCH_NEXT_ZBYTE

L1152:  jsr     FETCH_NEXT_ZBYTE
        bpl     L114B
L1157:  tax
        and     #$40
        beq     L1167
        txa
        and     #$3F
        sta     Z_VECTOR1
        lda     #$00
        sta     Z_VECTOR1+1
        beq     L117A
L1167:  txa
        and     #$3F
        tax
        and     #$20
        beq     L1173
        txa
        ora     #$E0
        tax
L1173:  stx     Z_VECTOR1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR1
L117A:  lda     Z_VECTOR1+1
        bne     L118C
        lda     Z_VECTOR1
        bne     L1185
        jmp     Z_RFALSE

L1185:  cmp     #$01
        bne     L118C
        jmp     Z_RTRUE

L118C:  jsr     DEC_VECTOR1
        jsr     DEC_VECTOR1
        lda     #$00
        sta     Z_VECTOR2+1
        lda     Z_VECTOR1+1
        sta     Z_VECTOR2
        asl
        rol	Z_VECTOR2+1
        lda     Z_VECTOR1
        clc
        adc     Z_PC
        bcc     L11AA
        inc     Z_VECTOR2
        bne     L11AA
        inc     Z_VECTOR2+1
L11AA:  sta     Z_PC
        lda     Z_VECTOR2
        ora     Z_VECTOR2+1
        beq     Z_NOP
        lda     Z_VECTOR2
        clc
        adc     Z_PC+1
        sta     Z_PC+1
        lda     Z_VECTOR2+1
        adc     $1B
        and     #$01
        sta     $1B
        lda     #$00
        sta     $1C
Z_NOP:  rts

DEC_VECTOR1
.(
	lda     Z_VECTOR1
        sec
        sbc     #$01
        sta     Z_VECTOR1
        bcs     L1
        dec     Z_VECTOR1+1
L1:	rts
.)

INC_VECTOR1
.(
	inc     Z_VECTOR1
        bne     L1
        inc     Z_VECTOR1+1
L1:	rts
.)

L11D9:  lda     Z_OPERAND1
        sta     Z_VECTOR1
        lda     Z_OPERAND1+1
        sta     Z_VECTOR1+1
        rts


JUMP_TABLE_ZERO:

	.word 	Z_RTRUE, Z_RFALSE, Z_PRINT_LITERAL, Z_PRINT_RET_LITERAL
	.word	Z_NOP, Z_SAVE, Z_RESTORE, Z_RESTART, Z_RET_POPPED, Z_POP
	.word	Z_QUIT, Z_NEW_LINE, Z_SHOW_STATUS, Z_VERIFY

JUMP_TABLE_ONE:
	.word	Z_JZ, Z_GET_SIBLING, Z_GET_CHILD, Z_GET_PARENT, Z_GET_PROP_LEN
	.word	Z_INC, Z_DEC, Z_PRINT_ADDR, Z_CALL_LS, Z_REMOVE_OBJ
	.word	Z_PRINT_OBJ, Z_RET, Z_JUMP, Z_PRINT_PADDR, Z_LOAD, Z_NOT

JUMP_TABLE_TWO:
	.word	Z_ERROR_4, Z_JE, Z_JL, Z_JG, Z_DEC_CHK, Z_INC_CHK, Z_JIN
	.word	Z_TEST, Z_OR, Z_AND, Z_TEST_ATTR, Z_SET_ATTR, Z_CLEAR_ATTR
	.word	Z_STORE, Z_INSERT_OBJ, Z_LOADW, Z_LOADB, Z_GET_PROP
	.word	Z_GET_PROP_ADDR, Z_GET_NEXT_PROP, Z_ADD, Z_SUB, Z_MUL, Z_DIV
	.word	Z_MOD

JUMP_TABLE_VAR:
	.word	Z_CALL, Z_STOREW, Z_STOREB, Z_PUT_PROP, Z_SREAD, Z_PRINT_CHAR
	.word	Z_PRINT_NUM, Z_RANDOM, Z_PUSH, Z_PULL, Z_SPLIT_WINDOW
	.word	Z_SET_WINDOW

; 0OP:176 0 rtrue
; Return true (i.e., 1) from the current routine.

Z_RTRUE:  ldx     #$01
L126A:  lda     #$00
L126C:  stx     Z_OPERAND1
        sta     Z_OPERAND1+1
        jmp     Z_RET

; 0OP:177 1 rfalse
; Return false (i.e., 0) from the current routine.

Z_RFALSE:  ldx     #$00
        beq     L126A

; 0OP:178 2 print
; Print the quoted (literal) Z-encoded string.

Z_PRINT_LITERAL:  lda     $1B
        sta     $21
        lda     Z_PC+1
        sta     $20
        lda     Z_PC
        sta     $1F
        lda     #$00
        sta     $22
        jsr     L1D2E
        ldx     #$05
L128C:  lda     $1F,x
        sta     Z_PC,x
        dex
        bpl     L128C
        rts

; 0OP:179 3 print_ret
; Print the quoted (literal) Z-encoded string, then print a new-line and
; then return true (i.e., 1).

Z_PRINT_RET_LITERAL:  jsr     Z_PRINT_LITERAL
        jsr     Z_NEW_LINE
        jmp     Z_RTRUE

; 0OP:184 8 ret_popped
; Pops top of stack and returns that.

Z_RET_POPPED:
	jsr     Z_POP
        jmp     L126C

; 0OP:189 D 3 verify ?(label)
; Verification counts a (two byte, unsigned) checksum of the file from
; $0040 onwards (by taking the sum of the values of each byte in the file,
; modulo $10000) and compares this against the value in the game header,
; branching if the two values agree.

Z_VERIFY:
	jsr     PRINT_VERSION
        ldx     #$03
        lda     #$00
L12AA:  sta     Z_VECTOR3,x
        sta     $1F,x
        dex
        bpl     L12AA
        lda     #$40
        sta     $1F
        lda     Z_HDR_FILE_LENGTH
        sta     Z_VECTOR2+1
        lda     Z_HDR_FILE_LENGTH+1
        sta     Z_VECTOR2
        asl     Z_VECTOR2
        rol     Z_VECTOR2+1
        rol     Z_VECTOR4
        lda     #0		; reset page pointers ...
        sta     STORY_INDEX
        sta     STORY_INDEX+1
	lda	REU_PRESENT
	and	#%00000100
	beq	L12AA1
	lda	EF_START_BANK
	sta	EF_BANK
	lda	#$80
	sta	EF_VEC1+2
	jmp	L12AA2
L12AA1
	jsr	UIEC_ONLY
	bcc	L12AA1a
	clc
	lda	#0
	tax
	tay
	jsr	UIEC_SEEK
	jmp	L12AA2
L12AA1a
	jsr	STORY_OPEN
L12AA2
        jmp     L12D2
L12CE:  lda     $1F
        bne     L12D9
L12D2:  lda     #>SECTOR_BUFFER
        sta     PAGE_VECTOR+1
	ldx	#5
        jsr     READ_BUFFER
L12D9:  ldy     $1F
        lda     SECTOR_BUFFER,y
        inc     $1F
        bne     L12E8
        inc     $20
        bne     L12E8
        inc     $21
L12E8:  clc
        adc     Z_VECTOR3
        sta     Z_VECTOR3
        bcc     L12F1
        inc     Z_VECTOR3+1
L12F1:  lda     $1F
        cmp     Z_VECTOR2
        bne     L12CE
        lda     $20
        cmp     Z_VECTOR2+1
        bne     L12CE
        lda     $21
        cmp     Z_VECTOR4
        bne     L12CE
	lda	REU_PRESENT
	and	#%00000100
	bne	L12F1a
	jsr	CLOSE_STORY_FILE	; with uIEC, we need to re-open ...
	jsr	UIEC_ONLY
	bcc	L12F1a
	clc
	jsr	COMMAND_CLOSE
	jsr	COMMAND_OPEN
	jsr	STORY_OPEN
L12F1a	lda     Z_HDR_CHKSUM+1
        cmp     Z_VECTOR3
        bne     L1314
        lda     Z_HDR_CHKSUM
        cmp     Z_VECTOR3+1
        bne     L1314
        jmp     L1152
L1314:  jmp     L1146

; 1OP:128 0 jz a ?(label)
; Jump if a = 0.

Z_JZ:  lda     Z_OPERAND1
        ora     Z_OPERAND1+1
        beq     L1339
L131D:  jmp     L1146

; 1OP:129 1 get_sibling object -> (result) ?(label)
; Get next object in tree, branching if this exists, i.e. is not 0.

Z_GET_SIBLING:  lda     Z_OPERAND1
        jsr     L1F39
        ldy     #$05
        bne     L1330

; 1OP:130 2 get_child object -> (result) ?(label)
; Get first object contained in given object, branching if this exists,
; i.e. is not nothing (i.e., is not 0).

Z_GET_CHILD:  lda     Z_OPERAND1
        jsr     L1F39
        ldy     #$06
L1330:  lda     (Z_VECTOR2),y
        jsr     L1104
        lda     Z_VECTOR1
        beq     L131D
L1339:  jmp     L1152

; 1OP:131 3 get_parent object -> (result)
; Get parent object (note that this has no "branch if exists" clause).

Z_GET_PARENT:  lda     Z_OPERAND1
        jsr     L1F39
        ldy     #$04
        lda     (Z_VECTOR2),y
        jmp     L1104

; 1OP:132 4 get_prop_len property-address -> (result)
; Get length of property data (in bytes) for the given object's property.
; It is illegal to try to find the property length of a property which does
; not exist for the given object, and an interpreter should halt with an error
; message (if it can efficiently check this condition).

Z_GET_PROP_LEN:  lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_VECTOR2+1
        lda     Z_OPERAND1
        sec
        sbc     #$01
        sta     Z_VECTOR2
        bcs     L135A
        dec     Z_VECTOR2+1
L135A:  ldy     #$00
        jsr     L1F83
        clc
        adc     #$01
        jmp     L1104

; 1OP:133 5 inc (variable)
; Increment variable by 1. (This is signed, so -1 increments to 0.)

Z_INC:  lda     Z_OPERAND1
        jsr     L109D
        jsr     INC_VECTOR1
        jmp     L1378

; 1OP:134 6 dec (variable)
; Decrement variable by 1. This is signed, so 0 decrements to -1.

Z_DEC:  lda     Z_OPERAND1
        jsr     L109D
        jsr     DEC_VECTOR1
L1378:  lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

; 1OP:135 7 print_addr byte-address-of-string
; Print (Z-encoded) string at given byte address, in dynamic or static memory.

Z_PRINT_ADDR:  lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jsr     L1B87
        jmp     L1D2E

; 1OP:137 9 remove_obj object
; Detach the object from its parent, so that it no longer has any parent.

Z_REMOVE_OBJ:  lda     Z_OPERAND1
        jsr     L1F39
        lda     Z_VECTOR2
        sta     Z_VECTOR3
        lda     Z_VECTOR2+1
        sta     Z_VECTOR3+1
        ldy     #$04
        lda     (Z_VECTOR2),y
        beq     L13CC
        jsr     L1F39
        ldy     #$06
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND1
        bne     L13B2
        ldy     #$05
        lda     (Z_VECTOR3),y
        iny
        sta     (Z_VECTOR2),y
        bne     L13C3
L13B2:  jsr     L1F39
        ldy     #$05
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND1
        bne     L13B2
        ldy     #$05
        lda     (Z_VECTOR3),y
        sta     (Z_VECTOR2),y
L13C3:  lda     #$00
        ldy     #$04
        sta     (Z_VECTOR3),y
        iny
        sta     (Z_VECTOR3),y
L13CC:  rts

; 1OP:138 A print_obj object
; Print short name of object (the Z-encoded string in the object header,
; not a property). If the object number is invalid, the interpreter should
; halt with a suitable error message.

Z_PRINT_OBJ:  lda     Z_OPERAND1
L13CF:  jsr     L1F39
        ldy     #$07
        lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR2
        stx     Z_VECTOR2+1
        inc     Z_VECTOR2
        bne     L13E4
        inc     Z_VECTOR2+1
L13E4:  jsr     L1B87
        jmp     L1D2E

; 1OP:139 B ret value
; Returns from the current routine with the value given.

Z_RET:  lda     $18
        sta     Z_STACK_POINTER
        jsr     Z_POP
        stx     Z_VECTOR2+1
        eor     #$FF
        cmp     Z_VECTOR2+1
        bne     Z_ERROR_0F
        txa
        beq     L1415
        dex
        txa
        asl
        sta     Z_VECTOR2
L1401:  jsr     Z_POP
        ldy     Z_VECTOR2
        sta     Z_LOCAL_VARIABLES+1,y
        txa
        sta     Z_LOCAL_VARIABLES,y
        dec     Z_VECTOR2
        dec     Z_VECTOR2
        dec     Z_VECTOR2+1
        bne     L1401
L1415:  jsr     Z_POP
        stx     Z_PC+1
        sta     $1B
        jsr     Z_POP
        stx     $18
        sta     Z_PC
        lda     #$00
        sta     $1C
        jsr     L11D9
        jmp     L110A

Z_ERROR_0F:  lda     #$0F
        jmp     FATAL_ERROR

; 1OP:140 C jump ?(label)
; Jump (unconditionally) to the given label. (This is not a branch instruction
; and the operand is a 2-byte signed offset to apply to the program counter.)

Z_JUMP:  jsr     L11D9
        jmp     L118C

; 1OP:141 D print_paddr packed-address-of-string
; Print the (Z-encoded) string at the given packed address in high memory

Z_PRINT_PADDR   lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jsr     L1D1C
        jmp     L1D2E

; 1OP:142 E load (variable) -> (result)
; The value of the variable referred to by the operand is stored in the result.

Z_LOAD:  lda     Z_OPERAND1
        jsr     L109D
        jmp     L110A

; 1OP:143 F 1/4 not value -> (result)
; Bitwise NOT (i.e., all 16 bits reversed).

Z_NOT:  lda     Z_OPERAND1
        eor     #$FF
        tax
        lda     Z_OPERAND1+1
        eor     #$FF
L1457:  stx     Z_VECTOR1
        sta     Z_VECTOR1+1
        jmp     L110A

; 2OP:2 2 jl a b ?(label)
; Jump if a < b (using a signed 16-bit comparison).

Z_JL:  jsr     L11D9
        jmp     L1467

; 2OP:4 4 dec_chk (variable) value ?(label)
; Decrement variable, and branch if it is now less than the given value.

Z_DEC_CHK:  jsr     Z_DEC
L1467:  lda     Z_OPERAND2
        sta     Z_VECTOR2
        lda     Z_OPERAND2+1
        sta     Z_VECTOR2+1
        jmp     L1490

; 2OP:3 3 jg a b ?(label)
; Jump if a > b (using a signed 16-bit comparison).

Z_JG:  lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jmp     L1488

; 2OP:5 5 inc_chk (variable) value ?(label)
; Increment variable, and branch if now greater than value.

Z_INC_CHK:  jsr     Z_INC
        lda     Z_VECTOR1
        sta     Z_VECTOR2
        lda     Z_VECTOR1+1
        sta     Z_VECTOR2+1
L1488:  lda     Z_OPERAND2
        sta     Z_VECTOR1
        lda     Z_OPERAND2+1
        sta     Z_VECTOR1+1
L1490:  jsr     L1497
        bcc     L14CD
        bcs     L14BA
L1497:  lda     Z_VECTOR2+1
        eor     Z_VECTOR1+1
        bpl     L14A2
        lda     Z_VECTOR2+1
        cmp     Z_VECTOR1+1
        rts
L14A2:  lda     Z_VECTOR1+1
        cmp     Z_VECTOR2+1
        bne     L14AC
        lda     Z_VECTOR1
        cmp     Z_VECTOR2
L14AC:  rts

; 2OP:6 6 jin obj1 obj2 ?(label)
; Jump if object a is a direct child of b, i.e., if parent of a is b.

Z_JIN:  lda     Z_OPERAND1
        jsr     L1F39
        ldy     #$04
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND2
        beq     L14CD
L14BA:  jmp     L1146

; 2OP:7 7 test bitmap flags ?(label)
; Jump if all of the flags in bitmap are set (i.e. if bitmap & flags == flags).

Z_TEST:  lda     Z_OPERAND2
        and     Z_OPERAND1
        cmp     Z_OPERAND2
        bne     L14BA
        lda     Z_OPERAND2+1
        and     Z_OPERAND1+1
        cmp     Z_OPERAND2+1
        bne     L14BA
L14CD:  jmp     L1152

; 2OP:8 8 or a b -> (result)
; Bitwise OR.

Z_OR:  lda     Z_OPERAND1
        ora     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        ora     Z_OPERAND2+1
        jmp     L1457

; 2OP:9 9 and a b -> (result)
; Bitwise AND.

Z_AND:  lda     Z_OPERAND1
        and     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        and     Z_OPERAND2+1
        jmp     L1457

; 2OP:10 A test_attr object attribute ?(label)
; Jump if object has attribute.

Z_TEST_ATTR:  jsr     L1F95
        lda     Z_VECTOR4+1
        and     Z_VECTOR3+1
        sta     Z_VECTOR4+1
        lda     Z_VECTOR4
        and     Z_VECTOR3
        ora     Z_VECTOR4+1
        bne     L14CD
        jmp     L1146

; 2OP:11 B set_attr object attribute
; Make object have the attribute numbered attribute.

Z_SET_ATTR:  jsr     L1F95
        ldy     #$00
        lda     Z_VECTOR4+1
        ora     Z_VECTOR3+1
        sta     (Z_VECTOR2),y
        iny
        lda     Z_VECTOR4
        ora     Z_VECTOR3
        sta     (Z_VECTOR2),y
        rts

; 2OP:12 C clear_attr object attribute
; Make object not have the attribute numbered attribute.

Z_CLEAR_ATTR:  jsr     L1F95
        ldy     #$00
        lda     Z_VECTOR3+1
        eor     #$FF
        and     Z_VECTOR4+1
        sta     (Z_VECTOR2),y
        iny
        lda     Z_VECTOR3
        eor     #$FF
        and     Z_VECTOR4
        sta     (Z_VECTOR2),y
        rts

; 2OP:13 D store (variable) value
; Set the VARiable referenced by the operand to value.

Z_STORE:  lda     Z_OPERAND2
        sta     Z_VECTOR1
        lda     Z_OPERAND2+1
        sta     Z_VECTOR1+1
        lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

; 2OP:14 E insert_obj object destination
; Moves object O to become the first child of the destination object D.

Z_INSERT_OBJ:  jsr     Z_REMOVE_OBJ
        lda     Z_OPERAND1
        jsr     L1F39
        lda     Z_VECTOR2
        sta     Z_VECTOR3
        lda     Z_VECTOR2+1
        sta     Z_VECTOR3+1
        lda     Z_OPERAND2
        ldy     #$04
        sta     (Z_VECTOR2),y
        jsr     L1F39
        ldy     #$06
        lda     (Z_VECTOR2),y
        tax
        lda     Z_OPERAND1
        sta     (Z_VECTOR2),y
        txa
        beq     L155C
        ldy     #$05
        sta     (Z_VECTOR3),y
L155C:  rts

; 2OP:15 F loadw array word-index -> (result)
; Stores array-->word-index (i.e., the word at address array+2*word-index,
; which must lie in static or dynamic memory).

Z_LOADW:  jsr     L1572
        jsr     L1A4C
L1563:  sta     Z_VECTOR1+1
        jsr     L1A4C
        sta     Z_VECTOR1
        jmp     L110A

; 2OP:16 10 loadb array byte-index -> (result)
; Stores array->byte-index (i.e., the byte at address array+byte-index,
; which must lie in static or dynamic memory).

Z_LOADB:  jsr     L1576
        beq     L1563
L1572:  asl     Z_OPERAND2
        rol     Z_OPERAND2+1
L1576:  lda     Z_OPERAND2
        clc
        adc     Z_OPERAND1
        sta     $1F
        lda     Z_OPERAND2+1
        adc     Z_OPERAND1+1
        sta     $20
        lda     #$00
        sta     $21
        sta     $22
        rts

; 2OP:17 11 get_prop object property -> (result)
; Read property from object (resulting in the default value if it had no such
; declared property). If the property has length 1, the value is only that
; byte. If it has length 2, the first two bytes of the property are taken as
; a word value. It is illegal for the opcode to be used if the property has
; length greater than 2, and the result is unspecified.

Z_GET_PROP:   jsr     L1F62
L158D:  jsr     L1F7E
        cmp     Z_OPERAND2
        beq     L15AF
        bcc     L159C
        jsr     L1F8B
        jmp     L158D
L159C:  lda     Z_OPERAND2
        sec
        sbc     #$01
        asl
        tay
        lda     (Z_OBJECTS_ADDR),y
        sta     Z_VECTOR1+1
        iny
        lda     (Z_OBJECTS_ADDR),y
        sta     Z_VECTOR1
        jmp     L110A
L15AF:  jsr     L1F83
        iny
        tax
        beq     L15BF
        cmp     #$01
        beq     L15C5
        lda     #$07
        jmp     FATAL_ERROR
L15BF:  lda     (Z_VECTOR2),y
        ldx     #$00
        beq     L15CB
L15C5:  lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
L15CB:  sta     Z_VECTOR1
        stx     Z_VECTOR1+1
        jmp     L110A

; 2OP:18 12 get_prop_addr object property -> (result)
; Get the byte address (in dynamic memory) of the property data for the given
; object's property.  This must return 0 if the object hasn't got the property.

Z_GET_PROP_ADDR:  jsr     L1F62
L15D5:  jsr     L1F7E
        cmp     Z_OPERAND2
        beq     L15E4
        bcc     L15FC
        jsr     L1F8B
        jmp     L15D5
L15E4:  inc     Z_VECTOR2
        bne     L15EA
        inc     Z_VECTOR2+1
L15EA:  tya
        clc
        adc     Z_VECTOR2
        sta     Z_VECTOR1
        lda     Z_VECTOR2+1
        adc     #$00
        sec
        sbc     Z_BASE_PAGE
        sta     Z_VECTOR1+1
        jmp     L110A
L15FC:  jmp     L1102

; 2OP:19 13 get_next_prop object property -> (result)
; Gives the number of the next property provided by the quoted object. This
; may be zero, indicating the end of the property list; if called with zero,
; it gives the first property number present. It is illegal to try to find
; the next property of a property which does not exist, and an interpreter
; should halt with an error message (if it can efficiently check this
; condition).

Z_GET_NEXT_PROP:  jsr     L1F62
        lda     Z_OPERAND2
        beq     L1618
L1606:  jsr     L1F7E
        cmp     Z_OPERAND2
        beq     L1615
        bcc     L15FC
        jsr     L1F8B
        jmp     L1606
L1615:  jsr     L1F8B
L1618:  jsr     L1F7E
        jmp     L1104

; 2OP:20 14 add a b -> (result)
; Signed 16-bit addition.

Z_ADD:  lda     Z_OPERAND1
        clc
        adc     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        adc     Z_OPERAND2+1
        jmp     L1457

; 2OP:21 15 sub a b -> (result)
; Signed 16-bit subtraction.

Z_SUB:  lda     Z_OPERAND1
        sec
        sbc     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        sbc     Z_OPERAND2+1
        jmp     L1457

; 2OP:22 16 mul a b -> (result)
; Signed 16-bit multiplication.

Z_MUL:  jsr     L16F2
L163B:  ror     $5B
        ror     $5A
        ror     Z_OPERAND2+1
        ror     Z_OPERAND2
        bcc     L1652
        lda     Z_OPERAND1
        clc
        adc     $5A
        sta     $5A
        lda     Z_OPERAND1+1
        adc     $5B
        sta     $5B
L1652:  dex
        bpl     L163B
        ldx     Z_OPERAND2
        lda     Z_OPERAND2+1
        jmp     L1457

; 2OP:23 17 div a b -> (result)
; Signed 16-bit division. Division by zero should halt the interpreter with a
; suitable error message.

Z_DIV:  jsr     L1670
        ldx     $56
        lda     $57
        jmp     L1457

; 2OP:24 18 mod a b -> (result)
; Remainder after signed 16-bit division. Division by zero should halt the
; interpreter with a suitable error message.

Z_MOD:  jsr     L1670
        ldx     $58
        lda     $59
        jmp     L1457

L1670:  lda     Z_OPERAND1+1
        sta     $5D
        eor     Z_OPERAND2+1
        sta     $5C
        lda     Z_OPERAND1
        sta     $56
        lda     Z_OPERAND1+1
        sta     $57
        bpl     L1685
        jsr     L16AE
L1685:  lda     Z_OPERAND2
        sta     $58
        lda     Z_OPERAND2+1
        sta     $59
        bpl     L1692
        jsr     L16A0
L1692:  jsr     L16BC
        lda     $5C
        bpl     L169C
        jsr     L16AE
L169C:  lda     $5D
        bpl     L16AD
L16A0:  lda     #$00
        sec
        sbc     $58
        sta     $58
        lda     #$00
        sbc     $59
        sta     $59
L16AD:  rts

L16AE:  lda     #$00
        sec
        sbc     $56
        sta     $56
        lda     #$00
        sbc     $57
        sta     $57
        rts

L16BC:  lda     $58
        ora     $59
        beq     Z_ERROR_8
        jsr     L16F2
L16C5:  rol     $56
        rol     $57
        rol     $5A
        rol     $5B
        lda     $5A
        sec
        sbc     $58
        tay
        lda     $5B
        sbc     $59
        bcc     L16DD
        sty     $5A
        sta     $5B
L16DD:  dex
        bne     L16C5
        rol     $56
        rol     $57
        lda     $5A
        sta     $58
        lda     $5B
        sta     $59
        rts

Z_ERROR_8:  lda     #$08
        jmp     FATAL_ERROR

L16F2:  ldx     #$10
        lda     #$00
        sta     $5A
        sta     $5B
        clc
        rts

; 2OP:1 1 je a b ?(label)
; Jump if a is equal to any of the subsequent operands. (Thus @je a never
; jumps and @je a b jumps if a = b.)

Z_JE:  dec     $04
        bne     L1705
        lda     #$09
        jmp     FATAL_ERROR
L1705:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        cmp     Z_OPERAND2
        bne     L1711
        cpx     Z_OPERAND2+1
        beq     L1729
L1711:  dec     $04
        beq     L172C
        cmp     Z_VECTOR0
        bne     L171D
        cpx     Z_VECTOR0+1
        beq     L1729
L171D:  dec     $04
        beq     L172C
        cmp     $0B
        bne     L172C
        cpx     $0C
        bne     L172C
L1729:  jmp     L1152
L172C:  jmp     L1146

; VAR:224 0 1 call routine ...up to 3 args... -> (result)
; The only call instruction in Version 3, Inform reads this as call_vs in
; higher versions: it calls the routine with 0, 1, 2 or 3 arguments as
; supplied and stores the resulting return value. (When the address 0 is
; called as a routine, nothing happens and the return value is false.)

Z_CALL: lda     Z_OPERAND1
        ora     Z_OPERAND1+1
        bne     L1738
        jmp     L1104
L1738:  ldx     $18
        lda     Z_PC
        jsr     Z_PUSH_STACK2
        ldx     Z_PC+1
        lda     $1B
        jsr     Z_PUSH_STACK2
        lda     #$00
        sta     $1C
        asl     Z_OPERAND1
        rol     Z_OPERAND1+1
        rol
        sta     $1B
        lda     Z_OPERAND1+1
        sta     Z_PC+1
        lda     Z_OPERAND1
        sta     Z_PC
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR3
        sta     Z_VECTOR3+1
        beq     L178D
        lda     #$00
        sta     Z_VECTOR2
L1766:  ldy     Z_VECTOR2
        ldx     Z_LOCAL_VARIABLES,y
        lda     Z_LOCAL_VARIABLES+1,y
        sty     Z_VECTOR2
        jsr     Z_PUSH_STACK2
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR2+1
        jsr     FETCH_NEXT_ZBYTE
        ldy     Z_VECTOR2
        sta     Z_LOCAL_VARIABLES,y
        lda     Z_VECTOR2+1
        sta     Z_LOCAL_VARIABLES+1,y
        iny
        iny
        sty     Z_VECTOR2
        dec     Z_VECTOR3
        bne     L1766
L178D:  dec     $04
        beq     L17B7
        lda     Z_OPERAND2
        sta     Z_LOCAL_VARIABLES
        lda     Z_OPERAND2+1
        sta     Z_LOCAL_VARIABLES+1
        dec     $04
        beq     L17B7
        lda     Z_VECTOR0
        sta     Z_LOCAL_VARIABLES + 2
        lda     Z_VECTOR0+1
        sta     Z_LOCAL_VARIABLES + 3
        dec     $04
        beq     L17B7
        lda     $0B
        sta     Z_LOCAL_VARIABLES + 4
        lda     $0C
        sta     Z_LOCAL_VARIABLES + 5
L17B7:  ldx     Z_VECTOR3+1
        txa
        eor     #$FF
        jsr     Z_PUSH_STACK2
        lda     Z_STACK_POINTER
        sta     $18
        rts

; VAR:225 1 storew array word-index value
; array-->word-index = value, i.e. stores the given value in the word at
; address array+2*wordindex (which must lie in dynamic memory).

Z_STOREW:  asl     Z_OPERAND2
        rol     Z_OPERAND2+1
        jsr     L17DA
        lda     Z_VECTOR0+1
        sta     (Z_VECTOR2),y
        iny
        bne     L17D5

; VAR:226 2 storeb array byte-index value
; array->byte-index = value, i.e. stores the given value in the byte at
; address array+byte-index (which must lie in dynamic memory). (See loadb.)

Z_STOREB:  jsr     L17DA
L17D5:  lda     Z_VECTOR0
        sta     (Z_VECTOR2),y
        rts

L17DA:  lda     Z_OPERAND2
        clc
        adc     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND2+1
        adc     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_VECTOR2+1
        ldy     #$00
        rts

; VAR:227 3 put_prop object property value
; Writes the given value to the given property of the given object. If the
; property does not exist for that object, the interpreter should halt with a
; suitable error message. If the property length is 1, then the interpreter
; should store only the least significant byte of the value. (For instance,
; storing -1 into a 1-byte property results in the property value 255.)
; As with get_prop the property length must not be more than 2: if it is,
; the behaviour of the opcode is undefined.

Z_PUT_PROP:  jsr     L1F62
L17F0:  jsr     L1F7E
        cmp     Z_OPERAND2
        beq     L17FF
        bcc     Z_ERROR_0A		; boom
        jsr     L1F8B
        jmp     L17F0
L17FF:  jsr     L1F83
        iny
        tax
        beq     L180F
        cmp     #$01
        bne     Z_ERROR_0B
        lda     Z_VECTOR0+1
        sta     (Z_VECTOR2),y
        iny
L180F:  lda     Z_VECTOR0
        sta     (Z_VECTOR2),y
        rts

Z_ERROR_0A:
	lda     #$0A
        jmp     FATAL_ERROR
Z_ERROR_0B:
	lda     #$0B
        jmp     FATAL_ERROR

; VAR:229 5 print_char output-character-code
; Print a ZSCII character. The operand must be a character code defined in
; ZSCII for output (see S3). In particular, it must certainly not be negative
; or larger than 1023.

Z_PRINT_CHAR:  lda     Z_OPERAND1
        jmp     PUT_CHAR_ALT

; VAR:230 6 print_num value
; Print (signed) number in decimal.

Z_PRINT_NUM:  lda     Z_OPERAND1
        sta     $56
        lda     Z_OPERAND1+1
        sta     $57
L182B:  lda     $57
        bpl     L1837
        lda     #$2D
        jsr     PUT_CHAR_ALT
        jsr     L16AE
L1837:  lda     #$00
        sta     $5E
L183B:  lda     $56
        ora     $57
        beq     L1853
        lda     #$0A
        sta     $58
        lda     #$00
        sta     $59
        jsr     L16BC
        lda     $58
        pha
        inc     $5E
        bne     L183B
L1853:  lda     $5E
        bne     L185C
        lda     #$30
        jmp     PUT_CHAR_ALT
L185C:  pla
        clc
        adc     #$30
        jsr     PUT_CHAR_ALT
        dec     $5E
        bne     L185C
        rts

; VAR:231 7 random range -> (result)
; If range is positive, returns a uniformly random number between 1 and range.
; If range is negative, the random number generator is seeded to that value
; and the return value is 0. Most interpreters consider giving 0 as range
; illegal (because they attempt a division with remainder by the range), but
; correct behaviour is to reseed the generator in as random a way as the
; interpreter can (e.g. by using the time in milliseconds).

Z_RANDOM:
        lda     Z_OPERAND1
        sta     Z_OPERAND2
        lda     Z_OPERAND1+1
        sta     Z_OPERAND2+1
        jsr     READ_SID_RANDOM
        stx     Z_OPERAND1
        and     #$7F
        sta     Z_OPERAND1+1
        jsr     L1670
        lda     $58
        sta     Z_VECTOR1
        lda     $59
        sta     Z_VECTOR1+1
        jsr     INC_VECTOR1
        jmp     L110A

; VAR:232 8 push value
; Pushes value onto the game stack.

Z_PUSH:  ldx     Z_OPERAND1
        lda	Z_OPERAND1+1
	jmp	Z_PUSH_STACK2

; VAR:233 9 1 pull (variable)
; Pulls value off a stack. (If the stack underflows, the interpreter should
; halt with a suitable error message.)

Z_PULL:  jsr     Z_POP
        lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

; VAR:228 4 1 sread text parse
; This opcode reads a whole command from the keyboard (no prompt is
; automatically displayed).
; It is legal for this to be called with the cursor at any position on any
; window.
; In Versions 1 to 3, the status line is automatically redisplayed first.
; A sequence of characters is read in from the current input stream until a
; carriage return (or, in Versions 5 and later, any terminating character)
; is found.
; In Versions 1 to 4, byte 0 of the text-buffer should initially contain the
; maximum number of letters which can be typed, minus 1 (the interpreter
; should not accept more than this). The text typed is reduced to lower case
; (so that it can tidily be printed back by the program if need be) and stored
; in bytes 1 onward, with a zero terminator (but without any other terminator,
; such as a carriage return code). (This means that if byte 0 contains n then
; the buffer must contain n+1 bytes, which makes it a string array of length n
; in Inform terminology.)

Z_SREAD:  jsr     Z_SHOW_STATUS
        lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_OPERAND1+1
        lda     Z_OPERAND2+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_OPERAND2+1
        jsr     L23C3
        sta     $45
        lda     #$00
        sta     $46
        ldy     #$01
        sta     (Z_OPERAND2),y
        sty     $43
        iny
        sty     $44
L18BC:  ldy     #$00
        lda     (Z_OPERAND2),y
        beq     L18C6
        cmp     #$3C
        bcc     L18CA
L18C6:  lda     #$3B
        sta     (Z_OPERAND2),y
L18CA:  iny
        cmp     (Z_OPERAND2),y
        bcc     L18D5
        lda     $45
        ora     $46
        bne     L18D6
L18D5:  rts
L18D6:  lda     $46
        cmp     #$06
        bcc     L18DF
        jsr     L196D
L18DF:  lda     $46
        bne     L1907
        ldx     #$05
L18E5:  sta     $37,x
        dex
        bpl     L18E5
        jsr     L195F
        lda     $43
        ldy     #$03
        sta     ($47),y
        tay
        lda     (Z_OPERAND1),y
        jsr     L199A
        bcs     L1921
        jsr     L1988
        bcc     L1907
        inc     $43
        dec     $45
        jmp     L18BC
L1907:  lda     $45
        beq     L1929
        ldy     $43
        lda     (Z_OPERAND1),y
        jsr     L1983
        bcs     L1929
        ldx     $46
        sta     $37,x
        dec     $45
        inc     $46
        inc     $43
        jmp     L18BC
L1921:  sta     $37
        dec     $45
        inc     $46
        inc     $43
L1929:  lda     $46
        beq     L18BC
        jsr     L195F
        lda     $46
        ldy     #$02
        sta     ($47),y
        jsr     L1E4A
        jsr     L19AC
        ldy     #$01
        lda     (Z_OPERAND2),y
        clc
        adc     #$01
        sta     (Z_OPERAND2),y
        jsr     L195F
        ldy     #$00
        sty     $46
        lda     Z_VECTOR1+1
        sta     ($47),y
        iny
        lda     Z_VECTOR1
        sta     ($47),y
        lda     $44
        clc
        adc     #$04
        sta     $44
        jmp     L18BC
L195F:  lda     Z_OPERAND2
        clc
        adc     $44
        sta     $47
        lda     Z_OPERAND2+1
        adc     #$00
        sta     $48
        rts

L196D:  lda     $45
        beq     L1982
        ldy     $43
        lda     (Z_OPERAND1),y
        jsr     L1983
        bcs     L1982
        dec     $45
        inc     $46
        inc     $43
        bne     L196D
L1982:  rts

L1983:  jsr     L199A
        bcs     L19AA
L1988:  ldx     #$05
L198A:  cmp     PUNCTUATION,x
        beq     L19AA
        dex
        bpl     L198A
        clc
        rts

L199A:  tax
        ldy     #$00
        lda     (Z_DICT_ADDR),y
        tay
        txa
L19A1:  cmp     (Z_DICT_ADDR),y
        beq     L19AA
        dey
        bne     L19A1
        clc
        rts
L19AA:  sec
        rts

L19AC:  ldy     #$00
        lda     (Z_DICT_ADDR),y
        clc
        adc     #$01
        adc     Z_DICT_ADDR
        sta     Z_VECTOR1
        lda     Z_DICT_ADDR+1
        adc     #$00
        sta     Z_VECTOR1+1
        lda     (Z_VECTOR1),y
        sta     $4B
        jsr     INC_VECTOR1
        lda     (Z_VECTOR1),y
        sta     $4A
        jsr     INC_VECTOR1
        lda     (Z_VECTOR1),y
        sta     $49
        jsr     INC_VECTOR1
L19D2:  ldy     #$00
        lda     (Z_VECTOR1),y
        cmp     $3D
        bne     L19EF
        iny
        lda     (Z_VECTOR1),y
        cmp     $3E
        bne     L19EF
        iny
        lda     (Z_VECTOR1),y
        cmp     $3F
        bne     L19EF
        iny
        lda     (Z_VECTOR1),y
        cmp     $40
        beq     L1A0E
L19EF:  lda     $4B
        clc
        adc     Z_VECTOR1
        sta     Z_VECTOR1
        bcc     L19FA
        inc     Z_VECTOR1+1
L19FA:  lda     $49
        sec
        sbc     #$01
        sta     $49
        bcs     L1A05
        dec     $4A
L1A05:  ora     $4A
        bne     L19D2
        sta     Z_VECTOR1
        sta     Z_VECTOR1+1
        rts

L1A0E:  lda     Z_VECTOR1+1
        sec
        sbc     Z_BASE_PAGE
        sta     Z_VECTOR1+1
        rts

FETCH_NEXT_ZBYTE:  lda     $1C
        bne     L1A38
        lda     Z_PC+1
        ldy     $1B
        bne     L1A28
        cmp     Z_RESIDENT_ADDR		; address above resident?
        bcs     L1A28			; if so, fetch it from storage
        adc     Z_BASE_PAGE
        bne     L1A2F
L1A28:  ldx     #$00
        stx     $22
        jsr     FETCH_PAGE
L1A2F:  sta     $1E
        ldx     #$FF
        stx     $1C
        inx
        stx     $1D
L1A38:  ldy     Z_PC
        lda     ($1D),y
        inc     Z_PC
        bne     L1A4A
        ldy     #$00
        sty     $1C
        inc     Z_PC+1
        bne     L1A4A
        inc     $1B
L1A4A:  tay
        rts

L1A4C:  lda     $22
        bne     L1A6E
        lda     $20
        ldy     $21
        bne     L1A5E
        cmp     Z_RESIDENT_ADDR
        bcs     L1A5E
        adc     Z_BASE_PAGE
        bne     L1A65
L1A5E:  ldx     #$00
        stx     $1C
        jsr     FETCH_PAGE
L1A65:  sta     $24
        ldx     #$FF
        stx     $22
        inx
        stx     $23
L1A6E:  ldy     $1F
        lda     ($23),y
        inc     $1F
        bne     L1A80
        ldy     #$00
        sty     $22
        inc     $20
        bne     L1A80
        inc     $21
L1A80:  tay
        rts

FETCH_PAGE
.(
	sta     Z_STORY_INDEX+1
        sty     Z_STORY_INDEX+2
        ldx     #$00
        stx     Z_STORY_INDEX
L1A8A:  cmp     $0B00,x
        bne     L1A97
        tya
        cmp     $0BA0,x
        beq     L1AC5
        lda     Z_STORY_INDEX+1
L1A97:  inc     Z_STORY_INDEX
        inx
        cpx     $29
        bcc     L1A8A
        jsr     L1B47
        ldx     $2E
        stx     Z_STORY_INDEX
        lda     Z_STORY_INDEX+1
        sta     $0B00,x
        sta     STORY_INDEX
        lda     Z_STORY_INDEX+2
        and     #$01
        sta     $0BA0,x
        sta     STORY_INDEX+1
        txa
        clc
        adc     Z_RESIDENT_ADDR+1
        sta     PAGE_VECTOR+1

; we're inlining REU_FETCH -- no reason to keep it separate

;	jsr	REU_FETCH

; 1AF2 (1AEF on non-EasyFlash)
REU_FETCH
.(
        jsr     UIEC_ONLY
        bcc     L1
        clc
	ldx	STORY_INDEX+1
	lda	STORY_INDEX
	jsr	IEC_FETCH
	jmp	L2

L1	lda     STORY_INDEX+1		; highbyte (these are big-endian)
        and     #$01			; we only use bank 0 and 1
        sta     SCRATCH			; save for a moment
        lda     STORY_INDEX		; lowbyte
        sec
        sbc     Z_RESIDENT_ADDR		; subtract from rez to get REU page
        tay				; pha
        lda     SCRATCH
        sbc     #$00
        tax

	jsr	IREU_FETCH
L2
	jsr	SECBUF_TO_PVEC
;	rts
.)


L1AC5
	ldy     Z_STORY_INDEX
        lda     Z_STORY_PAGE_INDEX,y
        cmp     $2D
        beq     L1AF5
        inc     $2D
        bne     L1AEE
        jsr     L1B61
        ldx     #$00
L1AD7:  lda     Z_STORY_PAGE_INDEX,x
        beq     L1AE2
        sec
        sbc     $25
        sta     Z_STORY_PAGE_INDEX,x
L1AE2:  inx
        cpx     $29
        bcc     L1AD7
        lda     #$00
        sec
        sbc     $25
        sta     $2D
L1AEE:  lda     $2D
        ldy     Z_STORY_INDEX
        sta     Z_STORY_PAGE_INDEX,y
L1AF5:  lda     Z_STORY_INDEX
        clc
        adc     Z_RESIDENT_ADDR+1
        rts
.)

L1B47:  ldx     #$00
        stx     $2E
        lda     Z_STORY_PAGE_INDEX
        inx
L1B4F:  cmp     Z_STORY_PAGE_INDEX,x
        bcc     L1B59
        lda     Z_STORY_PAGE_INDEX,x
        stx     $2E
L1B59:  inx
        cpx     $29
        bcc     L1B4F
        sta     $25
        rts

L1B61:  ldx     #$00
        stx     $2E
L1B65:  lda     Z_STORY_PAGE_INDEX,x
        bne     L1B71
        inx
        cpx     $29
        bcc     L1B65
        bcs     L1B84
L1B71:  inx
L1B72:  cmp     Z_STORY_PAGE_INDEX,x
        bcc     L1B7F
        ldy     Z_STORY_PAGE_INDEX,x
        beq     L1B7F
        tya
        stx     $2E
L1B7F:  inx
        cpx     $29
        bcc     L1B72
L1B84:  sta     $25
        rts

L1B87:  lda     Z_VECTOR2
        sta     $1F
        lda     Z_VECTOR2+1
        sta     $20
        lda     #$00
        sta     $21
        sta     $22
        rts

REU_LOAD_STORY
	ldy	#$01
	ldx	#$0d
	clc
	jsr	PLOT
	ldx	#<REU_TXT
	lda	#>REU_TXT
	ldy	#$28
	jsr	PRINT_MESSAGE

	lda     Z_HDR_FILE_LENGTH+1
        sta     Z_VECTOR3
        lda     Z_HDR_FILE_LENGTH
        ldy     #$06
L1C4A:  lsr
        ror     Z_VECTOR3
        dey
        bpl     L1C4A
        sta     Z_VECTOR3+1
        sec
        lda     Z_VECTOR3
        sbc     Z_RESIDENT_ADDR
        sta     Z_VECTOR3
        lda     Z_VECTOR3+1
        sbc     #$00
        sta     Z_VECTOR3+1
        inc     Z_VECTOR3
        inc     Z_VECTOR3
        lda     #$00
        sta     Z_VECTOR2+1
        sta     Z_VECTOR2
        sta     Z_VECTOR4
L1C74:  jsr     DEC_PAGE_COUNT			; want to put breakpoint here
        bcc     L1C85
;	jsr	DO_TWIRLY
        lda     #>SECTOR_BUFFER
        sta     PAGE_VECTOR+1
	ldx	#5
        jsr     READ_BUFFER
        bcc     REU_STASH
        jmp     FATAL_ERROR_0E
L1C85
        rts

REU_STASH:
.(
	jsr	IREU_STASH
	inc     Z_VECTOR2+1
        bne     L1C74
        inc     Z_VECTOR4
        jmp     L1C74
.)

DEC_PAGE_COUNT
	lda     Z_VECTOR3
        sec
        sbc     #$01
        sta     Z_VECTOR3
        lda     Z_VECTOR3+1
        sbc     #$00
        sta     Z_VECTOR3+1
        rts

L1D1C:  lda     Z_VECTOR2
        asl
        sta     $1F
        lda     Z_VECTOR2+1
        rol
        sta     $20
        lda     #$00
        sta     $22
        rol
        sta     $21
L1D2D:  rts

L1D2E:  ldx     #$00
        stx     $4C
        stx     $50
        dex
        stx     $4D
L1D37:  jsr     L1E02
        bcs     L1D2D
        sta     $4E
        tax
        beq     L1D82
L1D41:  cmp     #$04
        bcc     L1DA0
        cmp     #$06
        bcc     L1D86
        jsr     L1DF6
        tax
        bne     L1D5A
        lda     #$5B
L1D51:  clc
        adc     $4E
L1D54:  jsr     PUT_CHAR_ALT
        jmp     L1D37

L1D5A:  cmp     #$01
        bne     L1D62
        lda     #$3B
        bne     L1D51
L1D62:  lda     $4E
        sec
        sbc     #$06
        beq     L1D70
        tax
        lda     VALID_PUNCTUATION,x
        jmp     L1D54

L1D70:  jsr     L1E02
        asl
        asl
        asl
        asl
        asl
        sta     $4E
        jsr     L1E02
        ora     $4E
        jmp     L1D54

L1D82:  lda     #$20
        bne     L1D54
L1D86:  sec
        sbc     #$03
        tay
        jsr     L1DF6
        bne     L1D94
        sty     $4D
        jmp     L1D37

L1D94:  sty     $4C
        cmp     $4C
        beq     L1D37
        lda     #$00
        sta     $4C
        beq     L1D37
L1DA0:  sec
        sbc     #$01
        asl
        asl
        asl
        asl
        asl
        asl
        sta     $4F
        jsr     L1E02
        asl
        clc
        adc     $4F
        tay
        lda     (Z_ABBREV_ADDR),y
        sta     Z_VECTOR2+1
        iny
        lda     (Z_ABBREV_ADDR),y
        sta     Z_VECTOR2
        lda     $21
        pha
        lda     $20
        pha
        lda     $1F
        pha
        lda     $4C
        pha
        lda     $50
        pha
        lda     $52
        pha
        lda     $51
        pha
        jsr     L1D1C
        jsr     L1D2E
        pla
        sta     $51
        pla
        sta     $52
        pla
        sta     $50
        pla
        sta     $4C
        pla
        sta     $1F
        pla
        sta     $20
        pla
        sta     $21
        ldx     #$FF
        stx     $4D
        inx
        stx     $22
        jmp     L1D37

L1DF6:  lda     $4D
        bpl     L1DFD
        lda     $4C
        rts

L1DFD:  ldy     #$FF
        sty     $4D
        rts

L1E02:  lda     $50
        bpl     L1E08
        sec
        rts

L1E08:  bne     L1E1D
        inc     $50
        jsr     L1A4C
        sta     $52
        jsr     L1A4C
        sta     $51
        lda     $52
        lsr
        lsr
        jmp     L1E46

L1E1D:  sec
        sbc     #$01
        bne     L1E38
        lda     #$02
        sta     $50
        lda     $51
        sta     Z_VECTOR2
        lda     $52
        asl     Z_VECTOR2
        rol
        asl     Z_VECTOR2
        rol
        asl     Z_VECTOR2
        rol
        jmp     L1E46

L1E38:  lda     #$00
        sta     $50
        lda     $52
        bpl     L1E44
        lda     #$FF
        sta     $50
L1E44:  lda     $51
L1E46:  and     #$1F
        clc
        rts

L1E4A:  lda     #$05
        tax
L1E4D:  sta     $3D,x
        dex
        bpl     L1E4D
        lda     #$06
        sta     $53
        lda     #$00
        sta     $54
        sta     $55
L1E5C:  ldx     $54
        inc     $54
        lda     $37,x
        sta     $4E
        bne     L1E6A
        lda     #$05
        bne     L1E96
L1E6A:  lda     $4E
        jsr     L1EE0
        beq     L1E91
        clc
        adc     #$03
        ldx     $55
        sta     $3D,x
        inc     $55
        dec     $53
        bne     L1E81
        jmp     L1EF9

L1E81:  lda     $4E
        jsr     L1EE0
        cmp     #$02
        beq     L1EA3
        lda     $4E
        sec
        sbc     #$3B
        bpl     L1E96
L1E91:  lda     $4E
        sec
        sbc     #$5B
L1E96:  ldx     $55
        sta     $3D,x
        inc     $55
        dec     $53
        bne     L1E5C
        jmp     L1EF9

L1EA3:  lda     $4E
        jsr     L1ED0
        bne     L1E96
        lda     #$06
        ldx     $55
        sta     $3D,x
        inc     $55
        dec     $53
        beq     L1EF9
        lda     $4E
        lsr
        lsr
        lsr
        lsr
        lsr
        and     #$03
        ldx     $55
        sta     $3D,x
        inc     $55
        dec     $53
        beq     L1EF9
        lda     $4E
        and     #$1F
        jmp     L1E96

L1ED0:  ldx     #$19
L1ED2:  cmp     VALID_PUNCTUATION,x
        beq     L1EDB
        dex
        bne     L1ED2
        rts

L1EDB:  txa
        clc
        adc     #$06
        rts

L1EE0:  cmp     #$61
        bcc     L1EEB
        cmp     #$7B
        bcs     L1EEB
        lda     #$00
        rts

L1EEB:  cmp     #$41
        bcc     L1EF6
        cmp     #$5B
        bcs     L1EF6
        lda     #$01
        rts

L1EF6:  lda     #$02
        rts

L1EF9:  lda     $3E
        asl
        asl
        asl
        asl
        rol     $3D
        asl
        rol     $3D
        ora     $3F
        sta     $3E
        lda     $41
        asl
        asl
        asl
        asl
        rol     $40
        asl
        rol     $40
        ora     $42
        tax
        lda     $40
        ora     #$80
        sta     $3F
        stx     $40
        rts

L1F39:  sta     Z_VECTOR2
        ldx     #$00
L1F39A  stx     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        clc
        adc     Z_VECTOR2
        bcc     L1F4F
        inc     Z_VECTOR2+1
L1F4F:  clc
        adc     #$35
        bcc     L1F56
        inc     Z_VECTOR2+1
L1F56:  clc
        adc     Z_OBJECTS_ADDR
        sta     Z_VECTOR2
        lda     Z_VECTOR2+1
        adc     Z_OBJECTS_ADDR+1
        sta     Z_VECTOR2+1
        rts

L1F62:
	lda     Z_OPERAND1
        jsr     L1F39
        ldy     #$07
        lda     (Z_VECTOR2),y
        clc
        adc     Z_BASE_PAGE
        tax
        iny
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR2
        stx     Z_VECTOR2+1
        ldy     #$00
        lda     (Z_VECTOR2),y
        asl
        tay
        iny
        rts

L1F7E:  lda     (Z_VECTOR2),y
        and     #$1F
        rts

L1F83:  lda     (Z_VECTOR2),y
        lsr
        lsr
        lsr
        lsr
        lsr
        rts

L1F8B:  jsr     L1F83
        tax
L1F8F:  iny
        dex
        bpl     L1F8F
        iny
        rts

L1F95:  lda     Z_OPERAND1
        jsr     L1F39
        lda     Z_OPERAND2
        cmp     #$10
        bcc     L1FAF
        sbc     #$10
        tax
        lda     Z_VECTOR2
        clc
        adc     #$02
        sta     Z_VECTOR2
        bcc     L1FAE
        inc     Z_VECTOR2+1
L1FAE:  txa
L1FAF:  sta     Z_VECTOR4
        ldx     #$01
        stx     Z_VECTOR3
        dex
        stx     Z_VECTOR3+1
        lda     #$0F
        sec
        sbc     Z_VECTOR4
        tax
        beq     L1FC7
L1FC0:  asl     Z_VECTOR3
        rol     Z_VECTOR3+1
        dex
        bne     L1FC0
L1FC7:  ldy     #$00
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR4+1
        iny
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR4
        rts

FATAL_ERROR
.(
	ldy     #$01
L1	jsr     NUMBER_TO_DIGIT
        ora     #$30
	sta     INT_ERROR_TEXT+15,y
        txa
        dey
        bpl     L1
        jsr     CLRCHN
	clc
        jsr     Z_NEW_LINE
        ldx     #<INT_ERROR_TEXT
        lda     #>INT_ERROR_TEXT
        ldy     #$12
        jsr     PRINT_MESSAGE
.)

Z_QUIT
.(
	jsr     Z_NEW_LINE
        ldx     #<END_SESSION_TEXT
        lda     #>END_SESSION_TEXT
	ldy     #$10
        jsr     PRINT_MESSAGE
DIE:	jmp     DIE
.)

; 0OP:183 7 1 restart
; Restart the game. (Any "Are you sure?" question must be asked by the game,
; not the interpreter.)
; The only pieces of information surviving from the previous state are the
; "transcribing to printer" bit (bit 0 of 'Flags 2' in the header, at address
; $10) and the "use fixed pitch font" bit (bit 1 of 'Flags 2').
; In particular, changing the program start address before a restart will not
; have the effect of restarting from this new address.

Z_RESTART
.(
	jsr     Z_NEW_LINE
	lda     Z_HDR_FLAGS2+1
        and     #$01
        sta     INTERP_FLAGS
        jmp     STARTUP
.)

PRINT_VERSION
.(
	jsr     Z_NEW_LINE
        ldx     #<VERSION_TEXT
        lda     #>VERSION_TEXT
        ldy     #VERSION_LENGTH
        jmp     PRINT_MESSAGE
.)

GET_MAX_PAGE
.(
	lda	#MAX_RAM_PAGE
        rts
.)

READ_SID_RANDOM
.(
	lda     RANDOM
        ldx     RASTER
        rts
.)

; this seems kinda redundant, but okay ...


PUT_CHAR_ALT:  cmp	#$0d
	beq	Z_NEW_LINE
        cmp     #$20
L206C:  bcc     L2079
        ldx     $60
        sta     INPUT_BUFFER,x
	cpx	#SCREEN_WIDTH-1
        bcs     L207A
        inc     $60
L2079:  rts
L207A:  lda     #$20		; we're at column 40, are we a space?
L207C:  cmp     INPUT_BUFFER,x
        beq     L2086
        dex			; if not, rewind until we can find a space
        bne     L207C
	ldx	#SCREEN_WIDTH-1
L2086:  stx     $61
        stx     $60
        jsr     Z_NEW_LINE
        ldx     $61
        ldy     #$00
L2091:  inx
	cpx	#SCREEN_WIDTH-1
        bcc     L209B
        beq     L209B
        sty     $60
        rts
L209B:  lda     INPUT_BUFFER,x
        sta     INPUT_BUFFER,y
        iny
        bne     L2091

Z_NEW_LINE:  inc     $65
        lda     $65
        cmp     $66
        bcc     L20ED
        jsr     Z_SHOW_STATUS
        lda     #$00
        sta     $65
        sta     COLOR
        sta     $C6
        sec
        jsr     PLOT
        sty     $63
        stx     $64
        ldx     #<MORE_TEXT
        lda     #>MORE_TEXT
        ldy     #$06
        jsr     PRINT_MESSAGE
L20C9:  jsr     GETIN
        tax
        beq     L20C9
        ldy     $63
        ldx     $64
        clc
        jsr     PLOT
        lda     #$01
        sta     COLOR
        ldx     #<BLANK_TEXT
        lda     #>BLANK_TEXT
        ldy     #$06
        jsr     PRINT_MESSAGE
        ldy     $63
        ldx     $64
        clc
        jsr     PLOT
L20ED:  ldx     $60
        lda     #$0D
        sta     INPUT_BUFFER,x
        inc     $60
L20F6:  ldy     $60
        beq     L210B
        sty     $6F
        ldx     #$00
L20FE:  lda     INPUT_BUFFER,x
        jsr     PRINT_CHAR_AT_COORDINATE
        inx
        dey
        bne     L20FE
        jsr     LOG_TO_PRINTER
L210B:  lda     #$00
        sta     $60
        rts

; 0OP:188 C 3 show_status
; (In Version 3 only.) Display and update the status line now (don't wait
; until the next keyboard input). (In theory this opcode is illegal in later
; Versions but an interpreter should treat it as nop, because Version 5
; Release 23 of 'Wishbringer' contains this opcode by accident.)

Z_SHOW_STATUS
.(
	sec
        jsr     PLOT
        sty     $63
        stx     $64	; save current coordinates in $63/$64
        lda     $60
        pha
        lda     $21
        pha
        lda     $20
        pha
        lda     $1F
        pha
        lda     $4D
        pha
        lda     $4C
        pha
        lda     $52
        pha
        lda     $51
        pha
        lda     $50
        pha
        lda     $5E
        pha
        ldx     #$27
L2151:  lda     INPUT_BUFFER,x
        sta     Z_LOCAL_VARIABLES + $20,x
        lda     #$20
        sta     INPUT_BUFFER,x
        dex
        bpl     L2151
        lda     #$00
        sta     $60
        sta     COLOR
        lda     #$13		; set cursor to home (0,0)
        jsr     CHROUT
        lda     #$12		; turn on reverse
        jsr     CHROUT
        lda     #$10
        jsr     READ_GLOBAL_WORD
        lda     Z_VECTOR1
        jsr     L13CF
        lda     #$18
        sta     $60
        lda     #$11
        jsr     READ_GLOBAL_WORD
        lda     Z_FLAGS	; 0=score/turns, 1=hours:mins
        bne     SHOW_TIME
	ldy	#0
L21DEa	lda	SCORE_TEXT,y
	jsr	PUT_CHAR_ALT
	iny
	cpy	#7
	bne L21DEa
        lda     Z_VECTOR1
        sta     $56
        lda     Z_VECTOR1+1
        sta     $57
        jsr     L182B
        lda     #$2F
        bne     L21F0
SHOW_TIME:
	ldy	#0
L21DFa	lda	TIME_TEXT,y
        jsr     PUT_CHAR_ALT
	iny
	cpy	#6
	bne 	L21DFa
        lda     Z_VECTOR1
        bne     L21DF
        lda     #$18
L21DF:  cmp     #$0D
        bcc     L21E5
        sbc     #$0C
L21E5:  sta     $56
        lda     #$00
        sta     $57
        jsr     L182B
        lda     #$3A
L21F0:  jsr     PUT_CHAR_ALT
        lda     #$12
        jsr     READ_GLOBAL_WORD
        lda     Z_VECTOR1
        sta     $56
        lda     Z_VECTOR1+1
        sta     $57
        lda     Z_FLAGS
        bne     L220A
        jsr     L182B
        jmp     L2236
L220A:  lda     Z_VECTOR1
        cmp     #$0A
        bcs     L2215
        lda     #$30
        jsr     PUT_CHAR_ALT
L2215:  jsr     L182B
        lda     #$20
        jsr     PUT_CHAR_ALT
        lda     #$11
        jsr     READ_GLOBAL_WORD
        lda     Z_VECTOR1
        cmp     #$0C
        bcs     L222C
        lda     #$41
        bne     L222E
L222C:  lda     #$50
L222E:  jsr     PUT_CHAR_ALT
        lda     #$4D
        jsr     PUT_CHAR_ALT
L2236:  lda     #$28
        sta     $60
        jsr     L20ED
        ldx     #$27
L223F:  lda     Z_LOCAL_VARIABLES + $20,x
        sta     INPUT_BUFFER,x
        dex
        bpl     L223F
        pla
        sta     $5E
        pla
        sta     $50
        pla
        sta     $51
        pla
        sta     $52
        pla
        sta     $4C
        pla
        sta     $4D
        pla
        sta     $1F
        pla
        sta     $20
        pla
        sta     $21
        pla
        sta     $60
        ldx     $64
        ldy     $63
        clc
        jsr     PLOT	; restore original position
        ldx     #$00
        stx     $22
        inx
        stx     COLOR
        rts
.)

;
; Get a keypress, return in accumulator
;

GET_KEY:  txa
        pha
        tya
        pha
GET_KEY_RETRY:  ldx     #$FF
        stx     $0340
        inx
        stx     $7B
        stx     $7C
        sec
        jsr     PLOT
        txa
        asl
        asl
        asl
        clc
        adc     #$39
        sta     SP0Y
        tya
        cmp     #SCREEN_WIDTH
        bcc     L229D
        sbc     #SCREEN_WIDTH
L229D:  ldx     #$00
        cmp     #$1D
        bcc     L22A4
        inx
L22A4:  stx     MSIGX
        asl
        asl
        asl
        clc
        adc     #$18
        sta     SP0X
L22B0:  jsr     GETIN
        tax
        inc     $7B
        bne     L22C8
        inc     $7C
        bne     L22C8
        lda     #$E0
        sta     $7C
        lda     $0340
        eor     #$FF
        sta     $0340
L22C8:  txa
        beq     L22B0
        cmp     #"a"	; are we between "a" and "z"
        bcc     L22D5
        cmp     #"["
        bcs     L22D5
        adc     #$20	; yes, convert from PETSCII to ASCII and continue
L22D5:  and     #$7F	; strip high bit -- only valid ASCII from here.
        cmp     #$0D	; enter?
        beq     KEY_CLICK_SOUND
        cmp     #$14	; delete?
        beq     KEY_CLICK_SOUND
        cmp     #$20	; space?
        bcc     L22FF
        cmp     #$3C	; less-than?
        bne     L22EB
        lda     #$2C	; comma? 
        bne     KEY_CLICK_SOUND
L22EB:  cmp     #$3E	; greater-than?
        bne     L22F3
        lda     #$2E	; period?
        bne     KEY_CLICK_SOUND
L22F3:  cmp     #$7B	; something greater than "Z"?
        bcs     L22FF
        cmp     #$61	; something equal to or greater than "A"?
        bcs     KEY_CLICK_SOUND
        cmp     #$5B	; same but for lowercase ...
        bcc     KEY_CLICK_SOUND
L22FF:  jsr     ERROR_SOUND
        jmp     GET_KEY_RETRY

KEY_CLICK_SOUND:  sta     Z_TEMP1
        lda     #$1E
        sta     FRELO1
        lda     #$86
        sta     FREHI1
        lda     #$00
        tay
        sta     SUREL1
        lda	#$8f
        sta     SIGVOL
        lda     #$11
        sta     VCREG1
L2321:  dey
        bne     L2321
        sty     VCREG1
        lda     #$80
        sta     SIGVOL
        pla
        tay
        pla
        tax
        lda     Z_TEMP1
        rts

; This takes ASCII as a source, not PETSCII!


PUT_CHARACTER
.(
	cmp     #$61
        bcc     L2340
        cmp     #$7B
        bcs     L234D
        and     #$5F
        jmp     CHROUT
L2340:  cmp     #$41
        bcc     L234D
        cmp     #$5B
        bcs     L234D
        ora     #$20
        jmp     CHROUT
L234D:  cmp     #$5F
        bne     L2355
        lda     #$AF
        bne     L235B
L2355:  cmp     #$7C
        bne     L235B
        lda     #$7D
L235B:  jmp     CHROUT
.)

PRINT_CHAR_AT_COORDINATE
	sta     Z_TEMP1
        txa
        pha
        tya
        pha
        sec
        jsr     PLOT
        tya
        cmp     #SCREEN_WIDTH
        bcc     L2370
        sbc     #SCREEN_WIDTH
        tay
L2370:  lda     Z_TEMP1
        cmp     #$0D
        beq     L23BD
        cpx     #$17
        bcc     L23B3
        cpy     #$27
        bcc     L23B3
L237E:  dex
        clc
        jsr     PLOT
        ldx     $68
L2385:  cpx     #24
        beq     L23A9
        lda     VIC_ROW_ADDR_LO,x
        sta     $6C
        lda     VIC_ROW_ADDR_HI,x
        sta     $6D
        inx
        lda     VIC_ROW_ADDR_LO,x
        sta     $6A
        lda     VIC_ROW_ADDR_HI,x
        sta     $6B
        ldy     #$27
L23A0:  lda     ($6A),y
        sta     ($6C),y
        dey
        bpl     L23A0
        bmi     L2385
L23A9:  ldx     #$27
        lda     #$20
L23AD:  sta     $07C0,x
        dex
        bpl     L23AD
L23B3:  lda     Z_TEMP1
        jsr     PUT_CHARACTER
        pla
        tay
        pla
        tax
        rts

L23BD:  cpx     #$17
        bcc     L23B3
        bcs     L237E
L23C3:  jsr     L20F6
        jsr     L2684
        ldy     #$00
        sty     $65
L23CD:  jsr     GET_KEY
        cmp     #$0D
        beq     L23FE
        cmp     #$14
        beq     L23F4
        sta     INPUT_BUFFER,y
        iny
L23DC:  jsr     PRINT_CHAR_AT_COORDINATE
        cpy     #$4D
        bcc     L23CD
L23E3:  jsr     GET_KEY
        cmp     #$0D
        beq     L23FE
        cmp     #$14
        beq     L23F4
        jsr     ERROR_SOUND
        jmp     L23E3

L23F4:  dey
        bpl     L23DC
        jsr     ERROR_SOUND
        ldy     #$00
        beq     L23CD
L23FE:  sta     INPUT_BUFFER,y
        iny
        sty     $45
        sty     $6F
        ldx     #$00
        stx     SPENA
        jsr     PRINT_CHAR_AT_COORDINATE
L240E:  lda     $01FF,y
        and     #$7F
        cmp     #$41
        bcc     L241D
        cmp     #$5B
        bcs     L241D
        adc     #$20
L241D:  sta     (Z_OPERAND1),y
        dey
        bne     L240E
        jsr     LOG_TO_PRINTER
        lda     $45
        rts

PRINT_MESSAGE:  stx     L2430+1
        sta     L2430+2
        ldx     #$00
L2430:  lda	!$0000,x
        jsr     PRINT_CHAR_AT_COORDINATE
        inx
        dey
        bne     L2430
        rts

Z_SPLIT_WINDOW:  ldx     Z_OPERAND1
        beq     L24E5
        lda     $69
        bne     L24E4
        cpx     #$14
        bcs     L24E4
        inx
        stx     $68
        stx     $69
L24C3:  lda     VIC_ROW_ADDR_LO,x
        sta     $6A
        lda     VIC_ROW_ADDR_HI,x
        sta     $6B
        ldy     #$27
        lda     #$20
L24D1:  sta     ($6A),y
        dey
        bpl     L24D1
        dex
        bne     L24C3
        stx     $65
L24DB:  lda     #$17
        sec
        sbc     $68
        sta     $66
        dec     $66
L24E4:  rts

L24E5:  jsr     L250C
L24E8:  ldx     #$01
        stx     $68
        dex
        stx     $69
        stx     $65
        lda     #$15
        sta     $66
        rts

Z_SET_WINDOW:  lda     $69
        beq     L24E4
        lda     Z_OPERAND1
        ora     Z_OPERAND1+1
        beq     L250C
        cmp     #$01
        bne     L24E4
L2504:  ldx     #$15
        stx     $66
        ldx     #$01
        bne     L2511
L250C:  jsr     L24DB
        ldx     #$17
L2511:  ldy     #$00
        sty     $65
        clc
        jsr     PLOT
        jmp     L2582

ERROR_SOUND:  lda     #$00
        sta     FRELO1
        lda     #$05
        sta     FREHI1
        lda     #$F0
        sta     SUREL1
        lda     #$8F
        sta     SIGVOL
        lda     #$41
        sta     VCREG1
        lda     #$FC
        sta     $A2
L2539:  lda     $A2
        bne     L2539
        sta     VCREG1
        lda     #$80
        sta     SIGVOL
        rts

CLEAR_SCREEN
	lda     #>VICSCN
        sta     Z_VECTOR2+1
        lda     #>COLRAM
        sta     Z_VECTOR3+1
        ldy     #<VICSCN
        sty     Z_VECTOR2
        sty     Z_VECTOR3
	sty     SPENA
        ldx     #$04
L2559:  lda     #$20		; PETSCII space
        sta     (Z_VECTOR2),y	; fill $0400-07ff
        lda     #$01		; White character
        sta     (Z_VECTOR3),y	; fill $d800-dbff
        iny
        bne     L2559
        inc     Z_VECTOR2+1
        inc     Z_VECTOR3+1
        dex
        bne     L2559
        lda     #$0D
        sta     $07F8
        jsr     L2504
        jsr     L24E8
        sei
        lda     #<L258F
        sta     NMINV
        lda     #>L258F
        sta     NMINV+1
        cli
L2582:  ldx     #$18
L2584:  lda     VIC_ROW_ADDR_HI,x
        ora     #$80
        sta     $D9,x
        dex
        bpl     L2584
        rts

L258F:  rti

DO_CARRIAGE_RETURN
.(
	jsr     Z_NEW_LINE
        rts
.)

PRINT_DEFAULT:  clc
        adc     #$31
        sta     DEFAULT_TEXT+12
	ldx     #<DEFAULT_TEXT
        lda     #>DEFAULT_TEXT
        ldy     #$10
        jsr     PRINT_MESSAGE

L2684:  ldx     #$00
        stx     $C6
        inx
        stx     SPENA
        rts

SET_POSITION
.(
	ldx     #<POSITION_TEXT
        lda     #>POSITION_TEXT
        ldy     #$0D
        jsr     PRINT_MESSAGE	; which position?
        lda     $76
        jsr     PRINT_DEFAULT
L2707:  jsr     GET_KEY
        cmp     #$0D
        beq     L271B
        sec
        sbc     #$31
        cmp     #SAVE_SLOTS	; bumped to 9 for uIEC version
        bcc     L271D
        jsr     ERROR_SOUND
        jmp     L2707

L271B:  lda     $76
L271D:  sta     $78
        clc
        adc     #$31
        sta     POS_CONFIRM_TEXT+11
        sta     SAVE_POS_NUMBER
        sta     REST_POS_NUMBER
	sta	SAVE_FN
	sta	REST_FN
        jsr     PUT_CHARACTER
        ldx     #<POS_CONFIRM_TEXT
        lda     #>POS_CONFIRM_TEXT
        ldy     #35	; #$2C
        jsr     PRINT_MESSAGE
        jsr     L2684
L276F:  jsr     GET_KEY
        cmp     #$59
        beq     PRINT_NO
        cmp     #$79
        beq     PRINT_NO
        cmp     #$4E
        beq     PRINT_YES
        cmp     #$6E
        beq     PRINT_YES
        jsr     ERROR_SOUND
        jmp     L276F

PRINT_YES
	ldx     #<NO_TEXT
        lda     #>NO_TEXT
        ldy     #$03
        jsr     PRINT_MESSAGE
        jmp     SET_POSITION

PRINT_NO
	lda     #$00
        sta     SPENA
        ldx     #<YES_TEXT
        lda     #>YES_TEXT
        ldy     #$04
        jsr     PRINT_MESSAGE
        lda     $79
        sta     $77
        lda     $78
        sta     $76
        asl
        clc
	rts
.)

PRESS_RETURN
.(
	ldx     #<PRESS_RETURN_TEXT
        lda     #>PRESS_RETURN_TEXT
        ldy     #$1E
        jsr     PRINT_MESSAGE
        jsr     L2684
L27E4:  jsr     GET_KEY
        cmp     #$0D
        beq     L27F1
        jsr     ERROR_SOUND
        jmp     L27E4
L27F1:  lda     #$00
        sta     SPENA
        rts
.)

PRINT_MESSAGE_INV_STATUS_LINE
.(
	jsr     PRINT_MESSAGE
        ldx     #39
L1	lda     VICSCN,x
        ora     #$80
        sta     VICSCN,x
        lda     #$00
        sta     COLRAM,x
        dex
        bpl     L1
        rts
.)

; 0OP:181 5 4 save -> (result)
; Attempts to save the game (all questions about filenames are asked by
; interpreters) and branches if successful.

Z_SAVE
.(
	jsr	DO_CARRIAGE_RETURN
	ldx	#<SAVE_POSITION_TEXT
	lda	#>SAVE_POSITION_TEXT
        ldy     #$0E
        jsr     PRINT_MESSAGE_INV_STATUS_LINE
        jsr     SET_POSITION
        bcc     L28A9
L28A3
        jmp     L1146
L28A9:  ldx     #<SAVING_POSITION_TEXT
        lda     #>SAVING_POSITION_TEXT
        ldy     #$17
        jsr     PRINT_MESSAGE
        lda     Z_HDR_MODE_BITS+1
        sta     Z_LOCAL_VARIABLES + $20
        lda     Z_HDR_MODE_BITS+2
        sta     Z_LOCAL_VARIABLES + $21
        lda     Z_STACK_POINTER
        sta     Z_LOCAL_VARIABLES + $22
        lda     $18
        sta     Z_LOCAL_VARIABLES + $23
        ldx     #$02
L28CA:  lda     Z_PC,x
        sta     Z_LOCAL_VARIABLES + $24,x
        dex
        bpl     L28CA
        lda     #>Z_LOCAL_VARIABLES
        sta     PAGE_VECTOR+1

	jsr	UIEC_ONLY
	bcc	L28CAa
	clc
	jsr	CLOSE_STORY_FILE
	jsr	COMMAND_CLOSE

L28CAa
	jsr	SAVEFILE_OPEN_WRITE
        jsr     SEND_BUFFER_TO_DISK
        bcs     L28A3
        lda     #>Z_STACK_LO
        sta     PAGE_VECTOR+1
        jsr     SEND_BUFFER_TO_DISK
        bcs	L28A3
        jsr     SEND_BUFFER_TO_DISK
        bcs     L28A3
        lda     Z_BASE_PAGE
        sta     PAGE_VECTOR+1
        ldx     Z_HDR_DYN_SIZE
        inx
        stx     Z_VECTOR2
L28F3:  jsr     SEND_BUFFER_TO_DISK
        bcs     L28A3
        dec     Z_VECTOR2
        bne     L28F3
	jsr	CLOSE_SAVE_FILE

	jsr	UIEC_ONLY
        bcc     L28F3a
	clc
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN
L28F3a
        jmp     L1152
.)

; 0OP:182 5 4 restore -> (result)
; See save. In Version 3, the branch is never actually made, since either the
; game has successfully picked up again from where it was saved, or it failed
; to load the save game file.
; As with restart, the transcription and fixed font bits survive. The
; interpreter gives the game a way of knowing that a restore has just happened
; (see save).
; If the restore fails, 0 is returned, but once again this necessarily happens
; since otherwise control is already elsewhere.

Z_RESTORE
.(
	jsr	DO_CARRIAGE_RETURN
	ldx	#<RESTORE_POSITION_TEXT
        lda     #>RESTORE_POSITION_TEXT
        ldy     #$11
        jsr     PRINT_MESSAGE_INV_STATUS_LINE
        jsr     SET_POSITION
        bcs     L2974
        ldx     #<RESTORING_POSITION_TEXT
        lda     #>RESTORING_POSITION_TEXT
        ldy     #$1A
        jsr     PRINT_MESSAGE
        ldx     #$1F
L2949:  lda     Z_LOCAL_VARIABLES,x
        sta     STACK,x
        dex
        bpl     L2949
        lda     #>Z_LOCAL_VARIABLES
        sta     PAGE_VECTOR+1

	jsr	UIEC_ONLY
        bcc     L2949a
	clc
        jsr     CLOSE_STORY_FILE
        jsr     COMMAND_CLOSE

L2949a
	jsr	SAVEFILE_OPEN_READ
	bcs	L2969			; error if file not found
	ldx	#2
        jsr     READ_BUFFER_FROM_DISK
        lda     Z_LOCAL_VARIABLES + $20
        cmp     Z_HDR_MODE_BITS+1
        bne     L2969
        lda     Z_LOCAL_VARIABLES + $21
        cmp     Z_HDR_MODE_BITS+2
        beq     L297A
L2969:  ldx     #$1F
L296B:  lda     STACK,x
        sta     Z_LOCAL_VARIABLES,x
        dex
        bpl     L296B
	jsr	CLOSE_SAVE_FILE
	jsr	UIEC_ONLY
        bcc     L2974
	clc
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN
L2974
        jmp     L1146

L297A:  lda	Z_HDR_FLAGS2
        sta     Z_VECTOR2
        lda     Z_HDR_FLAGS2+1
        sta     Z_VECTOR2+1
        lda     #>Z_STACK_LO
        sta     PAGE_VECTOR+1
	ldx	#2
        jsr     READ_BUFFER_FROM_DISK
	ldx	#2
        jsr     READ_BUFFER_FROM_DISK
        lda     Z_BASE_PAGE
        sta     PAGE_VECTOR+1
	ldx	#2
        jsr     READ_BUFFER_FROM_DISK
        lda     Z_VECTOR2
        sta     Z_HDR_FLAGS2
        lda     Z_VECTOR2+1
        sta     Z_HDR_FLAGS2+1
        lda     Z_HDR_DYN_SIZE
        sta     Z_VECTOR2
L29A4
	ldx	#2
	jsr     READ_BUFFER_FROM_DISK
        dec     Z_VECTOR2
        bne     L29A4
	jsr	CLOSE_SAVE_FILE
L29AB:  lda     Z_LOCAL_VARIABLES + $22
        sta     Z_STACK_POINTER
        lda     Z_LOCAL_VARIABLES + $23
        sta     $18
        ldx     #$02
L29B7:  lda     Z_LOCAL_VARIABLES + $24,x
        sta     Z_PC,x
        dex
        bpl     L29B7
        lda     #$00
        sta     $1C
        jmp     L1152
.)

;
; This returns accumulator value as a split single-character value, high
; byte in X and low byte in acc.  Does not actually ASCIIfy it.
;

NUMBER_TO_DIGIT
.(
	ldx     #$00
L1	cmp     #$0A		; is accumulator less than 10?
        bcc     L2		; if so, just return
        sbc     #$0A		; if not, subtract 10 ...
        inx			; ... and increment X ...
        bne     L1		; ... and if we're not zero then continue.
L2	rts
.)

; string area here

POSITION_TEXT:
	.aasc $0d, "Position 1-", $30+SAVE_SLOTS

POS_CONFIRM_TEXT:
	.aasc $0d, $0d, "Position *."
	.aasc $0d, "Are you sure? (Y/N) >" ; 22

PUNCTUATION
	.asc	"!?,.", $0d, " "

VERSION_TEXT
	.aasc	"C64 Version I (", CUR_DATE, "-01)", $0d
	.aasc	"uIEC/EasyFlash code by Chris Kobayashi", $0d
	.aasc	"For Saya, Ao, Karie, and the KobaCats", $0d
	.aasc	$0d
VERSION_LENGTH = 30 + 39 + 38 + 1
MORE_TEXT
	.aasc $5b, "MORE", $5d

DEFAULT_TEXT
	.aasc	" (Default = *) >
PRESS_RETURN_TEXT
	.aasc	$0d, "Press [RETURN] to continue."
	.aasc	$0d, ">"

;
; local status stuff
;

#include "common.s"
#include "sd2iec.s"
#include "ramexp.s"

; pad up to next page
.dsb    $100 - (* & $00FF), $FF

Z_HEADER = *
