; $Id$

;
; Commodore 64 Infocom v4 interpreter, version L
; Build 2014112201 Christopher Kobayashi <lemon64@disavowed.jp>
;
; This was disassembled from the officially released version L interpreter
; (as extracted from the official "Nord and Bert" disk image, and modified
; thusly:
;
; * The 1541/1571 fastload routines were removed.
; * The story file is loaded from "STORY.DAT" instead of raw blocks.
; * To accomodate the above, an REU is now required.
; * The number of save slots has been increased from five to nine.
;   (however, Trinity and AMFV override this in their resident code, so they
;   can only save in slots 1-4)
; * Save games are variable-block seq files named "SAVEn", where n is slot
;   number.
; * The game can be run from any device number, not just device 8.
;
; These changes were made so that games could be easily played using an uIEC,
; but would also be useful with any larger-capacity drive (1581, FD-2000, etc).
;
; Version L can be compiled by undefining NON_STOCK.  The resulting binary will
; be byte-for-byte identical with the shipped interpreter.
; This is useful for regression testing.
;
; Compile with: xa65 -M -o i-v4.1000 i-v4.s
;
; Crunch with: exomizer sfx 0x0e00 i-v4.1000 -o infocom4
;
; To do:
;
; * Use George Hug's 2400bps RS232 routines to replace printer code
; * C128 80 column support

#include "c64.inc"
#undef CKNOIO

MAP_RAM =		%11111101
MAP_ROM =		%00000010

REU_PRESENT =           $02     ; 0 (0000) = no REU (death mode)
                                ; 1 (0001) = CBM REU
                                ; 2 (0010) = GeoRAM
                                ; 3 (1xxx) = EasyFlash
                                ; 4 (1xxx) = uIEC present

Z_PC			= $0e
Z_CURRENT_PHYS_PC	= $11
Z_CURRENT_PHYS_PC_ALT	= $17

Z_BASE_PAGE		= $1a
Z_HIGH_ADDR		= $1b
Z_GLOBALS_ADDR		= $1c
Z_ABBREV_ADDR		= $20
Z_OBJECTS_ADDR		= $22
Z_TEMP1			= $51
Z_STATIC_ADDR		= $75
Z_MAX_SAVES		= $76

STORY_INDEX		= $37
PAGE_VECTOR		= $39

Z_CURRENT_WINDOW =	$45
Z_CURRENT_WINDOW_HEIGHT = $50

;EF_START_BANK		= $59	 old SECTOR
;EF_BANK			= $5a	 old TRACK
;SCRATCH			= $5f	old L5F_CURRENT_DRIVE_UNIT
; EF_NONRES_PAGE_BASE	= $60	old L60_CURRENT_DISK_SIDE
Z_STACK_POINTER		= $64 ; two-byte

Z_SOMETHING_NOT_PC	= $67

Z_VECTOR0	= $7f
Z_VECTOR1	= $04
Z_VECTOR2	= $06
Z_VECTOR3	= $08
Z_VECTOR4	= $0c
Z_VECTOR5	= $15
Z_OPERAND1	= $7b
Z_OPERAND2	= $7d

INPUT_BUFFER		= $0200
Z_STACK_LO		= $0900
Z_STACK_HI		= $0b00
Z_LOCAL_VARIABLES	= $0f00

MAX_RAM_PAGE		= $EA		; start at 0x3a00, thus 0xb000
SCREEN_WIDTH		= 40

; Story file header

;Z_HEADER =              $3A00
Z_HDR_CODE_VERSION =    Z_HEADER + 0
Z_HDR_MODE_BITS =       Z_HEADER + 1
Z_HDR_RESIDENT_SIZE =   Z_HEADER + 4
Z_HDR_START_PC =        Z_HEADER + 6
Z_HDR_DICTIONARY =      Z_HEADER + 8
Z_HDR_OBJECTS =         Z_HEADER + $0a
Z_HDR_GLOBALS =         Z_HEADER + $0c
Z_HDR_DYN_SIZE =        Z_HEADER + $0e
Z_HDR_FLAGS2 =          Z_HEADER + $10
Z_HDR_ABBREV =          Z_HEADER + $18
Z_HDR_FILE_LENGTH =     Z_HEADER + $1a
Z_HDR_CHKSUM =          Z_HEADER + $1c
Z_HDR_INTERP_NUMBER =   Z_HEADER + $1e
Z_HDR_INTERP_VERSION =  Z_HEADER + $1f
Z_HDR_SCREEN_ROWS =     Z_HEADER + $20
Z_HDR_SCREEN_COLS =     Z_HEADER + $21

SECTOR_BUFFER = $0800

.text
.word	$1000

	* = $1000

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
        ldx     #<STORY_LOADING_TEXT
        lda     #>STORY_LOADING_TEXT
        ldy     #$19
;        ldx     #<PATIENT
;        lda     #>PATIENT
;        ldy     #$28
        jsr     PRINT_MESSAGE

        lda     REU_PRESENT
        and     #%00001111      ; we have to have at least a uIEC ...
        bne     L2
        lda     #$89
        jmp     FATAL_ERROR

L2	lda     #$00	; initialize state machine, i guess, in zero page
        ldx     #$03
L3	sta     $00,x
        inx
        cpx     #$8F
        bcc     L3
        inc     Z_STACK_POINTER
        inc     $66
        inc     $4E
        inc     $68
        inc     Z_HIGH_ADDR

        lda     #>Z_HEADER		; game data from $3a00
        sta     Z_BASE_PAGE
        sta     PAGE_VECTOR+1

	clc				; sick and wrong hardcoding
	adc	#$C0
	sta	MAX_RES_PAGE_CALC

        lda     REU_PRESENT
        and     #%00000100
        beq     L1Ed1a
                                ; set EasyFlash bank to 1, prepping for load
        lda     #$80
        sta     EF_VEC1+2
        lda     EF_START_BANK
        sta     EF_BANK
	jmp     LEd1b
L1Ed1a
	jsr	UIEC_ONLY
	bcc	L1Ed1b
	clc
	jsr	COMMAND_OPEN
L1Ed1b
	jsr	STORY_OPEN
LEd1b
	ldx	#5
        jsr     READ_BUFFER
        bcc     L4
        jmp     FATAL_ERROR_0E

L4	lda     Z_HDR_CODE_VERSION	; v4?
        cmp     #4
        beq     L6
        lda     #$10
        jmp     FATAL_ERROR

L5	ldx     #$05
        ldy     #$00
        jsr     PLOT
        lda     #$00
        jmp     FATAL_ERROR

L6
	;
	; On the Commodore 64 v4 interpreter, a wonky paging scheme is used
	; to handle resident sizes larger than physical memory.  This requires
	; that the resident size be set to $AEFF.
	;
	; "Bureaucracy", weirdly, doesn't need this fixup.

	ldx	#$ae
	stx	Z_HDR_RESIDENT_SIZE
	ldx	#$ff
	stx	Z_HDR_RESIDENT_SIZE+1
L6a:
	ldx     Z_HDR_RESIDENT_SIZE	; get resident pages ...
        inx				; ... pad up to next page
        stx     Z_HIGH_ADDR
        txa
        clc
        adc     Z_BASE_PAGE
        sta     Z_VECTOR3
        jsr     GET_MAX_PAGE		; we max out at size 0xb000
        cmp     Z_VECTOR3
        beq     L7
        bcc     L5			; resident size too big, bomb out ...
					; ... but this is a bug, because files
					; that blow past 0xffff (Trinity,
					; AMFV) will lose the carry bit and
					; pass this test :(

L7	lda     Z_HDR_MODE_BITS
        ora     #$3B			; mask unused bits in header
        sta     Z_HDR_MODE_BITS
        lda     #8			; set interpreter number (C64)
        sta     Z_HDR_INTERP_NUMBER
        lda	#"L"
	sta	Z_HDR_INTERP_VERSION	; set interpreter version
        lda     #24
        sta     Z_HDR_SCREEN_ROWS	; screen height

					; which game are we?
					; Nord: 870722 4986
					; AMFV: 850814 5031
					; Trinity: 860926 16ab
					; Bureaucracy: 870602 fc65
	ldx	Z_HDR_CHKSUM
	ldy	Z_HDR_CHKSUM+1
	cpx	#$49
	bne	L10a
	cpy	#$86
	bne	L10a
	lda	#0
	sta	WHICH_GAME
	jmp	L7A

L10a	cpx	#$50
	bne	L10b
	cpy	#$31
	bne	L10b
	lda	#1
	sta	WHICH_GAME
	jmp	L7A

L10b	cpx	#$16			; if running Trinity, lie about width
	bne	L10c
	cpy	#$ab
	bne	L10c
	lda	#2
	sta	WHICH_GAME
	lda	#64
	jmp	L7B

L10c	cpx	#$fc
	bne	L7A
	cpy	#$65
	bne	L7A
	lda	#3
	sta	WHICH_GAME

L7A     lda     #SCREEN_WIDTH
L7B     sta     Z_HDR_SCREEN_COLS	; screen width

	; set up addresses for globals

        lda     Z_HDR_GLOBALS
        clc
        adc     Z_BASE_PAGE
        sta     Z_GLOBALS_ADDR+1
        lda     Z_HDR_GLOBALS+1
        sta     Z_GLOBALS_ADDR

	; set up addresses for abbrevations

        lda     Z_HDR_ABBREV
        clc
        adc     Z_BASE_PAGE
        sta     Z_ABBREV_ADDR+1
        lda     Z_HDR_ABBREV+1
        sta     Z_ABBREV_ADDR

	; set up addresses for objects

        lda     Z_HDR_OBJECTS
        clc
        adc	Z_BASE_PAGE
        sta     Z_OBJECTS_ADDR+1
        lda     Z_HDR_OBJECTS+1
        sta     Z_OBJECTS_ADDR

	; set up addresses for dynamic sized stuff

        lda     Z_HDR_DYN_SIZE
        clc
        adc     #$06
        sta     Z_STATIC_ADDR

#ifdef	BAKA				; this sets up max number of saves
        ldx     #$00
        stx     Z_MAX_SAVES
L8	inc     Z_MAX_SAVES
        clc
        adc     Z_STATIC_ADDR
        bcc     L8
L9	inc     Z_MAX_SAVES
        clc
        adc     Z_STATIC_ADDR
        bcc     L9
L10	cmp     #$98
        bcs     L11
        inc     Z_MAX_SAVES
        clc
        adc     Z_STATIC_ADDR
        bcc     L10
L11	lda     Z_MAX_SAVES
        cmp     #$0A
        bcc     L12
#endif
        lda     #$09
        sta     Z_MAX_SAVES
L12	clc
        adc     #$30
        sta     SAVE_SLOT

        ldy     #$01
        ldx     #$0E
        clc
        jsr     PLOT
        ldx     #<PATIENT
        lda     #>PATIENT
        ldy     #$28
        jsr     PRINT_MESSAGE

	jsr     LOAD_RESIDENT
	lda	REU_PRESENT
	and	#%00000100
	bne	L13a
	jsr	UIEC_ONLY
	bcs	L13a
	jsr	CLOSE_STORY_FILE
L13a
	clc
        lda     Z_HDR_START_PC
        sta     Z_PC+1
        lda     Z_HDR_START_PC+1
        sta     Z_PC
        jsr     VIRT_TO_PHYS_ADDR_1	; first ...
        lda     INTERP_FLAGS
        cmp     #$01
        bne     L14
        sta     $69
        ora     Z_HDR_FLAGS2+1
        sta     Z_HDR_FLAGS2+1
L14	jsr     CLEAR_SCREEN
        ldx     #$17
        ldy     #$00
        clc
        jsr     PLOT
.)

; this appears to be the interpreter main loop


MAIN_LOOP
.(
	lda     #$00
        sta     $79
        jsr     FETCH_NEXT_ZBYTE
        sta     $03
        bmi     L11F5
        jmp     JUMP_TWO

L11F5:  cmp     #$B0
        bcs     L11FC
        jmp     JUMP_ONE

L11FC:  cmp     #$C0
        bcs     L1203
L1200:  jmp	JUMP_ZERO
L1203:  cmp     #$EC
        beq     L126A
        jsr     FETCH_NEXT_ZBYTE
        sta     $8B
        ldx     #$00
        stx     $8D
        beq     L1218
L1212:  lda     $8B
        asl
        asl
        sta     $8B
L1218:  and     #$C0
        bne     L1222
        jsr     L1370
        jmp     L1233

L1222:  cmp     #$40
        bne     L122C
        jsr     L136C
        jmp     L1233

L122C:  cmp     #$80
        bne     L1247
        jsr     L1384
L1233:  ldx     $8D
        lda     Z_VECTOR1
        sta     Z_OPERAND1,x
        lda     Z_VECTOR1+1
        sta     Z_OPERAND1+1,x
        inc     $79
        inx
        inx
        stx     $8D
        cpx     #$08
        bcc     L1212
.)

L1247:  lda     $03
        cmp     #$E0
        bcs     JUMP_VAR
        jmp     L1345

JUMP_VAR
	and     #$1F
	asl
        tay
        lda     JUMP_TABLE_VAR,y
        sta     L125F+1
        lda     JUMP_TABLE_VAR+1,y
        sta     L125F+2
L125F	jsr	$FFFF
        jmp     MAIN_LOOP

Z_ERROR_01:        lda     #$01
        jmp     FATAL_ERROR

L126A
	jsr     FETCH_NEXT_ZBYTE
        sta     $8B
        jsr     FETCH_NEXT_ZBYTE
        sta     $8C
        lda     $8B
        ldx     #$00
        stx     $8D
        beq     L1282
L127C:  lda     $8B
        asl
        asl
        sta     $8B
L1282:  and     #$C0
        bne     L128C
        jsr     L1370
        jmp     L129D
L128C:  cmp     #$40
        bne     L1296
        jsr     L136C
        jmp     L129D
L1296:  cmp     #$80
        bne     L1247
        jsr     L1384
L129D:  ldx     $8D
        lda     Z_VECTOR1
        sta     Z_OPERAND1,x
        lda     Z_VECTOR1+1
        sta     Z_OPERAND1+1,x
        inc     $79
        inx
        inx
        stx     $8D
        cpx     #$10
        beq     L1247
        cpx     #$08
        bne     L127C
        lda     $8C
        sta     $8B
        jmp     L1282

JUMP_ZERO
.(
	and     #$0F
	asl
        tay
        lda     JUMP_TABLE_ZERO,y
        sta     L1+1
        lda     JUMP_TABLE_ZERO+1,y
        sta     L1+2
L1	jsr	$FFFF
        jmp     MAIN_LOOP
.)

Z_ERROR_02
.(
        lda     #$02
        jmp     FATAL_ERROR
.)

JUMP_ONE
.(
	and     #$30
        bne     L1
        jsr     FETCH_NEXT_ZBYTE
        jmp     L2
L1	and     #$20
        bne     L3
L2	sta     Z_OPERAND1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_OPERAND1
        inc     $79
        jmp     L4
L3	jsr     L1384
        jsr     L1361
L4	lda     $03
        and     #$0F
	asl
        tay
        lda     JUMP_TABLE_ONE,y
        sta     L5+1
        lda     JUMP_TABLE_ONE+1,y
        sta     L5+2
L5	jsr	$FFFF
        jmp     MAIN_LOOP
.)

Z_ERROR_03			; not actually referenced anywhere
.(
        lda     #$03
        jmp     FATAL_ERROR
.)

JUMP_TWO
	and     #$40
        bne     L1322
        sta     Z_OPERAND1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_OPERAND1
        inc     $79
        jmp     L1328
L1322:  jsr     L1384
        jsr     L1361
L1328:  lda     $03
        and     #$20
        bne     L1338
        sta     Z_OPERAND2+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_OPERAND2
        jmp     L1343
L1338:  jsr     L1384
        lda     Z_VECTOR1
        sta     Z_OPERAND2
        lda     Z_VECTOR1+1
        sta     Z_OPERAND2+1
L1343:  inc     $79
L1345:  lda     $03
        and     #$1F
	asl
        tay
        lda     JUMP_TABLE_TWO,y
        sta     L1356+1
        lda     JUMP_TABLE_TWO+1,y
        sta     L1356+2
L1356:	jsr	$FFFF
        jmp     MAIN_LOOP

Z_ERROR_04:        lda     #$04
        jmp     FATAL_ERROR

L1361:  lda     Z_VECTOR1
        sta     Z_OPERAND1
        lda     Z_VECTOR1+1
        sta     Z_OPERAND1+1
        inc     $79
        rts

L136C:  lda     #$00
        beq     L1373
L1370:  jsr     FETCH_NEXT_ZBYTE
L1373:  sta     Z_VECTOR1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR1
        rts

L137B:  tax
        bne     L1389
        jsr     Z_POP
        jmp     PUSH_VECTOR1_TO_STACK

L1384
	jsr     FETCH_NEXT_ZBYTE
        beq     Z_POP
L1389:  cmp     #$10
        bcs     L139A
        asl
        tax
        lda     $0EFE,x
        sta     Z_VECTOR1
        lda     $0EFF,x
        sta     Z_VECTOR1+1
        rts
L139A:  jsr     CALCULATE_GLOBAL_WORD_ADDRESS
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR1+1
        iny
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR1
        rts

Z_POP
.(
	lda     Z_STACK_POINTER
        bne     L1
        sta     Z_STACK_POINTER+1
L1	dec     Z_STACK_POINTER
        bne     L2
        ora     Z_STACK_POINTER+1
        beq     Z_ERROR_05
L2	ldy     Z_STACK_POINTER
        lda     Z_STACK_POINTER+1
        beq     L3
        lda     Z_STACK_LO+$100,y
        sta     Z_VECTOR1
        tax
        lda     Z_STACK_HI+$100,y
        sta     Z_VECTOR1+1
        rts
L3	lda     Z_STACK_LO,y
        sta     Z_VECTOR1
        tax
        lda     Z_STACK_HI,y
        sta     Z_VECTOR1+1
        rts
.)

Z_ERROR_05:  lda     #$05
        jmp     FATAL_ERROR

PUSH_VECTOR1_TO_STACK
	ldx     Z_VECTOR1
        lda     Z_VECTOR1+1
PUSH_AX_TO_STACK
.(
	pha
        ldy     Z_STACK_POINTER
        lda     Z_STACK_POINTER+1
        beq     L1
        txa
        sta     Z_STACK_LO+$100,y
        pla
        sta     Z_STACK_HI+$100,y
        jmp     L2
L1	txa
        sta     Z_STACK_LO,y
        pla
        sta     Z_STACK_HI,y
L2	inc     Z_STACK_POINTER
        bne     L3
        lda     Z_STACK_POINTER
        ora     Z_STACK_POINTER+1
        bne     Z_ERROR_06
        inc     Z_STACK_POINTER+1
L3	rts
.)

Z_ERROR_06:  lda     #6		; stack overflow
        jmp     FATAL_ERROR

SET_GLOBAL_OR_LOCAL_WORD
	tax
        bne     L1428
        lda     Z_STACK_POINTER
        bne     L1411
        sta     Z_STACK_POINTER+1
L1411:  dec     Z_STACK_POINTER
        bne     PUSH_VECTOR1_TO_STACK
        ora     Z_STACK_POINTER+1
        beq     Z_ERROR_05
        bne     PUSH_VECTOR1_TO_STACK

; this CK 2319

RETURN_ZERO:  lda     #$00
        ldx     #$00
RETURN_VALUE:  sta     Z_VECTOR1
        stx     Z_VECTOR1+1
RETURN_NULL:  jsr     FETCH_NEXT_ZBYTE
        beq     PUSH_VECTOR1_TO_STACK
L1428:  cmp     #$10
        bcs     SET_GLOBAL_WORD
        asl
        tax
        lda     Z_VECTOR1
        sta     $0EFE,x
        lda     Z_VECTOR1+1
        sta     $0EFF,x
        rts

SET_GLOBAL_WORD
.(
	jsr     CALCULATE_GLOBAL_WORD_ADDRESS
        lda     Z_VECTOR1+1
        sta     (Z_VECTOR2),y
        iny
        lda     Z_VECTOR1
        sta     (Z_VECTOR2),y
        rts
.)

CALCULATE_GLOBAL_WORD_ADDRESS
	sec
        sbc     #$10
        ldy     #$00
        sty     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        clc
        adc     Z_GLOBALS_ADDR
        sta     Z_VECTOR2
        lda     Z_VECTOR2+1
        adc     Z_GLOBALS_ADDR+1
        sta     Z_VECTOR2+1
L145B:  rts

L145C:  jsr     FETCH_NEXT_ZBYTE
        bpl     L146D
L1461:  and     #$40
        bne     L145B
        jmp     FETCH_NEXT_ZBYTE

L1468:  jsr     FETCH_NEXT_ZBYTE
        bpl     L1461
L146D:  tax
        and     #$40
        beq     L147D
        txa
        and     #$3F
        sta     Z_VECTOR1
        lda     #$00
        sta     Z_VECTOR1+1
        beq     L1494
L147D:  txa
        and     #$3F
        tax
        and     #$20
        beq     L1489
        txa
        ora     #$E0
        tax
L1489:  stx     Z_VECTOR1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR1
        lda     Z_VECTOR1+1
        bne     L14A2
L1494:  lda     Z_VECTOR1
        bne     L149B
        jmp     Z_RFALSE

L149B:  cmp     #$01
        bne     L14A2
        jmp     Z_RTRUE

L14A2:  lda     Z_VECTOR1
        sec
        sbc     #$02
        tax
        lda     Z_VECTOR1+1
        sbc     #$00
        sta     Z_VECTOR2
        ldy     #$00
        sty     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        txa
        adc     Z_PC
        bcc     L14C3
L14BD:  inc     Z_VECTOR2
        bne     L14C3
        inc     Z_VECTOR2+1
L14C3:  sta     Z_PC
        lda     Z_VECTOR2
        ora     Z_VECTOR2+1
        beq     Z_NOP
        lda     Z_VECTOR2
        clc
        adc     Z_PC+1
        sta     Z_PC+1
        lda     Z_VECTOR2+1
        adc     $10
        and     #$03
        sta     $10
        jmp     VIRT_TO_PHYS_ADDR_1

Z_NOP:  rts

L14DE
.(
	lda     Z_OPERAND1
        sta     Z_VECTOR1
        lda     Z_OPERAND1+1
        sta     Z_VECTOR1+1
        rts
.)

REQUEST_STATUS_LINE_REDRAW
.(
	lda     Z_HDR_FLAGS2+1
        ora     #$04
        sta     Z_HDR_FLAGS2+1
        rts
.)

JUMP_TABLE_ZERO:
	.word	Z_RTRUE
	.word	Z_RFALSE
	.word	Z_PRINT_LITERAL
	.word	Z_PRINT_RET_LITERAL
	.word	Z_NOP
	.word	Z_SAVE		; v4 returns status
	.word	Z_RESTORE	; v4 returns status
	.word	Z_RESTART
	.word	Z_RET_POPPED
	.word	Z_POP
	.word	Z_QUIT
	.word	Z_NEW_LINE
	.word	Z_SHOW_STATUS	; v4 this is illegal!
	.word	Z_VERIFY
	.word	Z_ERROR_02	; v4 illegal
	.word	Z_ERROR_02	; v4 illegal

JUMP_TABLE_ONE:
	.word	Z_JZ
	.word	Z_GET_SIBLING
	.word	Z_GET_CHILD
	.word	Z_GET_PARENT
	.word	Z_GET_PROP_LEN
	.word	Z_INC
	.word	Z_DEC
	.word	Z_PRINT_ADDR
	.word	Z_CALL		; actually Z_CALL_LS
	.word	Z_REMOVE_OBJ
	.word	Z_PRINT_OBJ
	.word	Z_RET
	.word	Z_JUMP
	.word	Z_PRINT_PADDR
	.word	Z_LOAD
	.word	Z_NOT

JUMP_TABLE_TWO:
	.word	Z_ERROR_04
	.word	Z_JE
	.word	Z_JL
	.word	Z_JG
	.word	Z_DEC_CHK
	.word	Z_INC_CHK
	.word	Z_JIN
	.word	Z_TEST
	.word	Z_OR
	.word	Z_AND
	.word	Z_TEST_ATTR
	.word	Z_SET_ATTR
	.word	Z_CLEAR_ATTR
	.word	Z_STORE
	.word	Z_INSERT_OBJ
	.word	Z_LOADW
	.word	Z_LOADB
	.word	Z_GET_PROP
	.word	Z_GET_PROP_ADDR
	.word	Z_GET_NEXT_PROP
	.word	Z_ADD
	.word	Z_SUB
	.word	Z_MUL
	.word	Z_DIV
	.word	Z_MOD
	.word	Z_CALL		; only v4 addition
	.word	Z_ERROR_04
	.word	Z_ERROR_04
	.word	Z_ERROR_04
	.word	Z_ERROR_04
	.word	Z_ERROR_04
	.word	Z_ERROR_04

JUMP_TABLE_VAR:
	.word	Z_CALL			; 0
	.word	Z_STOREW		; 1
	.word	Z_STOREB		; 2
	.word	Z_PUT_PROP		; 3
	.word	Z_SREAD			; 4
	.word	Z_PRINT_CHAR		; 5
	.word	Z_PRINT_NUM		; 6
	.word	Z_RANDOM		; 7
	.word	Z_PUSH			; 8
	.word	Z_PULL			; 9
	.word	Z_SPLIT_WINDOW		; a
	.word	Z_SET_WINDOW		; b
	.word	Z_CALL			; c - from here v4+
	.word	Z_ERASE_WINDOW		; d
	.word	Z_ERASE_LINE		; e
	.word	Z_SET_CURSOR		; f
	.word	Z_NOP1			; 10
	.word	Z_SET_TEXT_STYLE	; 11
	.word	Z_BUFFER_MODE		; 12
	.word	Z_OUTPUT_STREAM		; 13
	.word	Z_NOP1			; 14
	.word	Z_SOUND_EFFECT		; 15
	.word	Z_READ_CHAR		; 16
	.word	Z_SCAN_TABLE		; 17
	.word	Z_ERROR_01		; these are v5+
	.word	Z_ERROR_01
	.word	Z_ERROR_01
	.word	Z_ERROR_01
	.word	Z_ERROR_01
	.word	Z_ERROR_01
	.word	Z_ERROR_01
	.word	Z_ERROR_01

; 0OP:176 0 rtrue
; Return true (i.e., 1) from the current routine.

Z_RTRUE:  ldx     #$01
L15B2:  lda     #$00
L15B4:  stx     Z_OPERAND1
        sta     Z_OPERAND1+1
        jmp     Z_RET

; 0OP:177 1 rfalse
; Return false (i.e., 0) from the current routine.

Z_RFALSE:  ldx     #$00
        beq     L15B2

; 0OP:178 2 print
; Print the quoted (literal) Z-encoded string.

Z_PRINT_LITERAL
.(
	ldx     #$05
L1	lda     Z_PC,x
        sta     $14,x
        dex
        bpl	L1
;	ldx	IGNORE_NEXT_PRINT	doesn't work yet
;	cpx	#00
;	beq 	L1A
;	dec	IGNORE_NEXT_PRINT
;	jmp	L1B
L1A	jsr	L247B
L1B     ldx	#$05
L2	lda     $14,x
        sta     Z_PC,x
        dex
        bpl     L2
        rts
.)

; 0OP:179 3 print_ret
; Print the quoted (literal) Z-encoded string, then print a new-line and
; then return true (i.e., 1).

Z_PRINT_RET_LITERAL
        jsr     Z_PRINT_LITERAL
        jsr     Z_NEW_LINE
        jmp     Z_RTRUE

; 0OP:184 8 ret_popped
; Pops top of stack and returns that.

Z_RET_POPPED
        jsr     Z_POP
        jmp     L15B4

VERSION_TEXT:
	.aasc   "C64 Version 8L (", CUR_DATE, "-01)", $0d
	.aasc   "uIEC fixes by Chris Kobayashi", $0d
	.aasc   "For Saya, Ao, Karie, and the KobaCats", $0d
	.aasc   $0d
VERSION_LENGTH = 30 + 29 + 38 + 1

; 0OP:189 D 3 verify ?(label)
; Verification counts a (two byte, unsigned) checksum of the file from
; $0040 onwards (by taking the sum of the values of each byte in the file,
; modulo $10000) and compares this against the value in the game header,
; branching if the two values agree.

Z_VERIFY
.(
	jsr	Z_NEW_LINE
        ldx	#<VERSION_TEXT
        lda	#>VERSION_TEXT
        ldy	#VERSION_LENGTH
        jsr	PRINT_MESSAGE
	jsr     Z_NEW_LINE
        ldx     #$03
        lda     #$00
L1	sta     $0A,x
        sta     $14,x
        dex
        bpl     L1
        lda     #$40
        sta     $14
        lda     Z_HDR_FILE_LENGTH
        sta     Z_VECTOR2+1
        lda	Z_HDR_FILE_LENGTH+1
        asl
        rol     Z_VECTOR2+1
        rol     $0A
        asl
        sta     Z_VECTOR2
        rol     Z_VECTOR2+1
        rol     $0A
        lda     #$00
        sta     STORY_INDEX
        sta     STORY_INDEX+1
	lda	REU_PRESENT
	and	#%00000100
	beq	L1a

        lda     EF_START_BANK
        sta     EF_BANK
        lda     #$80
        sta     EF_VEC1+2
	jmp	L1b
L1a
        jsr     UIEC_ONLY
        bcc     L1aa
        clc
        lda     #0
        tax
        tay
        jsr     UIEC_SEEK
        jmp     L1b
L1aa
	jsr	STORY_OPEN
L1b
        jmp     L3
L2	lda     $14
        bne     L4
L3 
	lda     #>SECTOR_BUFFER
        sta     PAGE_VECTOR+1
	ldx	#5
        jsr     READ_BUFFER
        bcc     L4
        jmp     FATAL_ERROR_0E

L4	ldy     $14
        lda     SECTOR_BUFFER,y
        inc     $14
        bne     L5
        inc     $15
        bne     L5
        inc     $16
L5	clc
        adc     Z_VECTOR4
        sta     Z_VECTOR4
        bcc     L6
        inc     Z_VECTOR4+1
L6	lda     $14
        cmp     Z_VECTOR2
        bne     L2
        lda     $15
        cmp     Z_VECTOR2+1
        bne     L2
        lda     $16
        cmp     $0A
        bne     L2
	lda	REU_PRESENT
	and	#%00000100
	bne	L6a
	jsr	CLOSE_STORY_FILE
        jsr     UIEC_ONLY
        bcc     L6a
        clc
        jsr     COMMAND_CLOSE
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN
L6a
        lda     Z_HDR_CHKSUM+1
        cmp     Z_VECTOR4
        bne     L7
        lda     Z_HDR_CHKSUM
        cmp     Z_VECTOR4+1
        bne     L7
        jmp     L1468
L7	jmp     L145C
.)

; 1OP:128 0 jz a ?(label)
; Jump if a = 0.

Z_JZ	lda     Z_OPERAND1
        ora     Z_OPERAND1+1
        beq     L168F
L1667:  jmp     L145C

; 1OP:129 1 get_sibling object -> (result) ?(label)
; Get next object in tree, branching if this exists, i.e. is not 0.

Z_GET_SIBLING
	lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        ldy     #$08
        bne     L167E

; 1OP:130 2 get_child object -> (result) ?(label)
; Get first object contained in given object, branching if this exists,
; i.e. is not nothing (i.e., is not 0).

Z_GET_CHILD
	lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        ldy     #$0A
L167E:  lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        jsr     RETURN_VALUE
        lda     Z_VECTOR1
        bne     L168F
        lda     Z_VECTOR1+1
        beq     L1667
L168F:  jmp     L1468

; 1OP:131 3 get_parent object -> (result)
; Get parent object (note that this has no "branch if exists" clause).

Z_GET_PARENT:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        ldy     #$06
        lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        jmp     RETURN_VALUE

; 1OP:132 4 get_prop_len property-address -> (result)
; Get length of property data (in bytes) for the given object's property.
; It is illegal to try to find the property length of a property which does
; not exist for the given object, and an interpreter should halt with an error
; message (if it can efficiently check this condition).

Z_GET_PROP_LEN
.(
	lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE		; reufix
        sta     Z_VECTOR2+1
        lda     Z_OPERAND1
        sec
        sbc     #$01
        sta     Z_VECTOR2
        bcs     L16B6
        dec     Z_VECTOR2+1
L16B6:  ldy     #$00
        lda     (Z_VECTOR2),y
        bmi     L16C8
        and     #$40
        beq     L16C4
        lda     #$02
        bne     L16CA
L16C4:  lda     #$01
        bne     L16CA
L16C8:  and     #$3F
L16CA:  ldx     #$00
        jmp     RETURN_VALUE
.)

; 1OP:133 5 inc (variable)
; Increment variable by 1. (This is signed, so -1 increments to 0.)

Z_INC:  lda     Z_OPERAND1
        jsr     L137B
        inc     Z_VECTOR1
        bne     L16DA
        inc     Z_VECTOR1+1
L16DA:  jmp     L16EF

; 1OP:134 6 dec (variable)
; Decrement variable by 1. This is signed, so 0 decrements to -1.

Z_DEC:  lda     Z_OPERAND1
        jsr     L137B
        lda     Z_VECTOR1
        sec
        sbc     #$01
        sta     Z_VECTOR1
        lda     Z_VECTOR1+1
        sbc     #$00
        sta     Z_VECTOR1+1
L16EF:  lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

; 1OP:135 7 print_addr byte-address-of-string
; Print (Z-encoded) string at given byte address, in dynamic or static memory.

Z_PRINT_ADDR:  lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jsr     L20FD
        jmp     L247B

; 1OP:137 9 remove_obj object
; Detach the object from its parent, so that it no longer has any parent.

Z_REMOVE_OBJ:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        lda     Z_VECTOR2
        sta     Z_VECTOR3
        lda     Z_VECTOR2+1
        sta     Z_VECTOR3+1
        ldy     #$07
        lda     (Z_VECTOR2),y
        sta     $0A
        dey
        lda     (Z_VECTOR2),y
        tax
        lda     $0A
        ora     (Z_VECTOR2),y
        beq     L1774
        lda     $0A
        jsr     CALC_PHYS_ADDR_3
        ldy     #$0A
        lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND1
        bne     L1747
        cpx     Z_OPERAND1+1
        bne     L1747
        ldy     #$08
        lda     (Z_VECTOR3),y
        iny
        iny
        sta     (Z_VECTOR2),y
        dey
        lda     (Z_VECTOR3),y
        iny
        iny
        sta     (Z_VECTOR2),y
        bne     L1765
L1747:  jsr     CALC_PHYS_ADDR_3
        ldy     #$08
        lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND1
        bne     L1747
        cpx     Z_OPERAND1+1
        bne     L1747
        ldy     #$08
        lda     (Z_VECTOR3),y
        sta     (Z_VECTOR2),y
        iny
        lda     (Z_VECTOR3),y
        sta     (Z_VECTOR2),y
L1765:  lda     #$00
        ldy     #$06
        sta     (Z_VECTOR3),y
        iny
        sta     (Z_VECTOR3),y
        iny
        sta     (Z_VECTOR3),y
        iny
        sta     (Z_VECTOR3),y
L1774:  rts

; 1OP:138 A print_obj object
; Print short name of object (the Z-encoded string in the object header,
; not a property). If the object number is invalid, the interpreter should
; halt with a suitable error message.

Z_PRINT_OBJ:	lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        ldy     #$0C
        lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR2
        stx     Z_VECTOR2+1
        inc     Z_VECTOR2
        bne     L178E
        inc     Z_VECTOR2+1
L178E:  jsr     L20FD
        jmp     L247B

; 1OP:139 B ret value
; Returns from the current routine with the value given.

Z_RET:  lda     $66
        sta     Z_STACK_POINTER
        lda     Z_SOMETHING_NOT_PC
        sta     Z_STACK_POINTER+1
        jsr     Z_POP
        stx     Z_VECTOR2+1
        txa
        beq     L17BD
        dex
        txa
        asl
        sta     Z_VECTOR2
L17A9:  jsr     Z_POP
        ldy     Z_VECTOR2
        sta     Z_LOCAL_VARIABLES+1,y
        txa
        sta     Z_LOCAL_VARIABLES,y
        dec     Z_VECTOR2
        dec     Z_VECTOR2
        dec     Z_VECTOR2+1
        bne     L17A9
L17BD:  jsr     Z_POP
        stx     Z_PC+1
        sta     $10
        jsr     Z_POP
        sta     Z_PC
        jsr     Z_POP
        stx     $66
        sta     Z_SOMETHING_NOT_PC
        jsr     VIRT_TO_PHYS_ADDR_1
        jsr     L14DE
L17D6	jmp	RETURN_NULL

; 1OP:140 C jump ?(label)
; Jump (unconditionally) to the given label. (This is not a branch instruction
; and the operand is a 2-byte signed offset to apply to the program counter.)

Z_JUMP   jsr     L14DE
        jmp     L14A2

; 1OP:141 D print_paddr packed-address-of-string
; Print the (Z-encoded) string at the given packed address in high memory

Z_PRINT_PADDR   lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jsr     L2462
        jmp     L247B

; 1OP:142 E load (variable) -> (result)
; The value of the variable referred to by the operand is stored in the result.

Z_LOAD   lda     Z_OPERAND1
        jsr     L137B
        jmp     RETURN_NULL

; 1OP:143 F 1/4 not value -> (result)
; Bitwise NOT (i.e., all 16 bits reversed).

Z_NOT   lda     Z_OPERAND1
        eor     #$FF
        tax
        lda     Z_OPERAND1+1
        eor     #$FF
RETURN_VECTOR1:  stx     Z_VECTOR1
        sta     Z_VECTOR1+1
        jmp     RETURN_NULL

; 2OP:2 2 jl a b ?(label)
; Jump if a < b (using a signed 16-bit comparison).

Z_JL   jsr     L14DE
        jmp     L180E

; 2OP:4 4 dec_chk (variable) value ?(label)
; Decrement variable, and branch if it is now less than the given value.

Z_DEC_CHK   jsr     Z_DEC
L180E:  lda     Z_OPERAND2
        sta     Z_VECTOR2
        lda     Z_OPERAND2+1
        sta     Z_VECTOR2+1
        jmp     L1837

; 2OP:3 3 jg a b ?(label)
; Jump if a > b (using a signed 16-bit comparison).

Z_JG
	lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jmp     L182F

; 2OP:5 5 inc_chk (variable) value ?(label)
; Increment variable, and branch if now greater than value.

Z_INC_CHK   jsr     Z_INC
        lda     Z_VECTOR1
        sta     Z_VECTOR2
        lda     Z_VECTOR1+1
        sta     Z_VECTOR2+1
L182F:  lda     Z_OPERAND2
        sta     Z_VECTOR1
        lda     Z_OPERAND2+1
        sta     Z_VECTOR1+1
L1837:  lda     Z_VECTOR2+1
        eor     Z_VECTOR1+1
        bpl     L1846
        lda     Z_VECTOR2+1
        cmp     Z_VECTOR1+1
        bcc     L187E
        jmp     L145C
L1846:  lda     Z_VECTOR1+1
        cmp     Z_VECTOR2+1
        bne     L1850
        lda     Z_VECTOR1
        cmp     Z_VECTOR2
L1850:  bcc     L187E
        jmp     L145C

; 2OP:6 6 jin obj1 obj2 ?(label)
; Jump if object a is a direct child of b, i.e., if parent of a is b.

Z_JIN   lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        ldy     #$06
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND2+1
        bne     L186B
        iny
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND2
        beq     L187E
L186B:  jmp     L145C

; 2OP:7 7 test bitmap flags ?(label)
; Jump if all of the flags in bitmap are set (i.e. if bitmap & flags == flags).

Z_TEST   lda     Z_OPERAND2
        and     Z_OPERAND1
        cmp     Z_OPERAND2
        bne     L186B
        lda     Z_OPERAND2+1
        and     Z_OPERAND1+1
        cmp     Z_OPERAND2+1
        bne     L186B
L187E:  jmp     L1468

; 2OP:8 8 or a b -> (result)
; Bitwise OR.

Z_OR    lda     Z_OPERAND1
        ora     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        ora     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

; 2OP:9 9 and a b -> (result)
; Bitwise AND.

Z_AND   lda     Z_OPERAND1
        and     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        and     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

; 2OP:10 A test_attr object attribute ?(label)
; Jump if object has attribute.

Z_TEST_ATTR   jsr     L2756
        lda     $0B
        and     Z_VECTOR3+1
        sta     $0B
        lda     $0A
        and     Z_VECTOR3
        ora     $0B
        bne     L187E
        jmp     L145C

; 2OP:11 B set_attr object attribute
; Make object have the attribute numbered attribute.

Z_SET_ATTR   jsr     L2756
        ldy     #$00
        lda     $0B
        ora     Z_VECTOR3+1
        sta     (Z_VECTOR2),y
        iny
        lda     $0A
        ora     Z_VECTOR3
        sta     (Z_VECTOR2),y
        rts

; 2OP:12 C clear_attr object attribute
; Make object not have the attribute numbered attribute.

Z_CLEAR_ATTR   jsr     L2756
        ldy     #$00
        lda     Z_VECTOR3+1
        eor     #$FF
        and     $0B
        sta     (Z_VECTOR2),y
        iny
        lda     Z_VECTOR3
        eor     #$FF
        and     $0A
        sta     (Z_VECTOR2),y
        rts

; 2OP:13 D store (variable) value
; Set the VARiable referenced by the operand to value.

Z_STORE   lda     Z_OPERAND2
        sta     Z_VECTOR1
        lda     Z_OPERAND2+1
        sta     Z_VECTOR1+1
        lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

; 2OP:14 E insert_obj object destination
; Moves object O to become the first child of the destination object D.

Z_INSERT_OBJ   jsr     Z_REMOVE_OBJ
        lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        lda     Z_VECTOR2
        sta     Z_VECTOR3
        lda     Z_VECTOR2+1
        sta     Z_VECTOR3+1
        lda     Z_OPERAND2+1
        ldy     #$06
        sta     (Z_VECTOR2),y
        tax
        lda     Z_OPERAND2
        iny
        sta     (Z_VECTOR2),y
        jsr     CALC_PHYS_ADDR_3
L1905:  ldy     #$0A
        lda     (Z_VECTOR2),y
        sta     $0B
        lda     Z_OPERAND1+1
        sta     (Z_VECTOR2),y
        iny
        lda     (Z_VECTOR2),y
        tax
        lda     Z_OPERAND1
        sta     (Z_VECTOR2),y
        txa
        ora	$0B
        beq     L1926
        txa
        ldy     #$09
        sta     (Z_VECTOR3),y
        dey
        lda     $0B
        sta     (Z_VECTOR3),y
L1926:  rts

; 2OP:15 F loadw array word-index -> (result)
; Stores array-->word-index (i.e., the word at address array+2*word-index,
; which must lie in static or dynamic memory).

Z_LOADW
	jsr     L193E
        jsr     FETCH_BYTE_FROM_VECTOR
L192D:  sta     Z_VECTOR1+1
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     Z_VECTOR1
        jmp     RETURN_NULL

; 2OP:16 10 loadb array byte-index -> (result)
; Stores array->byte-index (i.e., the byte at address array+byte-index,
; which must lie in static or dynamic memory).

Z_LOADB   jsr     L1942
        lda     #$00
        beq     L192D
L193E:  asl     Z_OPERAND2
        rol     Z_OPERAND2+1
L1942:  lda     Z_OPERAND2
        clc
        adc     Z_OPERAND1
        sta     $14
        lda     Z_OPERAND2+1
        adc     Z_OPERAND1+1
        sta     $15
        lda     #$00
        adc     #$00
        sta     $16
        jmp     VIRT_TO_PHYS_ADDR

; 2OP:17 11 get_prop object property -> (result)
; Read property from object (resulting in the default value if it had no such
; declared property). If the property has length 1, the value is only that
; byte. If it has length 2, the first two bytes of the property are taken as
; a word value. It is illegal for the opcode to be used if the property has
; length greater than 2, and the result is unspecified.

Z_GET_PROP   jsr     L26F9
L195B:  jsr     L2717
        cmp     Z_OPERAND2
        beq     L197D
        bcc     L196A
        jsr     L2746
        jmp     L195B
L196A:  lda     Z_OPERAND2
        sec
        sbc     #$01
        asl
        tay
        lda     (Z_OBJECTS_ADDR),y
        sta     Z_VECTOR1+1
        iny
        lda     (Z_OBJECTS_ADDR),y
        sta     Z_VECTOR1
        jmp     RETURN_NULL
L197D:  jsr     L271C
        iny
        cmp     #$01
        beq     L198E
        cmp     #$02
        beq     L1994
        lda     #$07
        jmp     FATAL_ERROR
L198E:  lda     (Z_VECTOR2),y
        ldx     #$00
        beq     L199A
L1994:  lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
L199A:  sta     Z_VECTOR1
        stx     Z_VECTOR1+1
        jmp     RETURN_NULL

; 2OP:18 12 get_prop_addr object property -> (result)
; Get the byte address (in dynamic memory) of the property data for the given
; object's property.  This must return 0 if the object hasn't got the property.

Z_GET_PROP_ADDR
.(
	lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        ldy     #$0C
        lda     (Z_VECTOR2),y
        clc
        adc	Z_BASE_PAGE		; reufix
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
L2	lda     (Z_VECTOR2),y
        and     #$3F
        cmp     Z_OPERAND2
        beq     L11
        bcs     L3
        jmp     L1A2D
L3	lda     (Z_VECTOR2),y
        and     #$80
        beq     L4
        iny
        lda     (Z_VECTOR2),y
        and     #$3F
        jmp     L6
L4	lda     (Z_VECTOR2),y
        and     #$40
        beq     L5
        lda     #$02
        jmp     L6
L5	lda     #$01
L6	tax
L7	iny
        bne     L8
        inc     Z_VECTOR2+1
L8	dex
        bne     L7
        iny
        tya
        clc
        adc     Z_VECTOR2
        sta     Z_VECTOR2
        bcc     L10
        inc     Z_VECTOR2+1
L10	ldy     #$00
        jmp     L2
L11	lda     (Z_VECTOR2),y
        and     #$80
        beq     L12
        iny
        lda     (Z_VECTOR2),y
        and     #$3F
        jmp     L14
L12	lda     (Z_VECTOR2),y
        and     #$40
        beq     L13
        lda     #$02
        jmp     L14
L13	lda     #$01
L14	iny
        tya
        clc
        adc     Z_VECTOR2
        sta     Z_VECTOR1
        lda     Z_VECTOR2+1
        adc     #$00
        sec
        sbc    Z_BASE_PAGE		; reufix
        sta     Z_VECTOR1+1
        jmp     RETURN_NULL
.)
L1A2D:  jmp     RETURN_ZERO

; 2OP:19 13 get_next_prop object property -> (result)
; Gives the number of the next property provided by the quoted object. This
; may be zero, indicating the end of the property list; if called with zero,
; it gives the first property number present. It is illegal to try to find
; the next property of a property which does not exist, and an interpreter
; should halt with an error message (if it can efficiently check this
; condition).

Z_GET_NEXT_PROP   jsr     L26F9
        lda     Z_OPERAND2
        beq     L1A49
L1A37:  jsr     L2717
        cmp     Z_OPERAND2
        beq     L1A46
        bcc     L1A2D
        jsr     L2746
        jmp     L1A37

L1A46:  jsr     L2734
L1A49:  jsr     L2717
        ldx     #$00
        jmp     RETURN_VALUE

; 2OP:20 14 add a b -> (result)
; Signed 16-bit addition.

Z_ADD   lda     Z_OPERAND1
        clc
        adc     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        adc     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

; 2OP:21 15 sub a b -> (result)
; Signed 16-bit subtraction.

Z_SUB   lda     Z_OPERAND1
        sec
        sbc     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        sbc     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

; 2OP:22 16 mul a b -> (result)
; Signed 16-bit multiplication.

Z_MUL   jsr     L1B51
L1A6E:  ror     L2CAA
        ror     L2CA9
        ror     Z_OPERAND2+1
        ror     Z_OPERAND2
        bcc     L1A8B
        lda     Z_OPERAND1
        clc
        adc     L2CA9
        sta     L2CA9
        lda     Z_OPERAND1+1
        adc     L2CAA
        sta     L2CAA
L1A8B:  dex
        bpl     L1A6E
        ldx     Z_OPERAND2
        lda     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

; 2OP:23 17 div a b -> (result)
; Signed 16-bit division. Division by zero should halt the interpreter with a
; suitable error message.

Z_DIV   jsr     L1AAD
        ldx     L2CA5
        lda     L2CA6
        jmp     RETURN_VECTOR1

; 2OP:24 18 mod a b -> (result)
; Remainder after signed 16-bit division. Division by zero should halt the
; interpreter with a suitable error message.

Z_MOD   jsr     L1AAD
        ldx     L2CA7
        lda     L2CA8
        jmp     RETURN_VECTOR1

L1AAD:  lda     Z_OPERAND1+1
        sta     L2CAC
        eor     Z_OPERAND2+1
        sta     L2CAB
        lda     Z_OPERAND1
        sta     L2CA5
        lda     Z_OPERAND1+1
        sta     L2CA6
        bpl     L1AC6
        jsr     L1AF7
L1AC6:  lda     Z_OPERAND2
        sta     L2CA7
        lda     Z_OPERAND2+1
        sta     L2CA8
        bpl     L1AD5
        jsr     L1AE5
L1AD5:  jsr     L1B09
        lda     L2CAB
        bpl     L1AE0
        jsr     L1AF7
L1AE0:  lda     L2CAC
        bpl     L1AF6
L1AE5:  lda     #$00
        sec
        sbc     L2CA7
        sta     L2CA7
        lda     #$00
        sbc     L2CA8
        sta     L2CA8
L1AF6:  rts

L1AF7:  lda     #$00
        sec
        sbc     L2CA5
        sta     L2CA5
        lda     #$00
        sbc     L2CA6
        sta     L2CA6
        rts

L1B09:  lda     L2CA7
        ora     L2CA8
        beq     Z_ERROR_08
        jsr     L1B51
L1B14:  rol     L2CA5
        rol     L2CA6
        rol     L2CA9
        rol     L2CAA
        lda     L2CA9
        sec
        sbc     L2CA7
        tay
        lda     L2CAA
        sbc     L2CA8
        bcc     L1B36
        sty     L2CA9
        sta     L2CAA
L1B36:  dex
        bne     L1B14
        rol     L2CA5
        rol     L2CA6
        lda     L2CA9
        sta     L2CA7
        lda     L2CAA
        sta     L2CA8
        rts

Z_ERROR_08:  lda     #$08
        jmp     FATAL_ERROR

L1B51:  ldx     #$10
        lda     #$00
        sta     L2CA9
        sta     L2CAA
        clc
        rts

; 2OP:1 1 je a b ?(label)
; Jump if a is equal to any of the subsequent operands. (Thus @je a never
; jumps and @je a b jumps if a = b.)

Z_JE:	dec     $79
        bne     L1B66
        lda     #$09
        jmp     FATAL_ERROR
L1B66:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        cmp     Z_OPERAND2
        bne     L1B72
        cpx     Z_OPERAND2+1
        beq     L1B8A
L1B72:  dec     $79
        beq     L1B8D
        cmp     Z_VECTOR0
        bne     L1B7E
        cpx     Z_VECTOR0+1
        beq     L1B8A
L1B7E:  dec     $79
        beq     L1B8D
        cmp     $81
        bne     L1B8D
        cpx     $82
        bne     L1B8D
L1B8A:  jmp     L1468
L1B8D:  jmp     L145C

; VAR:224 0 1 call routine ...up to 3 args... -> (result)
; The only call instruction in Version 3, Inform reads this as call_vs in
; higher versions: it calls the routine with 0, 1, 2 or 3 arguments as
; supplied and stores the resulting return value. (When the address 0 is
; called as a routine, nothing happens and the return value is false.)

Z_CALL:	lda     Z_OPERAND1
        ora     Z_OPERAND1+1
        bne     L1B9B
        ldx     #$00
        jmp     RETURN_VALUE
L1B9B:  ldx     $66
        lda     Z_SOMETHING_NOT_PC
        jsr     PUSH_AX_TO_STACK
        lda     Z_PC
        jsr     PUSH_AX_TO_STACK
        ldx     Z_PC+1
        lda     $10
        jsr     PUSH_AX_TO_STACK
        lda     #$00
        asl     Z_OPERAND1
        rol     Z_OPERAND1+1
        rol
        sta     $10
        asl     Z_OPERAND1
        rol     Z_OPERAND1+1
        rol     $10
        lda     Z_OPERAND1+1
        sta     Z_PC+1
        lda     Z_OPERAND1
        sta     Z_PC
        jsr     VIRT_TO_PHYS_ADDR_1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR3
        sta     Z_VECTOR3+1
        beq     L1BFA
        lda     #$00
        sta     Z_VECTOR2
L1BD5:  ldy     Z_VECTOR2
        ldx     Z_LOCAL_VARIABLES,y
        lda     Z_LOCAL_VARIABLES+1,y
        jsr     PUSH_AX_TO_STACK
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
        bne     L1BD5
L1BFA:  dec     $79
        beq     L1C5C
        lda     Z_OPERAND2
        sta     Z_LOCAL_VARIABLES
        lda     Z_OPERAND2+1
        sta     Z_LOCAL_VARIABLES+1
        dec     $79
        beq     L1C5C
        lda     Z_VECTOR0
        sta     $0F02
        lda     Z_VECTOR0+1
        sta     $0F03
        dec     $79
        beq     L1C5C
        lda     $81
L1C1C:  sta     $0F04
        lda     $82
        sta     $0F05
        dec     $79
        beq     L1C5C
        lda     $83
        sta     $0F06
        lda     $84
        sta     $0F07
        dec     $79
        beq     L1C5C
        lda     $85
        sta     $0F08
        lda     $86
        sta     $0F09
        dec     $79
        beq     L1C5C
        lda     $87
        sta     $0F0A
        lda     $88
        sta     $0F0B
        dec     $79
        beq     L1C5C
        lda     $89
        sta     $0F0C
        lda     $8A
        sta     $0F0D
L1C5C:  ldx     Z_VECTOR3+1
        txa
        jsr     PUSH_AX_TO_STACK
        lda     Z_STACK_POINTER+1
        sta     Z_SOMETHING_NOT_PC
        lda     Z_STACK_POINTER
        sta     $66
        rts

; VAR:225 1 storew array word-index value
; array-->word-index = value, i.e. stores the given value in the word at
; address array+2*wordindex (which must lie in dynamic memory).

Z_STOREW:
	asl	$7D
	rol	$7E
	jsr     L1C81
        lda     Z_VECTOR0+1
        sta     (Z_VECTOR2),y
        iny
        bne     L1C7C

; VAR:226 2 storeb array byte-index value
; array->byte-index = value, i.e. stores the given value in the byte at
; address array+byte-index (which must lie in dynamic memory). (See loadb.)

Z_STOREB   jsr     L1C81
L1C7C:  lda     Z_VECTOR0
        sta     (Z_VECTOR2),y
        rts

L1C81:  lda     Z_OPERAND2
        clc
        adc     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND2+1
        adc     Z_OPERAND1+1
        clc
        adc	Z_BASE_PAGE		; reufix
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

Z_PUT_PROP:   jsr     L26F9
L1C97:  jsr     L2717
        cmp     Z_OPERAND2
        beq     L1CA6
        bcc     Z_ERROR_0A
        jsr     L2746
        jmp     L1C97
L1CA6:  jsr     L271C
        iny
        cmp     #$01
        beq     L1CB7
        cmp     #$02
        bne     Z_ERROR_0B
        lda     Z_VECTOR0+1
        sta     (Z_VECTOR2),y
        iny
L1CB7:  lda     Z_VECTOR0
        sta     (Z_VECTOR2),y
        rts

Z_ERROR_0A:  lda     #$0A
        jmp     FATAL_ERROR
Z_ERROR_0B:  lda     #$0B
        jmp     FATAL_ERROR

; VAR:229 5 print_char output-character-code
; Print a ZSCII character. The operand must be a character code defined in
; ZSCII for output (see S3). In particular, it must certainly not be negative
; or larger than 1023.

Z_PRINT_CHAR
        lda     Z_OPERAND1
        jmp     PUT_CHAR_ALT

; VAR:230 6 print_num value
; Print (signed) number in decimal.

Z_PRINT_NUM
        lda     Z_OPERAND1
        sta     L2CA5
        lda     Z_OPERAND1+1
        sta     L2CA6
        lda     L2CA6
        bpl     L1CE2
        lda     #$2D
        jsr     PUT_CHAR_ALT
        jsr     L1AF7
L1CE2:  lda     #$00
        sta     L2CAD
L1CE7:  lda     L2CA5
        ora     L2CA6
        beq     L1D05
        lda     #$0A
        sta     L2CA7
        lda     #$00
        sta     L2CA8
        jsr     L1B09
        lda     L2CA7
        pha
        inc     L2CAD
        bne     L1CE7
L1D05:  lda     L2CAD
        bne     L1D0F
        lda     #$30
        jmp     PUT_CHAR_ALT
L1D0F:  pla
        clc
        adc     #$30
        jsr     PUT_CHAR_ALT
        dec     L2CAD
        bne     L1D0F
        rts

; VAR:231 7 random range -> (result)
; If range is positive, returns a uniformly random number between 1 and range.
; If range is negative, the random number generator is seeded to that value
; and the return value is 0. Most interpreters consider giving 0 as range
; illegal (because they attempt a division with remainder by the range), but
; correct behaviour is to reseed the generator in as random a way as the
; interpreter can (e.g. by using the time in milliseconds).

Z_RANDOM
.(
	lda	Z_OPERAND1
        ora     Z_OPERAND1+1
        bne     L1
        sta     $61
        sta     $62
        jmp     RETURN_ZERO
L1	lda     $61
        ora     $62
        bne     L3
        lda     Z_OPERAND1+1
        bpl     L2
        eor     #$FF
        sta     $62
        lda     Z_OPERAND1
        eor     #$FF
        sta     $61
        inc     $61
        lda     #$00
        sta     $44
        sta     Z_CURRENT_WINDOW
        beq     L3
L2	lda     Z_OPERAND1
        sta     Z_OPERAND2
        lda     Z_OPERAND1+1
        sta     Z_OPERAND2+1
        jsr     RNG_HW
        stx     Z_OPERAND1
        and     #$7F
        sta     Z_OPERAND1+1
        jsr     L1AAD
        lda     L2CA7
        clc
        adc     #$01
        sta     Z_VECTOR1
        lda     L2CA8
        adc     #$00
        sta     Z_VECTOR1+1
        jmp     RETURN_NULL
L3	lda     $62
        cmp     Z_OPERAND1+1
        bcc     L5
        bne     L4
        lda     Z_OPERAND1
        cmp     $61
        bcs     L5
L4	lda     Z_OPERAND1+1
        sta     $62
        lda     Z_OPERAND1
        sta     $61
L5	lda     Z_CURRENT_WINDOW
        cmp     $62
        bcc     L7
        lda     $44
        cmp     $61
        bcc     L7
        beq     L7
L6	lda     #$01
        sta     $44
        lda     #$00
        sta     Z_CURRENT_WINDOW
L7	lda     $44
        sta     Z_VECTOR1
        lda     Z_CURRENT_WINDOW
        sta     Z_VECTOR1+1
        inc     $44
        bne     L8
        inc     Z_CURRENT_WINDOW
L8	jmp     RETURN_NULL
.)

; VAR:232 8 push value
; Pushes value onto the game stack.

Z_PUSH
        ldx     Z_OPERAND1
        lda     Z_OPERAND1+1
        jmp     PUSH_AX_TO_STACK

; VAR:233 9 1 pull (variable)
; Pulls value off a stack. (If the stack underflows, the interpreter should
; halt with a suitable error message.)

Z_PULL: jsr     Z_POP
        lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

; insert description here

Z_SCAN_TABLE
        lda     Z_OPERAND2
        sta     $14
        lda     Z_OPERAND2+1
        sta     $15
        lda     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
L1DC8:  jsr     FETCH_BYTE_FROM_VECTOR
        sta     Z_VECTOR2+1
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     Z_OPERAND1
        bne     L1DDA
        lda     Z_VECTOR2+1
        cmp     Z_OPERAND1+1
        beq     L1DE7
L1DDA:  dec     Z_VECTOR0
        bne     L1DC8
        lda     Z_VECTOR0+1
        beq     L1DFE
        dec     Z_VECTOR0+1
        jmp     L1DC8
L1DE7:  sec
        lda     $14
        sbc     #$02
        sta     $14
        bcs     L1DF2
        dec     $15
L1DF2:  sta     Z_VECTOR1
        lda     $15
        sta     Z_VECTOR1+1
        jsr     RETURN_NULL
        jmp     L1468
L1DFE:  lda     #$00		; shouldn't this be RETURN_ZERO?
        sta     Z_VECTOR1
        sta     Z_VECTOR1+1
        jsr     RETURN_NULL
        jmp     L145C

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

Z_SREAD:	lda     Z_OPERAND1+1
        clc
        adc    Z_BASE_PAGE	; reufix
        sta     $47
        lda     Z_OPERAND1
        sta     $46
        lda     Z_OPERAND2+1
        clc
        adc	Z_BASE_PAGE	;reufix
        sta     $49
        lda     Z_OPERAND2
        sta     $48
        ldy     #$00
        lda     ($46),y
        cmp     #$4F
        bcc     L1E2A
        lda     #$4E
L1E2A:  sta     $43
        jsr     L2E0B
        sta     $26
        lda     #$00
        sta     $27
        ldy     #$01
        sta     ($48),y
        sty     $24
        iny
        sty     $25
L1E3E:  ldy     #$00
        lda     ($48),y
        beq     L1E48
        cmp     #$3C
        bcc     L1E4C
L1E48:  lda     #$3B
        sta     ($48),y
L1E4C:  iny
        cmp     ($48),y
        bcc     L1E57
        lda     $26
        ora     $27
        bne     L1E58
L1E57:  rts

L1E58:  lda     $27
        cmp     #$09
        bcc     L1E61
        jsr     L1EF2
L1E61:  lda     $27
        bne     L1E8A
        ldx     #$08
L1E67:  sta     L2C93,x
        dex
        bpl     L1E67
        jsr     L1EE4
        lda     $24
        ldy     #$03
        sta     ($28),y
        tay
        lda     ($46),y
        jsr     L1F1F
        bcs     L1EA5
        jsr     L1F13
        bcc     L1E8A
        inc     $24
        dec     $26
        jmp     L1E3E

L1E8A:  lda     $26
        beq     L1EAE
        ldy     $24
        lda     ($46),y
        jsr     L1F0E
        bcs     L1EAE
        ldx     $27
        sta     L2C93,x
        dec     $26
        inc     $27
        inc     $24
        jmp     L1E3E

L1EA5:  sta     L2C93
        dec     $26
        inc     $27
        inc     $24
L1EAE:  lda     $27
        beq     L1E3E
        jsr     L1EE4
        lda     $27
        ldy     #$02
        sta     ($28),y
        jsr     L25A9
        jsr     L1F4A
        ldy     #$01
        lda     ($48),y
        clc
        adc     #$01
        sta     ($48),y
        jsr     L1EE4
        ldy     #$00
        sty     $27
        lda     Z_VECTOR1+1
        sta     ($28),y
        iny
        lda     Z_VECTOR1
        sta     ($28),y
        lda     $25
        clc
        adc     #$04
        sta     $25
        jmp     L1E3E

L1EE4:  lda     $48
        clc
        adc     $25
        sta     $28
        lda     $49
        adc     #$00
        sta     $29
        rts

L1EF2:  lda     $26
        beq     L1F07
        ldy     $24
        lda     ($46),y
        jsr     L1F0E
        bcs     L1F07
        dec     $26
        inc     $27
        inc     $24
        bne     L1EF2
L1F07:  rts

PUNCTUATION:  .asc	"!?,.", $0d, " "

L1F0E:  jsr     L1F1F
        bcs     L1F48
L1F13:  ldx     #$05
L1F15:  cmp     PUNCTUATION,x
        beq     L1F48
        dex
        bpl     L1F15
        clc
        rts

L1F1F:  sta     Z_TEMP1
        lda     Z_HDR_DICTIONARY
        ldy     Z_HDR_DICTIONARY+1
        sta     $15
        sty     $14
        lda     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     Z_VECTOR3
L1F37:  jsr     FETCH_BYTE_FROM_VECTOR
        cmp     Z_TEMP1
        beq     L1F46
        dec     Z_VECTOR3
        bne     L1F37
        lda     Z_TEMP1
        clc
        rts

L1F46:  lda     Z_TEMP1
L1F48:  sec
        rts

L1F4A:  lda     Z_HDR_DICTIONARY
        ldy     Z_HDR_DICTIONARY+1
        sta     $15
        sty     $14
        lda     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
        jsr     FETCH_BYTE_FROM_VECTOR
        clc
        adc     $14
        sta     $14
        bcc     L1F67
        inc     $15
L1F67:  jsr     VIRT_TO_PHYS_ADDR
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $2C
        sta     Z_VECTOR2
        lda     #$00
        sta     Z_VECTOR2+1
        sta     Z_VECTOR3
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $2B
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $2A
        lda     #$00
        sta     $6B
        sta     $6C
        sta     $6D
        ldx     $2C
L1F8B:  clc
        lda     $6B
        adc     $2A
        sta     $6B
        lda     $6C
        adc     $2B
        sta     $6C
        lda     $6D
        adc     #$00
        sta     $6D
        dex
        bne     L1F8B
        clc
        lda     $6B
        adc     $14
        sta     $6B
        lda     $6C
        adc     $15
        sta     $6C
        lda     $6D
        adc     $16
        sta     $6D
        lda     $6B
        sec
        sbc     $2C
        sta     $6B
        lda     $6C
        sbc     #$00
        sta     $6C
        lsr     $2B
        ror     $2A
L1FC5:  asl     Z_VECTOR2
        rol     Z_VECTOR2+1
        rol     Z_VECTOR3
        lsr     $2B
        ror     $2A
        bne     L1FC5
        clc
        lda     $14
        adc     Z_VECTOR2
        sta     $14
        lda     $15
        adc     Z_VECTOR2+1
        sta     $15
        lda     $16
        adc     Z_VECTOR3
        sta     $16
        sec
        lda     $14
        sbc     $2C
        sta     $14
        bcs     L1FFC
        lda     $15
        sec
        sbc     #$01
        sta     $15
        bcs     L1FFC
        lda     $16
        sbc     #$00
        sta     $16
L1FFC:  lsr     Z_VECTOR3
        ror     Z_VECTOR2+1
        ror     Z_VECTOR2
        lda     $14
        sta     Z_VECTOR3+1
        lda     $15
        sta     $0A
        lda     $16
        sta	$0B
        jsr     VIRT_TO_PHYS_ADDR
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L2C9C
        bcc     L204D
        bne     L2081
        jsr     FETCH_BYTE_FROM_VECTOR
	cmp	L2C9D
	bcc	L204D
        bne     L2081
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L2C9E
        bcc     L204D
        bne     L2081
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L2C9F
        bcc     L204D
        bne     L2081
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L2CA0
        bcc     L204D
        bne     L2081
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L2CA1
        beq     L20AC
        bcs     L2081
L204D:  lda     Z_VECTOR3+1
        clc
        adc     Z_VECTOR2
        sta     $14
        lda     $0A
        adc     Z_VECTOR2+1
        bcs     L2072
        sta     $15
        lda	#$00
        sta     $16
	lda	$15
	cmp	$6C
	beq	L206A
        bcs     L2072
        bcc     L2094
L206A:  lda     $14
L206C:  cmp     $6B
        bcc     L2094
        beq     L2094
L2072:  lda     $6B
L2074:  sta     $14
        lda     $6C
        sta     $15
        lda     $6D
        sta     $16
        jmp     L2094

L2081:  lda     Z_VECTOR3+1
        sec
        sbc     Z_VECTOR2
        sta     $14
        lda     $0A
        sbc     Z_VECTOR2+1
        sta     $15
        lda     $0B
        sbc     Z_VECTOR3
        sta     $16
L2094:  lda     Z_VECTOR3
        bne     L20A2
        lda     Z_VECTOR2+1
        bne     L20A2
        lda     Z_VECTOR2
        cmp     $2C
        bcc     L20A5
L20A2:  jmp     L1FFC

L20A5:  lda     #$00
        sta     Z_VECTOR1
        sta     Z_VECTOR1+1
        rts

L20AC:  lda     Z_VECTOR3+1
        sta     Z_VECTOR1
        lda     $0A
        sta     Z_VECTOR1+1
        rts

; grab #$ff bytes from from ($(17)+$14)

FETCH_BYTE_FROM_VECTOR:
        sei
        lda     R6510
        and     #MAP_RAM
        sta     R6510
L20C2:  ldy     $14
        lda     (Z_CURRENT_PHYS_PC_ALT),y
        tax
        sei
        lda     R6510
        ora     #MAP_ROM
        sta     R6510
        cli
        txa
        inc     $14
        bne     L20D7
        jsr     L244A
L20D7:  tay
        rts

FETCH_NEXT_ZBYTE:
.(
        sei
        lda     R6510
        and     #MAP_RAM
        sta     R6510
L1	ldy     Z_PC
        lda     (Z_CURRENT_PHYS_PC),y
        tax
        sei
        lda     R6510
        ora     #MAP_ROM
        sta     R6510
        cli
        txa
        inc     Z_PC
        bne     L20FB
L2	pha
        inc     Z_PC+1
        bne     L3
        inc     $10
L3	jsr     VIRT_TO_PHYS_ADDR_1
        pla
L20FB:  tay
        rts
.)

L20FD
.(
	lda     Z_VECTOR2
        sta     $14
        lda     Z_VECTOR2+1
        sta     $15
        lda     #$00
        sta     $16
        jmp     VIRT_TO_PHYS_ADDR
.)

L210C:  .byte	0
L210D:  .byte	0
L210E:  .byte	0
L210F:  .byte	0
L2110:  .byte	0
L2111:  .byte	0
L2112:  .byte	0
L2113:  .byte	0
L2114:  .byte	0
L2115:  .byte	0

;
; This converts virtual address in ($15) to real address in ($18)
:

VIRT_TO_PHYS_ADDR
.(
	lda     $16			; um, start of a page?
        bne     L2
        lda     $15
        cmp     Z_HIGH_ADDR		; are we in resident page?
        bcs     L2
					; handle resident here
        adc     #>Z_HEADER		; calculate physical address
        sta     Z_CURRENT_PHYS_PC_ALT+1
L1	rts

L2	lda     $16			; we are above resident space
        ldy     $15
        jsr     CALC_NONRESIDENT_PHYS_ADDR
        clc
        adc     MAX_RES_PAGE_CALC	; #$FA
        sta     Z_CURRENT_PHYS_PC_ALT+1
        lda     L216C
        beq     L1
        jmp     VIRT_TO_PHYS_ADDR_1		; extraneous?
.)

VIRT_TO_PHYS_ADDR_1
.(
	lda     $10			; Z_CURRENT_PHYS_PC-1
        bne     L2
        lda     Z_PC+1
        cmp     Z_HIGH_ADDR		; are we above resident?
        bcs     L2
					; handle resident here.
        adc     #>Z_HEADER
        sta     Z_CURRENT_PHYS_PC+1
L1	rts

L2	lda     $10			; we are above resident space
        ldy     Z_PC+1
        jsr     CALC_NONRESIDENT_PHYS_ADDR
        clc
        adc     MAX_RES_PAGE_CALC	; #$FA
        sta     Z_CURRENT_PHYS_PC+1
        lda     L216C
        beq     L1
        jmp     VIRT_TO_PHYS_ADDR
.)
L216C:  .byte	0


CALC_NONRESIDENT_PHYS_ADDR
.(
	sta     L210D
        sty     L210C
        ldx     #$00
        stx     L216C
        jsr     L225B
        bcc     L21A1
        ldx     L210E
        lda     $0D00,x
        sta     L210E
        tax
        lda     L210D
        sta     $0E00,x
        lda     L210C
        sta     $0E80,x
        tay
        txa
        pha
        lda     L210D
        jsr     REU_FETCH
        dec     L216C
        pla
        rts
L21A1:  sta     L210F
        cmp     L210E
        bne     L21AA
        rts
L21AA:  ldy     L210E
        lda     $0D00,y
        sta     L2112
        lda     L210F
        jsr     L223D
        ldy     L210E
        lda     L210F
        jsr     L2217
        lda     L210F
        sta     L210E
.)
L21C8:  rts

;
; retrieve (STORY_INDEX) from (REU_BASE-Z_HIGH_ADDR) to (PAGE_VECTOR)
;


REU_FETCH
.(
	sta     STORY_INDEX+1
        sty     STORY_INDEX
        txa
        clc
        adc     MAX_RES_PAGE_CALC	; #$FA
        sta     PAGE_VECTOR+1		; ultimately getting stashed here

        jsr     UIEC_ONLY
        bcc     L1
        clc
        ldx     STORY_INDEX+1
        lda     STORY_INDEX
        jsr     IEC_FETCH
        jmp     L2

L1
;
; REU
;

	lda     STORY_INDEX
        sec
        sbc     Z_HIGH_ADDR
        tay				; pha
        lda     STORY_INDEX+1
        sbc     #$00
        tax

	jsr	IREU_FETCH
L2
	jsr	SECBUF_TO_PVEC
	rts
.)

L2217:  sta     L2114
        sty     L2113
        tax
        tya
        sta     $0D80,x
        lda     $0D00,y
        sta     L2115
        txa
        ldx     L2115
        sta     $0D80,x
        txa
        ldx     L2114
        sta     $0D00,x
        lda     L2114
        sta     $0D00,y
        rts

L223D
.(
	tax
        lda     $0D00,x
        sta     L2110
        lda     $0D80,x
        sta     L2111
        tax
        lda     L2110
        sta     $0D00,x
        lda     L2111
        ldx     L2110
        sta     $0D80,x
        rts
.)

L225B
.(
	ldx     #$04
L1	lda     L210D
        cmp     $0E00,x
        beq     L3
L2	dex
        bpl     L1
        sec
        rts
L3	tya
        cmp     $0E80,x
        bne     L2
        txa
        clc
        rts
.)

LOAD_RESIDENT
.(
	ldx     #$04
        stx     L210E
        lda     #$FF
L1	sta     $0E00,x
        dex
        bpl     L1
        ldx     #$00
        ldy     #$01
L2	tya
        sta     $0D80,x
        inx
        iny
        cpx     #$05
        bcc     L2
        lda     #$00
        dex
        sta     $0D80,x
        ldx     #$00
        ldy     #$FF
        lda     #$04
L3	sta     $0D00,x
        inx
        iny
        tya
        cpx     #$05
        bcc     L3

L4	lda     STORY_INDEX
        cmp     Z_HIGH_ADDR	
        bcs     LOAD_NONRESIDENT

	lda	REU_PRESENT
	and	#%00000100
	bne	L4a

;        jsr	DO_TWIRLY

L4a	ldx	#5
        jsr     READ_BUFFER
        bcc     L4
        jmp     FATAL_ERROR_0E
.)

LOAD_NONRESIDENT:
	lda	REU_PRESENT
	and	#%00000100
	beq	L0a

                        ; at this point, EF_VEC1+2 has non-res base page and
                        ; EF_BANK has non-res base bank ...
        lda     EF_VEC1+2
        sta     EF_NONRES_PAGE_BASE
        lda     EF_BANK
        sta     EF_NONRES_BANK_BASE
	rts

L0a
	jsr	UIEC_ONLY
	bcc	L0aa
	clc
	rts
L0aa
        ldy     #$01
        ldx     #$0F
        clc
        jsr     PLOT
        ldx     #<REU_TXT
        lda     #>REU_TXT
	ldy     #$28
        jsr     PRINT_MESSAGE

	lda     Z_HDR_FILE_LENGTH+1
        sta     Z_VECTOR3
        lda     Z_HDR_FILE_LENGTH
        ldy     #$05
L22DC:  lsr
        ror     Z_VECTOR3
        dey
        bpl     L22DC
        sta     Z_VECTOR3+1
        sec
        lda     Z_VECTOR3
        sbc     #$AF			; magic number - beware
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
L2306:  jsr     DEC_PAGE_COUNT			; are we done?
        bcc     L2317			; if so, exit ...
;	jsr	DO_TWIRLY
        lda     #>SECTOR_BUFFER
        sta     PAGE_VECTOR+1
	ldx	#5
        jsr     READ_BUFFER
        bcc     REU_STASH
L2314   jmp     FATAL_ERROR_0E		; this vectors to that weird thing
L2317
        rts

REU_STASH:
.(
	jsr	IREU_STASH
	inc     Z_VECTOR2+1
        bne     L1
        inc     Z_VECTOR4
L1	jmp     L2306
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

L244A:  pha
        inc     $15
        bne     L2451
        inc     $16
L2451:  jsr     VIRT_TO_PHYS_ADDR
        pla
        rts

L2462:  lda     Z_VECTOR2
        asl
        sta     $14
        lda     Z_VECTOR2+1
        rol
        sta     $15
        lda     #$00
        rol
        sta     $16
        asl     $14
        rol     $15
        rol     $16
        jmp     VIRT_TO_PHYS_ADDR

L247A:  rts

L247B:  ldx     #$00
        stx     $2D
        stx     $31
        dex
        stx     $2E
L2484:  jsr     L2561
        bcs     L247A
        sta     $2F
        tax
        beq     L24CF
        cmp     #$04
        bcc     L24ED
        cmp     #$06
        bcc     L24D3
        jsr     L2543
        tax
        bne     L24A7
        lda     #$5B
L249E:  clc
        adc     $2F
L24A1:  jsr     PUT_CHAR_ALT
        jmp     L2484

L24A7:  cmp     #$01
        bne     L24AF
        lda     #$3B
        bne     L249E
L24AF:  lda     $2F
        sec
        sbc     #$06
        beq     L24BD
        tax
        lda     VALID_PUNCTUATION,x
        jmp     L24A1

L24BD:  jsr     L2561
        asl
        asl
        asl
        asl
        asl
        sta     $2F
        jsr     L2561
        ora     $2F
        jmp     L24A1

L24CF:  lda     #$20
        bne     L24A1
L24D3:  sec
        sbc     #$03
        tay
        jsr     L2543
        bne     L24E1
        sty     $2E
        jmp     L2484

L24E1:  sty     $2D
        cmp     $2D
        beq     L2484
        lda     #$00
        sta     $2D
        beq     L2484
L24ED:  sec
        sbc     #$01
        asl
        asl
        asl
        asl
        asl
        asl
        sta     $30
        jsr     L2561
        asl
        clc
        adc     $30
        tay
        lda     ($20),y
        sta     Z_VECTOR2+1
        iny
        lda     ($20),y
        sta     Z_VECTOR2
        lda     $16
        pha
        lda     $15
        pha
        lda     $14
        pha
        lda     $2D
        pha
        lda     $31
        pha
        lda     $33
        pha
        lda     $32
        pha
        jsr     L254F
        jsr     L247B
        pla
        sta     $32
        pla
        sta     $33
        pla
        sta     $31
        pla
        sta     $2D
        pla
        sta     $14
        pla
        sta     $15
        pla
        sta     $16
        ldx     #$FF
        stx     $2E
        jsr     VIRT_TO_PHYS_ADDR
        jmp     L2484

L2543:  lda     $2E
        bpl     L254A
        lda     $2D
        rts

L254A:  ldy     #$FF
        sty     $2E
        rts

L254F:  lda     Z_VECTOR2
        asl
        sta     $14
        lda     Z_VECTOR2+1
        rol
        sta     $15
        lda     #$00
        rol
        sta     $16
        jmp     VIRT_TO_PHYS_ADDR

L2561:  lda     $31
        bpl     L2567
        sec
        rts
L2567:  bne     L257C
        inc     $31
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $33
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $32
        lda     $33
        lsr
        lsr
        jmp     L25A5
L257C:  sec
        sbc     #$01
        bne     L2597
        lda     #$02
        sta     $31
        lda     $32
        sta     Z_VECTOR2
        lda     $33
        asl     Z_VECTOR2
        rol
        asl     Z_VECTOR2
        rol
        asl     Z_VECTOR2
        rol
        jmp     L25A5
L2597:  lda     #$00
        sta     $31
        lda     $33
        bpl     L25A3
        lda     #$FF
        sta	$31
L25A3:  lda     $32
L25A5:  and     #$1F
        clc
        rts

L25A9:  lda     #$05
        ldx     #$08
L25AD:  sta     L2C9C,x
        dex
        bpl     L25AD
        lda     #$09
        sta     $34
        lda     #$00
        sta     $35
        sta     $36
L25BD:  ldx     $35
        inc     $35
        lda     L2C93,x
        sta     $2F
        bne     L25CC
        lda     #$05
        bne     L25F9
L25CC:  lda     $2F
        jsr     L2646
        beq     L25F4
        clc
        adc     #$03
        ldx     $36
        sta     L2C9C,x
        inc     $36
        dec     $34
        bne     L25E4
        jmp     L265F

L25E4:  lda     $2F
        jsr     L2646
        cmp     #$02
        beq     L2607
        lda     $2F
        sec
        sbc     #$3B
        bpl     L25F9
L25F4:  lda     $2F
        sec
        sbc     #$5B
L25F9:  ldx     $36
        sta     L2C9C,x
        inc     $36
        dec     $34
        bne     L25BD
        jmp     L265F

L2607:  lda     $2F
        jsr     L2636
        bne     L25F9
        lda     #$06
        ldx     $36
        sta     L2C9C,x
        inc     $36
        dec     $34
        beq     L265F
        lda     $2F
        lsr
        lsr
        lsr
        lsr
        lsr
        and     #$03
        ldx     $36
        sta     L2C9C,x
        inc     $36
        dec     $34
        beq     L265F
        lda     $2F
        and     #$1F
        jmp     L25F9

L2636:  ldx     #$19
L2638:  cmp     VALID_PUNCTUATION,x
        beq     L2641
        dex
        bne     L2638
        rts

L2641:  txa
        clc
        adc     #$06
        rts

L2646:  cmp     #$61
        bcc     L2651
        cmp     #$7B
        bcs     L2651
        lda     #$00
        rts

L2651:  cmp     #$41
        bcc     L265C
        cmp     #$5B
        bcs     L265C
        lda     #$01
        rts

L265C:  lda     #$02
        rts

L265F:  lda     L2C9D
        asl
        asl
        asl
        asl
        rol     L2C9C
        asl
        rol     L2C9C
        ora     L2C9E
        sta     L2C9D
        lda     L2CA0
        asl
        asl
        asl
        asl
        rol     L2C9F
        asl
        rol     L2C9F
        ora     L2CA1
        tax
        lda     L2C9F
        sta     L2C9E
        stx     L2C9F
        lda     L2CA3
        asl
        asl
        asl
        asl
        rol     L2CA2
        asl
        rol     L2CA2
        ora     L2CA4
        sta     L2CA1
        lda     L2CA2
        ora     #$80
        sta     L2CA0
        rts

CALC_PHYS_ADDR_3:
.(
	stx     Z_VECTOR2+1
        asl
        sta     Z_VECTOR2
        rol     Z_VECTOR2+1
        ldx     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        asl
        rol     Z_VECTOR2+1
        sec
        sbc     Z_VECTOR2
        sta     Z_VECTOR2
        lda     Z_VECTOR2+1
        stx     Z_VECTOR2+1
        sbc     Z_VECTOR2+1
        sta     Z_VECTOR2+1
        lda     Z_VECTOR2
        clc
        adc     #$70
        bcc     L26ED
        inc     Z_VECTOR2+1
L26ED:  clc
        adc     Z_OBJECTS_ADDR		; reufix
        sta     Z_VECTOR2
        lda     Z_VECTOR2+1
        adc     Z_OBJECTS_ADDR+1
        sta     Z_VECTOR2+1
        rts
.)

L26F9:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        ldy     #$0C
        lda     (Z_VECTOR2),y
        clc
        adc    Z_BASE_PAGE		; reufix
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

L2717:  lda     (Z_VECTOR2),y
        and     #$3F
        rts

L271C:  lda     (Z_VECTOR2),y
        and     #$80
        beq     L2728
        iny
        lda     (Z_VECTOR2),y
        and     #$3F
        rts

L2728:  lda     (Z_VECTOR2),y
        and     #$40
        beq     L2731
        lda     #$02
        rts

L2731:  lda     #$01
        rts

L2734:  jsr     L271C
        tax
L2738:  iny
        bne     L2741
        inc     Z_VECTOR2
        bne     L2741
        inc     Z_VECTOR2+1
L2741:  dex
        bne     L2738
        iny
        rts

L2746:  jsr     L2734
        tya
        clc
        adc     Z_VECTOR2
        sta     Z_VECTOR2
        bcc     L2753
        inc     Z_VECTOR2+1
L2753:  ldy     #$00
        rts

L2756:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     CALC_PHYS_ADDR_3
        lda     Z_OPERAND2
        cmp     #$10
        bcc     L2787
        sbc     #$10
        tax
        cmp     #$10
        bcc     L277B
        sbc     #$10
        tax
        lda     Z_VECTOR2
        clc
        adc     #$04
        sta     Z_VECTOR2
        bcc     L2786
        inc     Z_VECTOR2+1
        jmp     L2786

L277B:  lda     Z_VECTOR2
        clc
        adc     #$02
        sta     Z_VECTOR2
        bcc     L2786
        inc     Z_VECTOR2+1
L2786:  txa
L2787:  sta     $0A
        ldx     #$01
        stx     Z_VECTOR3
        dex
        stx     Z_VECTOR3+1
        lda     #$0F
        sec
        sbc     $0A
        tax
        beq     L279F
L2798:  asl     Z_VECTOR3
        rol     Z_VECTOR3+1
        dex
        bne     L2798
L279F:  ldy     #$00
        lda     (Z_VECTOR2),y
        sta     $0B
        iny
        lda     (Z_VECTOR2),y
        sta     $0A
        rts

FATAL_ERROR
.(
	jsr	CLOSE_ALL_FILES
	ldy     #$01
L1	ldx     #$00
L2	cmp     #$0A
        bcc     L3
        sbc     #$0A
        inx
        bne     L2
L3	ora     #$30
        sta     INT_ERROR_TEXT+15,y
        txa
        dey
        bpl     L1
        ldx     #<INT_ERROR_TEXT
        lda     #>INT_ERROR_TEXT
        ldy     #$14
        jsr     PRINT_MESSAGE
.)


Z_QUIT: jsr     Z_NEW_LINE
        ldx     #<END_SESSION_TEXT
        lda     #>END_SESSION_TEXT
        ldy     #$2C
        jsr     PRINT_MESSAGE
        jmp     L27F0

Z_RESTART:  jsr     Z_NEW_LINE
L27F0:
	jsr	PRESS_RETURN

L2808:  lda     Z_HDR_FLAGS2+1
        and     #$01
        sta     INTERP_FLAGS
        jmp     STARTUP

; We max out at a resident size of 0xB000 (0xEA00 - 0x3A00, which is the
; storyfile start address

GET_MAX_PAGE:
	lda     #MAX_RAM_PAGE
        rts

PUT_CHAR_ALT:  sta     Z_TEMP1
        ldx     $6A
        beq     L284B
        jmp     L28C3

L284B:  ldx     $68
        bne     L2854
        ldx     $69
        bne     L2854
        rts

L2854:  lda     Z_TEMP1
        ldx     $42
        bne     L2883
        cmp     #$0D
        bne     L2861
        jmp     Z_NEW_LINE

L2861:  cmp     #$20
        bcc     L2882
        ldx     $4B
        sta     INPUT_BUFFER,x
        ldy     $4A
        lda     Z_CURRENT_WINDOW
        bne     L2877
        cpy     #$27
        bcc     L287E
        jmp     L28DD

L2877:  cpy     #SCREEN_WIDTH
        bcs     L287E
        jmp     L28DD

L287E:  inc     $4A
        inc     $4B
L2882:  rts

L2883:  sta     Z_TEMP1
        cmp     #$20
        bcc     L28C0
        sec
        jsr     PLOT
        lda     Z_CURRENT_WINDOW
        beq     L289B
        cpy     #SCREEN_WIDTH
        bcs     L28C0
        cpx     $52
        bcs     L28C0
        bcc     L28A3
L289B:  cpy     #SCREEN_WIDTH-1
        bcs     L28C0
        cpx     $52
        bcc     L28C0
L28A3:  lda     $68
        beq     L28AC
        lda     Z_TEMP1
        jsr     PUT_CHARACTER
L28AC:  lda     Z_CURRENT_WINDOW
        bne     L28C0
        lda     #$01
        sta     $58
        lda     Z_TEMP1
        sta     INPUT_BUFFER
        jsr     LOG_TO_PRINTER
        lda     #$00
        sta     $58
L28C0:  jmp     L3094

L28C3:  tax
        lda     $3E
        clc
        adc     $3C
        sta     Z_VECTOR2
        lda     $3F
        adc     $3D
        sta     Z_VECTOR2+1
        ldy     #$00
        txa
        sta     (Z_VECTOR2),y
        inc     $3E
        bne     L28DC
        inc     $3F
L28DC:  rts

L28DD:  lda     #$20
        stx     $4D
L28E1:  cmp     INPUT_BUFFER,x
        beq     L28F1
        dex
        bne     L28E1
        ldx     #$27
        lda     Z_CURRENT_WINDOW
        beq     L28F1
        ldx     #SCREEN_WIDTH
L28F1:  stx     $4C
        stx     $4B
        jsr     Z_NEW_LINE
        ldx     $4C
        ldy     #$00
L28FC:  inx
        cpx     $4D
        bcc     L2908
        beq     L2908
        sty     $4A
        sty     $4B
        rts
L2908:  lda     INPUT_BUFFER,x
        sta     INPUT_BUFFER,y
        iny
        bne     L28FC

Z_NEW_LINE:  ldx     $4B
        lda     Z_CURRENT_WINDOW
        beq     L291B
        cpx     #SCREEN_WIDTH
        bcs     L2922
L291B:  lda     #$0D
        sta     INPUT_BUFFER,x
        inc     $4B
L2922:  lda     $68
        beq     L2971
        lda     Z_CURRENT_WINDOW
        bne     L292C
L292A:  inc     $4F
L292C:  ldx     $4F
        inx
        cpx     Z_CURRENT_WINDOW_HEIGHT
        bcc     L2971
        lda     #$00
        sta     $4F
        sta     COLOR
        sta     $C6
        sec
        jsr     PLOT
        sty     $77
        stx     $78
        ldx     #<MORE_TEXT
        lda     #>MORE_TEXT
        ldy     #$06
        jsr     PRINT_MESSAGE
L294D:  jsr	GETIN
        tax
        beq     L294D
        ldy     $77
        ldx     $78
        clc
        jsr     PLOT
        lda     #$01
        sta     COLOR
        ldx     #<BLANK_TEXT
        lda     #>BLANK_TEXT
        ldy     #$06
        jsr     PRINT_MESSAGE
        ldy     $77
        ldx     $78
        clc
        jsr     PLOT
L2971:  jsr     L297B
        lda     #$00
        sta     $4A
        sta     $4B
        rts

L297B:  ldy     $4B
        beq     L2998
        sty     $58
        lda     $68
        beq     L2991
        ldx     #$00
L2987:  lda     INPUT_BUFFER,x
        jsr     PRINT_CHAR_AT_COORDINATE
        inx
        dey
        bne     L2987
L2991:  lda     Z_CURRENT_WINDOW
        bne     L2998
        jsr     LOG_TO_PRINTER
L2998:  rts

L2999:  jsr     L297B
        ldx     #$00
        stx     $4B
        rts

Z_SHOW_STATUS:  rts

Z_BUFFER_MODE:        ldx     Z_OPERAND1
        bne     L29B1
        jsr     L297B
        ldx     #$00
        stx     $4B
        inx
        stx     $42
        rts

L29B1:  dex
        bne     L29B6
        stx     $42
L29B6:  rts

Z_OUTPUT_STREAM
.(
	ldx     Z_OPERAND1
        bmi     L2
        dex
        beq     L4
        dex
        beq     TRANSCRIPT_ON
        dex
        beq     L29F3
        dex
        beq     L1
L1	rts
L2	inx
        beq     L5
        inx
        beq     TRANSCRIPT_OFF
        inx
        beq     L2A0A
        inx
        beq     L3
L3	rts
L4	inx
        stx     $68
        rts
L5	stx     $68
        rts
.)

TRANSCRIPT_ON
.(
	inx
        stx     $69
        lda     Z_HDR_FLAGS2+1
        ora     #%00000001
        sta     Z_HDR_FLAGS2+1
        rts
.)

TRANSCRIPT_OFF
.(
	stx     $69
        lda     Z_HDR_FLAGS2+1
        and     #%11111110
        sta     Z_HDR_FLAGS2+1
        rts
.)

L29F3:  inx
        stx     $6A
        lda     Z_OPERAND2+1
        clc
        adc    Z_BASE_PAGE		; reufix
        ldx     Z_OPERAND2
        stx     $3C
        sta     $3D
        lda     #$02
        sta     $3E
        lda     #$00
        sta     $3F
        rts

L2A0A
.(
	lda     $6A
        beq     L3
        stx     $6A
        lda     $3E
        clc
        adc     $3C
        sta     Z_VECTOR2
        lda     $3F
        adc     $3D
        sta     Z_VECTOR2+1
        lda     #$00
        tay
L1	sta     (Z_VECTOR2),y
        ldy     #$01
        lda     $3E
        sec
        sbc     #$02
        sta	($3C),y
        bcs     L2
        dec     $3F
L2	lda     $3F
        dey
        sta     ($3C),y
        lda     #$00
        sta     $3B
L3	rts
.)

Z_SET_CURSOR
.(
	lda     Z_HDR_MODE_BITS
        and     #$10	; supports fixed-width font?
        beq     L1
        lda     Z_CURRENT_WINDOW
        beq     L1
        lda     $42
        beq     L1
        ldx     Z_OPERAND1
        dex
        ldy     Z_OPERAND2
        dey

	lda	WHICH_GAME
	cmp	#2	; Trinity
	bne	L1b
	lda	Z_CURRENT_WINDOW	; if 0, status line
	beq	L1a
	cpy	#20
	bcc	L1a
	tya
	lsr		; divide by two to avoid overrunning 40 columns
	tay
	jmp	L1a	; end Trinity
L1b
#ifdef	BAD_FIXUPS	; status-line fixups
	cmp	#1	; AMFV
	bne	L1h
	cpx	#2	; status line?
	bcc	L1c	; not status line ...
        tya		; ... so unconditionally divide by 
        lsr             ; divide by two to avoid overrunning 40 columns
        tay
        jmp     L1a
L1c			; AMFV's status line is complex.
			; if row [01] and column 1, set column to 0
			; (suppress actually)
			; if row 0 and column 8 (mode), set column to 6
			; if row [01] and column 59 ("Time:"), set column to 27 
			; (want to turn above to nop, but this is good enoughe
			; (suppress actually)
			; if row 0 and column 66 (time), set column to 33
			; if row 1 and column 12 (location), set column to 10
			; if row > 2 and column either 32 or 34, /2
	cpy     #1
	bne	L1d
	inc	IGNORE_NEXT_PRINT
	dey
	jmp	L1a
L1d	cpy	#59
	bne	L1e
	ldy	#27
	inc	IGNORE_NEXT_PRINT
	jmp	L1a
L1e	cpy	#8
	bne	L1f
	ldy	#6
	jmp	L1a
L1f	cpy	#66
	bne	L1g
	cpx	#0
	bne	L1fa
	ldy	#33
	jmp	L1a
L1fa	ldy	#30
	jmp	L1a
L1g	cpy	#12
	bne	L1a
	ldy	#10	
			; end AMFV

L1h
#endif
L1a     clc
        jsr     PLOT
L1	rts
.)

Z_NOP1:        rts

; VAR:241 11 4 set_text_style style
; Sets the text style to: Roman (if 0), Reverse Video (if 1), Bold (if 2),
; Italic (4), Fixed Pitch (8). In some interpreters (though this is not
; required) a combination of styles is possible (such as reverse video and
; bold). In these, changing to Roman should turn off all the other styles
; currently set.
;
; CK - this looks like it inherited some code from the C128 port.

Z_SET_TEXT_STYLE
.(
        lda     Z_HDR_MODE_BITS
        and     #$0A
        beq     L1	; supports pictures and emphasis? no, return
        ldx     Z_OPERAND1
        bne     L2
        lda     #$92		; reverse off
        jsr     CHROUT
	lda	#$05		; CK
	jsr	CHROUT		; CK
        lda     #$82 	; underline off (on C128/80c)
        jmp     L4
L1	rts
L2	cpx     #$01	; reverse?
        bne     L3
	lda	Z_CURRENT_WINDOW
	beq	L2a
	lda     #$90	; reverse PETSCII
	jsr	CHROUT
L2a	lda	#$12
        jmp     L4
L3	cpx     #$04	; italic?
        bne     L1
        lda     #$02	; underline on (on C128/80c)
L4	sta     Z_TEMP1
        lda     $68
        bne     L5
        lda     $69
        bne     L5
        rts
L5	lda     Z_TEMP1
        ldx     $42
        beq     L6
        jmp     CHROUT
L6	ldx     $4B
        sta     INPUT_BUFFER,x
        inc     $4B
        rts
.)

Z_ERASE_LINE
.(
	lda     Z_HDR_MODE_BITS
        and     #$10			; do we support fixed-width?
        beq     L2ACB
        lda     Z_OPERAND1
        cmp     #$01
        bne     L2ACB
        sec
        jsr     PLOT
        stx     $77
        sty     $78
L2AAA:  iny
        cpy     #$27
        bcs     L2AB7
        lda     #$20
        jsr     CHROUT
        jmp     L2AAA
L2AB7:  ldx     Z_CURRENT_WINDOW
        beq     L2AC0
        lda     #$20
        jsr     CHROUT
L2AC0:  ldx     $77
        ldy     $78
        clc
        jsr     PLOT
        jmp     L3094
.)
L2ACB	rts				; fixme

Z_ERASE_WINDOW
.(	
	lda     Z_HDR_MODE_BITS		; check if game header is good
        and     #$01		
        beq     L2ACB			; return if we are	
        lda     Z_OPERAND1
        beq     L2AE5
        cmp     #$01
        beq     L2B14
        cmp     #$FF
        bne     L2ACB
        jsr     L2F9F
        jmp     CLEAR_SCREEN

L2AE5:  ldx     $52
        lda     VIC_ROW_ADDR_LO,x
        tay
        lda     VIC_ROW_ADDR_HI,x
        sta     Z_VECTOR2+1
        sec
        sbc     #$04
        clc
        adc     #$D8
        sta     Z_VECTOR3+1
        lda     #$00
        sta     Z_VECTOR2
        sta     Z_VECTOR3
        sta     SPENA
        sta     $4F
        lda     #$18
        sec
        sbc     $52
        sta     $0A
        ldx     #$27
        jsr     L2B33
        ldx     #$17
        jmp     L2FED

L2B14:  lda     #>VICSCN
        sta     Z_VECTOR2+1
        lda     #>COLRAM
        sta     Z_VECTOR3+1
        ldy     #$00
        sty     Z_VECTOR2
        sty     Z_VECTOR3
        sty     SPENA
        lda     $52
        sta     $0A
        ldx     #SCREEN_WIDTH
        jsr     L2B33
        ldx     $52
        jmp     L2FED

L2B33:  stx     Z_VECTOR4
L2B35:  lda     #$20
        sta     (Z_VECTOR2),y
        lda     #$01
        sta     (Z_VECTOR3),y
        dex
        bne     L2B46
        dec     $0A
        beq     L2B4F
        ldx     Z_VECTOR4
L2B46:  iny
        bne     L2B35
        inc     Z_VECTOR2+1
        inc     Z_VECTOR3+1
        bne     L2B35
L2B4F:  rts
.)

Z_READ_CHAR:        lda     Z_OPERAND1
        cmp     #$01
        beq     L2B59
        jmp     RETURN_ZERO

L2B59:  ldx     #$00
        stx     $4F
        stx     $4A
        stx     $4B
        stx     $C6
        inx
        stx     SPENA
        dec     $79
        bne     L2B6E
        jmp     L2B8F

L2B6E:  lda     Z_OPERAND2
        sta     Z_VECTOR2+1
        lda     #$00
        sta     Z_VECTOR3+1
        sta     Z_VECTOR3
        dec     $79
        beq     L2B84
        lda     Z_VECTOR0
        sta     Z_VECTOR3
        lda     Z_VECTOR0+1
        sta     Z_VECTOR3+1
L2B84:  jsr     GET_KEY_RETRY
        jsr     L2BB5
        bcc     L2B92
        jmp     RETURN_ZERO

L2B8F:  jsr     GET_KEY
L2B92:  ldx     #$05
L2B94:  cmp     L2BA9,x
        beq     L2B9E
        dex
        bpl     L2B94
        bmi     L2BA1
L2B9E:  lda     L2BAF,x
L2BA1:  ldx     #$00
        jmp     RETURN_VALUE

        jmp     RETURN_ZERO

L2BA9:  .byte   $14, $11, $1d, $91, $5e, $9d
L2BAF:  .byte	$08, $0d, $07, $0e, $0e, $0b

L2BB5:  lda     Z_VECTOR2+1
        sta     Z_VECTOR2
L2BB9:  lda     #$F9
        sta     $A2
L2BBD:  lda     $A2
        bne     L2BBD
        jsr     GETIN
        cmp     #$00
        beq     L2BCE
        jsr     L2D15
        jmp     L2BF8

L2BCE:  inc     L2CAE
        bne     L2BE5
        inc	L2CAF
	bne	L2BE5
        lda     #$E0
        sta     L2CAF
        lda     $0340
        eor     #$FF
        sta     $0340
L2BE5:  dec     Z_VECTOR2
        bne     L2BB9
        lda     Z_VECTOR3
        ora     Z_VECTOR3+1
        beq     L2BF6
        jsr     L2BFA
        lda     Z_VECTOR1
        beq     L2BB5
L2BF6:  sec
        rts

L2BF8:  clc
        rts

L2BFA:  lda     #>L2C7D
        sta     L17D6+2
        lda     #<L2C7D
        sta     L17D6+1
        lda     Z_VECTOR2+1
        pha
        lda     Z_VECTOR3+1
        pha
        lda     Z_VECTOR3
        pha
        ldx     $66
        lda     Z_SOMETHING_NOT_PC
        jsr     PUSH_AX_TO_STACK
        lda     Z_PC
        jsr     PUSH_AX_TO_STACK
        ldx     Z_PC+1
        lda     $10
        jsr     PUSH_AX_TO_STACK
        lda     #$00
        asl     Z_VECTOR3
        rol     Z_VECTOR3+1
        rol
        sta     $10
        asl     Z_VECTOR3
        rol     Z_VECTOR3+1
	rol	$10
	lda	Z_VECTOR3+1
	sta	Z_PC+1
        lda     Z_VECTOR3
        sta     Z_PC
        jsr     VIRT_TO_PHYS_ADDR_1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR3
        sta     Z_VECTOR3+1
        beq     L2C6C
        lda     #$00
        sta     Z_VECTOR2
L2C47:  ldy     Z_VECTOR2
        ldx     Z_LOCAL_VARIABLES,y
        lda     Z_LOCAL_VARIABLES+1,y
        jsr     PUSH_AX_TO_STACK
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
        bne     L2C47
L2C6C:  ldx     Z_VECTOR3+1
        txa
        jsr     PUSH_AX_TO_STACK
        lda     Z_STACK_POINTER
L2C74:  sta     $66
        lda     Z_STACK_POINTER+1
        sta     Z_SOMETHING_NOT_PC
        jmp     MAIN_LOOP

L2C7D:  lda     #<L2314
        sta     L17D6+2
        lda     #>L2314
        sta     L17D6+1
        pla
        pla
        pla
        sta     Z_VECTOR3
        pla
        sta     Z_VECTOR3+1
        pla
        sta     Z_VECTOR2+1
        rts

L2C93:  .dsb	9, 00

L2C9C:  brk
L2C9D:  brk
L2C9E:  brk
L2C9F:  brk
L2CA0:  brk
L2CA1:  brk
L2CA2:  brk
L2CA3:  brk
L2CA4:  brk
L2CA5:  brk
L2CA6:  brk
L2CA7:  brk
L2CA8:  brk
L2CA9:  brk
L2CAA:  brk
L2CAB:  brk
L2CAC:  brk
L2CAD:  brk
L2CAE:  brk
L2CAF:  brk
        brk

MORE_TEXT:	.aasc "[MORE]"

GET_KEY_RETRY:  ldx     #$FF
        stx     $0340
        inx
        stx     L2CAE
        stx     L2CAF
        sec
        jsr     PLOT
        txa
        asl
        asl
        asl
        clc
        adc     #$39
        sta     $D001
        tya
        cmp     #SCREEN_WIDTH
        bcc     L2CE0
        sbc     #SCREEN_WIDTH
L2CE0:  ldx     #$00
        cmp     #$1D
        bcc     L2CE7
        inx
L2CE7:  stx     MSIGX
        asl
        asl
        asl
        clc
        adc     #$18
        sta     SP0X
        rts

GET_KEY
	jsr     GET_KEY_RETRY
L2CF7:  jsr     GETIN
        tax
        inc     L2CAE
        bne     L2D12
        inc     L2CAF
        bne     L2D12
        lda     #$E0
        sta     L2CAF
        lda     $0340
        eor     #$FF
        sta     $0340
L2D12:  txa
        beq     L2CF7
L2D15:  cmp     #"A"
        bcc     L2D22
        cmp     #"["
        bcs     L2D22
        adc     #$20
        jmp     KEY_CLICK_SOUND

L2D22:  ldx     #$06
L2D24:  cmp     L2D5F,x
        beq     KEY_CLICK_SOUND
        dex
        bpl     L2D24
        and     #$7F
        cmp     #$20
        bcc     L2D48
        ldx     #$05
L2D34:  cmp     L2D66,x
        beq     L2D48
        dex
        bpl     L2D34
        cmp     #$7B
        bcs     L2D48
        cmp     #$61
        bcs     KEY_CLICK_SOUND
        cmp     #$5B
        bcc     KEY_CLICK_SOUND
L2D48:  jsr     ERROR_SOUND
        jmp     L2CF7

KEY_CLICK_SOUND:
	sta     Z_TEMP1
        adc     RANDOM
        sta     RANDOM
        eor     RASTER
        sta     RASTER
        lda     Z_TEMP1
        rts

L2D5F:	.byte	$0d, $14, $11, $1d, $91, $5e, $9d
L2D66:	.byte	$25, $26, $3d, $40, $3c, $3e

PUT_CHARACTER:
.(
	cmp     #$61
        bcc     L2D79
        cmp     #$7B
        bcs     L2D83
        and     #$5F
        jmp     CHROUT
L2D79:  cmp     #$41
        bcc     L2D83
        cmp     #$5B
        bcs     L2D83
        ora     #$20
L2D83:  jmp     CHROUT
.)


PRINT_CHAR_AT_COORDINATE
.(
	sta     Z_TEMP1
        txa
        pha
        tya
        pha
        sec
        jsr     PLOT
        tya
        cmp     #SCREEN_WIDTH
        bcc     L2D98
        sbc     #SCREEN_WIDTH
        tay
L2D98:  lda     Z_TEMP1
        cmp     #$0D
        bne     L2DA4
        cpx     #$17
        bcs     L2DAC
        bcc     L2DE1
L2DA4:  cpx     #$17
        bcc     L2DE1
        cpy     #$27
        bcc     L2DE1
L2DAC:  dex
        clc
        jsr     PLOT
        ldx     $52
L2DB3:  cpx     #24
        beq     L2DD7
        lda     VIC_ROW_ADDR_LO,x
        sta     $56
        lda     VIC_ROW_ADDR_HI,x
        sta     $57
        inx
        lda     VIC_ROW_ADDR_LO,x
        sta     $54
        lda     VIC_ROW_ADDR_HI,x
        sta     $55
        ldy     #$27
L2DCE:  lda     ($54),y
        sta     ($56),y
        dey
        bpl     L2DCE
        bmi     L2DB3
L2DD7:  ldx     #$27
        lda     #$20
L2DDB:  sta     $07C0,x
        dex
        bpl     L2DDB
L2DE1:  lda     Z_TEMP1
        cmp     #$22
        bne     L2DF1
        jsr     PUT_CHARACTER
        lda     #$00
        sta     $D4
        jmp     L2E06
L2DF1:  cmp     #$0D
        bne     L2E03
        sec
        jsr     PLOT
        inx
        ldy     #$00
        clc
        jsr     PLOT
        jmp     L2E06
L2E03:  jsr     PUT_CHARACTER
L2E06:  pla
        tay
        pla
        tax
        rts
.)

L2E0B:  jsr     L297B
        ldx     #$00
        stx     $4A
        stx     $4B
        stx     $4F
        stx     $C6
        inx
        stx     SPENA
        dec     $79
        dec     $79
        beq     L2E4A
        lda     Z_VECTOR0
        sta     Z_VECTOR2+1
        lda     #$00
        sta     Z_VECTOR3+1
        sta     Z_VECTOR3
        dec     $79
L2E2E:  beq     L2E38
        lda     $81
        sta     Z_VECTOR3
        lda     $82
        sta     Z_VECTOR3+1
L2E38:  jsr     GET_KEY_RETRY
        jsr     L2BB5
        bcc     L2E43		; why!?!
	lda	#$00		; this was a JMP L2ECD
	rts

L2E43:  ldy     #$00
        sty     L2ED0
        beq     L2E52
L2E4A:  ldy     #$00
        sty     L2ED0
L2E4F:  jsr     GET_KEY
L2E52:  cmp     #$91
        beq     L2E9C
        cmp     #$5E
        beq     L2E9C
        cmp     #$11
        beq     L2E9C
        cmp     #$9D
        beq     L2E9C
        cmp     #$1D
        beq     L2E9C
        cmp     #$0D
        beq     L2EA2
        cmp     #$14
        beq     L2E92
        ldy     L2ED0
        sta     INPUT_BUFFER,y
        inc     L2ED0
L2E77:  jsr     PRINT_CHAR_AT_COORDINATE
        ldy     L2ED0
        cpy     #$4D
        bcc     L2E4F
L2E81:  jsr     GET_KEY
        cmp     #$0D
        beq     L2EA2
        cmp     #$14
        beq     L2E92
        jsr     L3018
        jmp     L2E81

L2E92:  dec     L2ED0
        bpl     L2E77
        ldy     #$00
        sty     L2ED0
L2E9C:  jsr     L3018
        jmp     L2E4F

L2EA2:  ldy     L2ED0
        sta     INPUT_BUFFER,y
        iny
        sty     $26
        sty     $58
        ldx     #$00
        stx     SPENA
        jsr     PRINT_CHAR_AT_COORDINATE
L2EB5:  lda     $01FF,y
        cmp     #$41
        bcc     L2EC2
        cmp     #$5B
        bcs     L2EC2
        adc     #$20
L2EC2:  sta     ($46),y
        dey
        bne     L2EB5
        jsr     LOG_TO_PRINTER
        lda     $26
        rts

L2ED0:  .byte	0

PRINT_MESSAGE:  stx     L2ED9+1
        sta     L2ED9+2
        ldx     #$00
L2ED9:  lda	!$0000,x	; make damned sure this doesn't zero page!
        jsr     PRINT_CHAR_AT_COORDINATE
        inx
        dey
        bne     L2ED9
        rts

Z_SPLIT_WINDOW:
	lda     Z_HDR_MODE_BITS
        and     #$20 		; do we support sound?
        beq     L2F9E
        ldx     Z_OPERAND1
        beq     L2F9F		; if zero, unsplit window
        cpx     #24		; one big screen?
        bcs     L2F9E		; we don't support that, rts
        lda     $52
        sta     Z_VECTOR2	; we need to check for split_window 1
        stx     $52		; and return stuff back to normal
        stx     $53
        cpx     $4F
        bcc     L2F7B
L2F7B:  lda     #$17
        sec
        sbc     $52
        sta     Z_CURRENT_WINDOW_HEIGHT
	
L2F7Ba  sec
        jsr     PLOT
        cpx     Z_VECTOR2
        bcc     L2F96
        cpx     $52
        bcs     L2F9E
        ldx     #23
        ldy     #0
        clc
        jmp     PLOT

L2F96:  ldx     #$00
        ldy     #$00
        clc
        jmp     PLOT

L2F9E:  rts

L2F9F:  jsr     L2FC9
L2FA2:  ldx     #$00
        stx     $52
        stx     $53
        stx     $4F
        lda     #24
        sta     Z_CURRENT_WINDOW_HEIGHT
        rts

Z_SET_WINDOW:
	lda     Z_HDR_MODE_BITS
        and     #$01		; do we support color?
        beq     L2F9E
        lda     $53
        beq     L2F9E
        jsr     L2999
        lda     Z_OPERAND1
        bne     L2FD3
        lda     #$FF		; window 0 (main body)
        sta     $4E
        lda     #$00
        sta     Z_CURRENT_WINDOW
				; CK mod - switch to color white
	lda	#$05		; CK
	jsr	CHROUT		; CK
	lda	#$92		; CK
	jsr	CHROUT		; CK

L2FC9:  jsr     L2F7B
        ldx     $77
        ldy     $78
        jmp     L2FED

L2FD3:  cmp     #1		; this is window 1
        bne     L2F9E		; we handle only windows 0 and 1 :)
        sta     Z_CURRENT_WINDOW		; window 1 (status line)
				; CK mod - switch to color black
	lda	#$90
	jsr	CHROUT
	lda	#$12
	jsr	CHROUT
				; end CK mod
        lda     #$00
        sta     $4E
        sec
        jsr     PLOT
        stx     $77
        sty     $78
L2FE5:  ldx     #24
        stx     Z_CURRENT_WINDOW_HEIGHT
        ldx     #$00
        ldy     #$00
L2FED:  clc
        jsr     PLOT
        jmp     L3094

Z_SOUND_EFFECT
.(
	lda     Z_HDR_MODE_BITS
        and     #$20
        beq     L3006
        ldx    Z_OPERAND1
        dex
        bne     L3003
        jmp     L3018
L3003:  dex
        beq     ERROR_SOUND
L3006:  rts
.)

ERROR_SOUND
.(
	lda     #$60
        sta     FRELO1
        lda     #$16
        sta     FREHI1
        lda     #$F2
        sta     $A2
        jmp     L3026
.)

L3018:  lda     #$3C
        sta     FRELO1
        lda     #$32
        sta     FREHI1
        lda     #$FC
        sta     $A2
L3026:  lda     #$F0
        sta     SUREL1
        lda     #$8F
        sta     SIGVOL
	lda	#$41
	sta	VCREG1
L3035:  lda     $A2
        bne     L3035
        sta     VCREG1
        lda     #$80
        sta     SIGVOL
        rts

RNG_HW	inc     RANDOM
        dec     RASTER
        lda     RANDOM
        adc     $8E
        tax
        lda     RASTER
        sbc     $8F
        sta     $8E
        stx     $8F
        rts

CLEAR_SCREEN
	lda     #>VICSCN
        sta     Z_VECTOR2+1
        lda     #>COLRAM
        sta     Z_VECTOR3+1
        ldy     #<COLRAM
        sty     Z_VECTOR2
        sty     Z_VECTOR3		; $06 = $0400, $08 = $d800
	sty     SPENA
        ldx     #$04
L306B:  lda     #$20
        sta     (Z_VECTOR2),y		; all spaces in screen and ...
        lda     #$01
        sta     (Z_VECTOR3),y		; all character color is white.
        iny
        bne     L306B
        inc     Z_VECTOR2+1
        inc     Z_VECTOR3+1
        dex
        bne     L306B
        lda     #$0D
        sta     $07F8
        jsr     L2FE5
        jsr     L2FA2
        sei
        lda     #<IRQ_HANDLER		; install "rti" into interrupt handler
        sta     NMINV
        lda     #>IRQ_HANDLER
        sta     NMINV+1
        cli
L3094:  ldx     #24
L3096:  lda     VIC_ROW_ADDR_HI,x
        ora     #$80
        sta     $D9,x
        dex
        bpl     L3096
        rts

IRQ_HANDLER:  rti

DO_CARRIAGE_RETURN
.(
	jsr     Z_NEW_LINE
        ldx     #$00
        stx     $4E
        stx     $4F
        rts
.)

DEFAULT_SLOT_TEXT:	.aasc	" (Default is *):"

PRINT_DEFAULT_SLOT:  clc
        adc     #$31
        sta     DEFAULT_SLOT_TEXT+13
        ldx     #<DEFAULT_SLOT_TEXT
        lda     #>DEFAULT_SLOT_TEXT
        ldy     #$10
        jsr     PRINT_MESSAGE
        ldx     #$00
        stx     $C6
        inx
        stx     SPENA
        rts

SAVE_SLOT_TEXT:	.aasc	$0d, "Position 1-"
SAVE_SLOT:  .aasc	"*"

POS_CONFIRM_TEXT:
	.aasc	$0d, $0d, "Position *."
	.aasc	$0d, "Are you sure? (Y or N):"

#define	POS_TEXT_LENGTH	#$25
#define	CONFIRM_TEXT_LENGTH #$12

SET_POSITION:
.(
	ldx     #<SAVE_SLOT_TEXT
        lda     #>SAVE_SLOT_TEXT
        ldy     #$0D
        jsr     PRINT_MESSAGE
        lda     $5B
        jsr     PRINT_DEFAULT_SLOT
L33A3:  jsr     GET_KEY
        cmp     #$0D
        beq     L33B7
        sec
        sbc     #$31
        cmp     Z_MAX_SAVES
        bcc     L33B9
        jsr     ERROR_SOUND
        jmp     L33A3

L33B7:  lda     $5B
L33B9:  sta     $5D
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
        ldy     POS_TEXT_LENGTH
        jsr     PRINT_MESSAGE
        ldx     #$00
        stx     $C6
        inx
        stx     SPENA
L3410:  jsr     GET_KEY
        cmp     #$59
        beq     PRINT_YES
        cmp     #$79
        beq     PRINT_YES
        cmp     #$4E
        beq     PRINT_NO
        cmp     #$6E
        beq     PRINT_NO
        jsr     ERROR_SOUND
        jmp     L3410

PRINT_NO
	ldx     #<NO_TEXT
        lda     #>NO_TEXT
        ldy     #$03
        jsr     PRINT_MESSAGE
        jmp     SET_POSITION

PRINT_YES:  lda     #$00
        sta     SPENA
        ldx     #<YES_TEXT
        lda     #>YES_TEXT
        ldy     #$04
        jsr     PRINT_MESSAGE
        lda     #$00
        sta     STORY_INDEX
        sta     STORY_INDEX+1
        ldx     $5D
        beq     L3459
L344D:  clc
        adc     Z_STATIC_ADDR
        bcc     L3454
        inc     STORY_INDEX+1
L3454:  dex
        bne     L344D
        sta     STORY_INDEX
L3459:  lda     STORY_INDEX
L3475:
        rts
.)

PRESS_RETURN
.(
	ldx     #<PRESS_RETURN_TEXT
        lda     #>PRESS_RETURN_TEXT
        ldy     #$1E
        jsr     PRINT_MESSAGE
L1	jsr     GETIN
        cmp     #$00
        beq     L1
        and     #$7F
        cmp     #$0D
        beq     L2
        jsr     ERROR_SOUND
        jmp     L1
L2	rts
.)

PRESS_RETURN_TEXT: .aasc $0d, "Press [RETURN] to continue.", $0d, $0d

Z_SAVE
.(
	jsr	DO_CARRIAGE_RETURN
        ldx     #<SAVE_POSITION_TEXT
        lda     #>SAVE_POSITION_TEXT
        ldy     #$0E
        jsr     PRINT_MESSAGE
        jsr     SET_POSITION
	jmp	L2
L1
	jsr	CLOSE_SAVE_FILE
        jsr     REQUEST_STATUS_LINE_REDRAW
        jmp     RETURN_ZERO

L2	ldx     #<SAVING_POSITION_TEXT
        lda     #>SAVING_POSITION_TEXT
        ldy     #$17
        jsr     PRINT_MESSAGE
        lda     Z_HDR_MODE_BITS+1
        sta     $0F20
        lda     Z_HDR_MODE_BITS+2
        sta     $0F21
        lda     Z_STACK_POINTER
        sta     $0F22
        lda     Z_STACK_POINTER+1
        sta     $0F23
        lda     $66
        sta     $0F24
        lda     Z_SOMETHING_NOT_PC
        sta     $0F25
        ldx     #$02
L3	lda     Z_PC,x
        sta     $0F26,x
        dex
        bpl     L3
        lda     #>Z_LOCAL_VARIABLES		; so save from $0F00-$0FFF
        sta     PAGE_VECTOR+1

        jsr     UIEC_ONLY
        bcc     L3a
        clc
        jsr     CLOSE_STORY_FILE
        jsr     COMMAND_CLOSE

L3a
	jsr	SAVEFILE_OPEN_WRITE
	jsr     SEND_BUFFER_TO_DISK
        bcs     L1
        lda     #>Z_STACK_LO			; and $0900-$0EFF
        sta     PAGE_VECTOR+1
        lda     #$04
        sta     Z_VECTOR4
L4	jsr     SEND_BUFFER_TO_DISK
        bcs     L1
        dec     Z_VECTOR4
        bne     L4
        lda     Z_BASE_PAGE
        sta     PAGE_VECTOR+1
        ldx     Z_HDR_DYN_SIZE
        inx
        stx     Z_VECTOR2
L5	jsr     SEND_BUFFER_TO_DISK
        bcs     L1
        dec     Z_VECTOR2
        bne     L5
	jsr	CLOSE_SAVE_FILE

        jsr     UIEC_ONLY
        bcc     L6
        clc
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN

L6	jsr     REQUEST_STATUS_LINE_REDRAW
        lda     $5E
        sta     $5C
        lda     $5D
        sta     $5B
        lda     #$01
        ldx     #$00
        jmp     RETURN_VALUE
.)

Z_RESTORE:
.(
	jsr	DO_CARRIAGE_RETURN
        ldx     #<RESTORE_POSITION_TEXT
        lda     #>RESTORE_POSITION_TEXT
        ldy     #$11
        jsr     PRINT_MESSAGE
        jsr     SET_POSITION
        ldx     #<RESTORING_POSITION_TEXT
        lda     #>RESTORING_POSITION_TEXT
        ldy     #$1A
        jsr     PRINT_MESSAGE
        ldx     #$1F
L35B4:  lda     Z_LOCAL_VARIABLES,x
        sta     STACK,x
        dex
        bpl     L35B4
        lda     #>Z_LOCAL_VARIABLES	; read in $0F00
        sta     PAGE_VECTOR+1

        jsr     UIEC_ONLY
        bcc     L35B4a
        clc
        jsr     CLOSE_STORY_FILE
        jsr     COMMAND_CLOSE

L35B4a
	jsr	SAVEFILE_OPEN_READ
	bcs	L35D6
	ldx	#2
        jsr     READ_BUFFER_FROM_DISK
        bcs     L35E1
        lda     $0F20			; 32ea
        cmp     Z_HDR_MODE_BITS+1
        bne     L35D6
        lda     $0F21
        cmp     Z_HDR_MODE_BITS+2
        beq     L35EA
L35D6
	ldx     #$1F
L35D8:  lda     STACK,x
        sta     Z_LOCAL_VARIABLES,x
        dex
        bpl     L35D8
L35E1
	jsr	CLOSE_SAVE_FILE
        jsr     UIEC_ONLY
        bcc     L35E1a
        clc
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN
L35E1a
        jsr	REQUEST_STATUS_LINE_REDRAW
        jmp     RETURN_ZERO

L35EA:  lda     Z_HDR_FLAGS2		; 330e
        sta     Z_VECTOR2
        lda     Z_HDR_FLAGS2+1
        sta     Z_VECTOR2+1
        lda     #>Z_STACK_LO
        sta     PAGE_VECTOR+1
        lda     #$04
        sta     Z_VECTOR4
L35FC
	ldx	#2
	jsr     READ_BUFFER_FROM_DISK
        bcc     L3604
        jmp     FATAL_ERROR_0E

L3604:  dec     Z_VECTOR4		; 3328
        bne     L35FC
        lda	Z_BASE_PAGE		; reufix
        sta     PAGE_VECTOR+1
	ldx	#2
        jsr     READ_BUFFER_FROM_DISK
        bcc     L3614
        jmp     FATAL_ERROR_0E

L3614:  lda     Z_VECTOR2		; 3338
        sta     Z_HDR_FLAGS2
        lda     Z_VECTOR2+1
        sta     Z_HDR_FLAGS2+1
        lda     Z_HDR_DYN_SIZE
        sta     Z_VECTOR2
L3623
	ldx	#2
	jsr     READ_BUFFER_FROM_DISK
        bcc     L362B
        jmp     FATAL_ERROR_0E

L362B
	dec     Z_VECTOR2		; 3352
        bne     L3623
	jsr	CLOSE_SAVE_FILE

        jsr     UIEC_ONLY
        bcc     L362Ba
        clc
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN

L362Ba
        lda     $0F22
        sta     Z_STACK_POINTER
        lda     $0F23			; 335b
        sta     Z_STACK_POINTER+1
        lda     $0F24
        sta     $66
        lda     $0F25
        sta     Z_SOMETHING_NOT_PC
        ldx     #$02
L3645:  lda     $0F26,x
        sta     Z_PC,x
        dex
        bpl     L3645
        lda     #$18
        sta     Z_HDR_SCREEN_ROWS
        lda     #SCREEN_WIDTH
        sta     Z_HDR_SCREEN_COLS
        lda     #$0D
        jsr     CHROUT
        jsr     VIRT_TO_PHYS_ADDR_1
        jsr     REQUEST_STATUS_LINE_REDRAW
        lda     $5E
        sta     $5C
        lda     $5D
        sta     $5B
        lda     #$02
        ldx     #$00
        jmp     RETURN_VALUE
.)

;
; local status stuff
;

; local strings here

WHICH_GAME	.byte	00	; 0=N&B, 1=AMFV, 2=Trinity, 3=Bureaucracy
SPACE_TOGGLE	.byte	00
SPACE_SQUASH_OVERRIDE .byte 00
IGNORE_NEXT_PRINT	.byte 00	; to kill extra stuff in status line

MAX_RES_PAGE_CALC .byte 0

#include "common.s"
#include "sd2iec.s"
#include "ramexp.s"

; pad up to next page
.dsb    $100 - (* & $00FF), $FF

Z_HEADER = *
