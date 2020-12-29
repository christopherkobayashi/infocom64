; $Id$

; da65 V2.14 - Git N/A
; Created:    2014-11-21 16:09:11
; Input file: i-v5-original-2
; Page:       1

#include "c64.inc"

MAP_RAM =		%11111101	; note - v4 didn't map $D000 as RAM
MAP_ROM =		%00000010

REU_PRESENT =		$02

Z_VECTOR1 =		$04
Z_VECTOR2 =		$06
Z_VECTOR3 =		$08
Z_VECTOR4 =		$0c
Z_PC =			$0e
Z_BASE_PAGE =		$1a
Z_GLOBALS_ADDR =	$1d
STORY_INDEX =		$3a
PAGE_VECTOR =		$3c
Z_CURRENT_WINDOW =	$48
Z_TEMP1 =		$54
Z_STACK_POINTER =	$66
Z_OPERAND1 =		$79
Z_OPERAND2 =		$7b

INPUT_BUFFER            = $0200
Z_STACK_LO              = $0900
Z_STACK_HI              = $0b00
Z_LOCAL_VARIABLES       = $0f00

;Z_HEADER =              $4300
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
Z_HDR_SCREEN_WIDTH =	Z_HEADER + $22
Z_HDR_SCREEN_HEIGHT =	Z_HEADER + $24
Z_HDR_FONT_WIDTH =	Z_HEADER + $26
Z_HDR_FONT_HEIGHT =	Z_HEADER + $27
Z_HDR_ROUTINES =	Z_HEADER + $28
Z_HDR_STATIC =		Z_HEADER + $2a
Z_HDR_COLOR_BACK =	Z_HEADER + $2c
Z_HDR_COLOR_FRONT =	Z_HEADER + $2d
Z_HDR_TERMCHAR_ADDR =	Z_HEADER + $2e
Z_HDR_STANDARD_REV =	Z_HEADER + $32
Z_HDR_ALPHABET_ADDR =	Z_HEADER + $34
Z_HDR_EXTENSION_ADDR =	Z_HEADER + $36

SECTOR_BUFFER = $0800
SCREEN_WIDTH            = 40

.word	$1000
* = $1000

	jsr	PREP_SYSTEM

STARTUP:
	cld
        ldx     #$FF
        txs
        jsr     CLALL
;        jsr     CLEAR_SCREEN
        ldy     #$08
        ldx     #$0B
        clc
        jsr     PLOT
        ldx     #<STORY_LOADING_TEXT
        lda     #>STORY_LOADING_TEXT
        ldy     #$19
        jsr     PRINT_MESSAGE

        lda     REU_PRESENT
        and     #%00001111      ; we have to have at least a uIEC ...
        bne     L1142
        lda     #$89
        jmp     FATAL_ERROR

L1142:  lda     #$00
        ldx     #$03
L1146:  sta     $00,x
        inx
        cpx     #$8F
        bcc     L1146
        inc     Z_STACK_POINTER
        inc     $68
        inc     $6A
        inc     $63
        inc     Z_BASE_PAGE+1
        lda     #>Z_HEADER		; game data from $4300
        sta     Z_BASE_PAGE
        sta     PAGE_VECTOR+1
	clc
	adc	#$AF			; sick and wrong hardcoding
	sta	MAX_RES_PAGE_CALC

        lda     REU_PRESENT
        and     #%00000100
        beq     L1Ed1a
                                ; set EasyFlash bank to 1, prepping for load
        lda     #$80
        sta     EF_VEC1+2
        lda     EF_START_BANK
        sta     EF_BANK
L1Ed1a
        jsr     UIEC_ONLY
        bcc     L1Ed1b
        clc
        jsr     COMMAND_OPEN
L1Ed1b
	jsr	STORY_OPEN
LEd1b
	ldx	#5
        jsr     READ_BUFFER
        bcc     L1167
        jmp     FATAL_ERROR_0E

L1167:  lda     Z_HDR_CODE_VERSION	; v5?
        cmp     #$05
        beq     L1173
        lda     #$10
        jmp     FATAL_ERROR

; C64 Z5 games absolutely require the resident size to be set to $2BC0.

L1173
	lda	#$2b
	sta	Z_HDR_RESIDENT_SIZE
	lda	#$c0
	sta	Z_HDR_RESIDENT_SIZE+1

	lda     Z_HDR_RESIDENT_SIZE
        sta     $1C
        lda     Z_HDR_RESIDENT_SIZE+1
        sta     Z_BASE_PAGE+1
        lsr     $1C
        ror     Z_BASE_PAGE+1
        lsr     $1C
        ror     Z_BASE_PAGE+1
        lsr     $1C
        ror     Z_BASE_PAGE+1
        lsr     $1C
        ror     Z_BASE_PAGE+1
        lsr     $1C
        ror     Z_BASE_PAGE+1
L1191:  lsr     $1C
        ror     Z_BASE_PAGE+1
        jsr     GET_MAX_PAGE	; max out at 0xf200
        cmp     $1C
        beq     L11AA
        bcs     L11AA
        ldx     #$05
        ldy     #$00
        jsr     PLOT
        lda     #$00
        jmp     FATAL_ERROR

L11AA:  lda     #$30
        sta     Z_HDR_MODE_BITS
        lda     #8
        sta     Z_HDR_INTERP_NUMBER
        lda     #"J"
        sta     Z_HDR_INTERP_VERSION
        lda     #$00
        sta     Z_HDR_SCREEN_WIDTH
        sta     Z_HDR_SCREEN_HEIGHT
        lda     #SCREEN_WIDTH
        sta     Z_HDR_SCREEN_WIDTH+1
        lda     #24
        sta     Z_HDR_SCREEN_HEIGHT+1
        lda     #$01
        sta     Z_HDR_FONT_WIDTH
        sta     Z_HDR_FONT_HEIGHT
        lda     #$18
        sta     Z_HDR_SCREEN_ROWS
        lda     #$28
        sta     Z_HDR_SCREEN_COLS
        lda     #$02
        sta     Z_HDR_COLOR_BACK
        lda     #$09
        sta     Z_HDR_COLOR_FRONT
        lda     Z_HDR_GLOBALS
        clc
        adc     Z_BASE_PAGE
        sta     Z_GLOBALS_ADDR+1
        lda     Z_HDR_GLOBALS+1
        sta     Z_GLOBALS_ADDR
        lda     Z_HDR_ABBREV
        clc
        adc     Z_BASE_PAGE
        sta     $22
        lda     Z_HDR_ABBREV+1
        sta     $21
        lda     Z_HDR_OBJECTS
        clc
        adc     Z_BASE_PAGE
        sta     $24
        lda     Z_HDR_OBJECTS+1
        sta     $23
        lda     Z_HDR_TERMCHAR_ADDR
        ora     Z_HDR_TERMCHAR_ADDR+1
        beq     L1223
        lda     Z_HDR_TERMCHAR_ADDR
        clc
        adc     Z_BASE_PAGE
        sta     $26
        lda     Z_HDR_TERMCHAR_ADDR+1
        sta     $25

	; set up addresses for dynamic sized stuff

L1223:  lda     Z_HDR_DYN_SIZE		; bz a 54
        cmp     #$A0
        bcc     L122F
        lda     #$0D
        jmp     FATAL_ERROR

L122F:  adc     #$06			; bz a 5a
        sta     Z_STATIC_ADDR

        lda     #$09
	sta	Z_MAX_SAVES		; me
L1261:  clc
        adc     #$30
        sta     SAVE_SLOT
        ldy     #$01
        ldx     #$0E
        clc
        jsr     PLOT
        jmp     L129A

L129A:  ldx     #<PATIENT
        lda     #>PATIENT
        ldy     #$28
        jsr     PRINT_MESSAGE
        jsr     LOAD_RESIDENT
        lda     REU_PRESENT
        and     #%00000100
        bne     L129Aa
	jsr	UIEC_ONLY
	bcs	L129Aa
	jsr	CLOSE_STORY_FILE
L129Aa
	clc
        lda     $26
        ora     $25
        beq     L12BE
        ldy     #$FF
L12AE:  iny
        lda     ($25),y
        lda     ($25),y
        beq     L12BE
        cmp     #$FF
        bne     L12AE
        lda     #$01
        sta     L330D
L12BE:  lda     #$00
        sta     $10
        lda     Z_HDR_START_PC ; argh
        sta     Z_PC+1
        lda     Z_HDR_START_PC+1
        sta     Z_PC
        jsr     VIRT_TO_PHYS_ADDR_1
        lda     #$27
        sta     $70
        lda     INTERP_FLAGS
        cmp     #$01
        bne     MAIN_LOOP
        sta     $6B
        ora     Z_HDR_FLAGS2+1
        sta	Z_HDR_FLAGS2+1

MAIN_LOOP
	lda     #$00
        sta     $77
        jsr     FETCH_NEXT_ZBYTE
        sta     $03
        bmi     L12F3
        jmp     JUMP_TWO

L12F3:  cmp     #$B0
        bcs     L12FA
        jmp     JUMP_ONE

L12FA:  cmp     #$C0
        bcs     L1301
        jmp     JUMP_ZERO

L1301:  cmp     #$EC
        bne     L1308
        jmp     L1392

L1308:  cmp     #$FA
        bne     L130F
        jmp     L1392

L130F:  jsr     FETCH_NEXT_ZBYTE
        sta     $89
        ldx     #$00
        stx     $8B
        beq     L1320
L131A:  lda     $89
        asl
L131D:  asl
        sta     $89
L1320:  and     #$C0
        bne     L132A
        jsr     L14AD
        jmp     L133B

L132A:  cmp     #$40
        bne     L1334
        jsr     L14A9
        jmp     L133B

L1334:  cmp     #$80
        bne     L134F
        jsr     L14C1
L133B:  ldx     $8B
        lda     Z_VECTOR1
        sta     Z_OPERAND1,x
        lda     Z_VECTOR1+1
        sta     Z_OPERAND1+1,x
        inc     $77
        inx
        inx
        stx     $8B
        cpx     #$08
        bcc     L131A
L134F:  lda     $03
        cmp     #$E0
        bcs     L135C
        cmp     #$C0
        bcc     Z_EXTENDED_OPCODE
        jmp     L147F

L135C:  and     #$1F
	asl
        tay
        lda     JUMP_TABLE_VAR,y
        sta     L136B+1
        lda     JUMP_TABLE_VAR+1,y
        sta     L136B+2
L136B	jsr	$FFFF
        jmp     MAIN_LOOP

Z_EXTENDED_OPCODE:  cmp     #$0B
        bcs     L138D
	asl
        tay
        lda     JUMP_TABLE_EXT,y
        sta     L1382+1
        lda     JUMP_TABLE_EXT+1,y
        sta     L1382+2
L1382	jsr	$FFFF
        jmp     MAIN_LOOP

        lda     #$01
        jmp     FATAL_ERROR

L138D:  lda     #$11
        jmp     FATAL_ERROR

L1392:  jsr     FETCH_NEXT_ZBYTE
        sta     $89
        jsr     FETCH_NEXT_ZBYTE
        sta     $8A
        lda     $89
        ldx     #$00
        stx     $8B
        beq     L13AA
L13A4:  lda     $89
        asl
        asl
        sta     $89
L13AA:  and     #$C0
        bne     L13B4
        jsr     L14AD
        jmp     L13C8

L13B4:  cmp     #$40
        bne     L13BE
        jsr     L14A9
        jmp     L13C8

L13BE:  cmp     #$80
        beq     L13C5
        jmp     L134F

L13C5:  jsr     L14C1
L13C8:  ldx     $8B
        lda     Z_VECTOR1
        sta     Z_OPERAND1,x
        lda     Z_VECTOR1+1
        sta     Z_OPERAND1+1,x
        inc     $77
        inx
        inx
        stx     $8B
        cpx     #$10
        bne     L13DF
        jmp     L134F

L13DF:  cpx     #$08
        bne     L13A4
        lda     $8A
        sta     $89
        jmp     L13AA

JUMP_ZERO:  cmp     #$BE
        beq     L1408
        and     #$0F
	asl
        tay
        lda     JUMP_TABLE_ZERO,y
        sta     L13FD+1
        lda     JUMP_TABLE_ZERO+1,y
        sta     L13FD+2
L13FD	jsr	$FFFF
        jmp     MAIN_LOOP

        lda     #$02
        jmp     FATAL_ERROR

L1408:  jsr     FETCH_NEXT_ZBYTE
        sta     $03
L140D:  jmp     L1301

JUMP_ONE:  and     #$30
        bne     L141A
        jsr     FETCH_NEXT_ZBYTE
        jmp     L141E

L141A:  and     #$20
        bne     L142A
L141E:  sta     Z_OPERAND1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_OPERAND1
        inc     $77
        jmp     L1430

L142A:  jsr     L14C1
        jsr     L149E
L1430:  lda     $03
        and     #$0F
	asl
        tay
        lda     JUMP_TABLE_ONE,y
        sta     L1441+1
        lda     JUMP_TABLE_ONE+1,y
        sta     L1441+2
L1441	jsr	$FFFF
        jmp     MAIN_LOOP

        lda     #$03
        jmp     FATAL_ERROR

JUMP_TWO:  and     #$40
        bne     L145C
        sta     Z_OPERAND1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_OPERAND1
        inc     $77
        jmp     L1462

L145C:  jsr     L14C1
        jsr     L149E
L1462:  lda     $03
        and     #$20
        bne     L1472
        sta     Z_OPERAND2+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_OPERAND2
        jmp     L147D

L1472:  jsr     L14C1
        lda     Z_VECTOR1
        sta     Z_OPERAND2
        lda     Z_VECTOR1+1
        sta     Z_OPERAND2+1
L147D:  inc     $77
L147F:  lda     $03
        and     #$1F
	asl
        tay
        lda     JUMP_TABLE_TWO,y
        sta     L1490+1
        lda     JUMP_TABLE_TWO+1,y
        sta     L1490+2
L1490	jsr	$FFFF
        jmp     MAIN_LOOP

Z_ERROR_04
	lda     #$04
	jmp     FATAL_ERROR

L149E:  lda     Z_VECTOR1
        sta     Z_OPERAND1
        lda     Z_VECTOR1+1
        sta     Z_OPERAND1+1
        inc     $77
        rts

L14A9:  lda     #$00
        beq     L14B0
L14AD:  jsr     FETCH_NEXT_ZBYTE
L14B0:  sta     Z_VECTOR1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR1
        rts

L14B8:  tax
        bne     L14C6
        jsr     L14E4
        jmp     PUSH_VECTOR1_TO_STACK

L14C1:  jsr     FETCH_NEXT_ZBYTE
        beq     L14E4
L14C6:  cmp     #$10
        bcs     L14D7
        asl
        tax
        lda     $0EFE,x
        sta     Z_VECTOR1
        lda     $0EFF,x
        sta     Z_VECTOR1+1
        rts

L14D7:  jsr     CALCULATE_GLOBAL_WORD_ADDRESS
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR1+1
        iny
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR1
        rts

L14E4:  lda     Z_STACK_POINTER
        bne     L14EA
        sta     Z_STACK_POINTER+1
L14EA:  dec     Z_STACK_POINTER
        bne     L14F2
        ora     Z_STACK_POINTER+1
        beq     Z_ERROR_05
L14F2:  ldy     Z_STACK_POINTER
        lda     Z_STACK_POINTER+1
        beq     L1504
        lda     Z_STACK_LO+$100,y
        sta     Z_VECTOR1
        tax
        lda     Z_STACK_HI+$100,y
        sta     Z_VECTOR1+1
        rts
L1504:  lda     Z_STACK_LO,y
        sta     Z_VECTOR1
        tax
        lda     Z_STACK_HI,y
        sta     Z_VECTOR1+1
        rts

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
        beq     L152B
        txa
        sta     Z_STACK_LO+$100,y
        pla
        sta     Z_STACK_HI+$100,y
        jmp     L1533
L152B:  txa
        sta     Z_STACK_LO,y
        pla
        sta     Z_STACK_HI,y
L1533:  inc     Z_STACK_POINTER
        bne     L153F
        lda     Z_STACK_POINTER
        ora     Z_STACK_POINTER+1
        bne     Z_ERROR_06
        inc     Z_STACK_POINTER+1
L153F:  rts
.)

Z_ERROR_06:  lda     #$06
        jmp     FATAL_ERROR

SET_GLOBAL_OR_LOCAL_WORD:  tax
        bne     L1565
        lda     Z_STACK_POINTER
        bne     L154E
        sta     Z_STACK_POINTER+1
L154E:  dec     Z_STACK_POINTER
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
L1565:  cmp     #$10
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
.(
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
.)
L1598:  rts

L1599:  jsr     FETCH_NEXT_ZBYTE
        bpl     L15AA
L159E:  and     #$40
        bne     L1598
        jmp     FETCH_NEXT_ZBYTE

L15A5:  jsr     FETCH_NEXT_ZBYTE
        bpl     L159E
L15AA:  tax
        and     #$40
        beq     L15BA
        txa
        and     #$3F
        sta     Z_VECTOR1
        lda     #$00
        sta     Z_VECTOR1+1
        beq     L15D1
L15BA:  txa
        and     #$3F
        tax
        and     #$20
        beq     L15C6
        txa
        ora     #$E0
        tax
L15C6:  stx     Z_VECTOR1+1
        jsr     FETCH_NEXT_ZBYTE
        sta     Z_VECTOR1
        lda     Z_VECTOR1+1
        bne     L15DF
L15D1:  lda     Z_VECTOR1
        bne     L15D8
        jmp     Z_RFALSE

L15D8:  cmp     #$01
        bne     L15DF
        jmp     Z_RTRUE

L15DF:  lda     Z_VECTOR1
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
        bcc     L1600
        inc     Z_VECTOR2
        bne     L1600
        inc     Z_VECTOR2+1
L1600:  sta     Z_PC
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

L161B:  lda     Z_OPERAND1
        sta     Z_VECTOR1
        lda     Z_OPERAND1+1
        sta     Z_VECTOR1+1
        rts

REQUEST_STATUS_LINE_REDRAW:  lda     Z_HDR_FLAGS2+1
        ora     #$04
        sta     Z_HDR_FLAGS2+1
        rts

; Jump tables

JUMP_TABLE_ZERO
	.word	Z_RTRUE
	.word	Z_RFALSE
	.word	Z_PRINT_LITERAL
	.word	Z_PRINT_RET_LITERAL
	.word	Z_NOP
	.word	Z_ILLEGAL1
	.word	Z_ILLEGAL1
	.word	Z_RESTART
	.word	Z_RET_POPPED
	.word	Z_POP
	.word	Z_QUIT
	.word	Z_NEW_LINE
	.word	Z_ILLEGAL2
	.word	Z_VERIFY
	.word	Z_EXTENDED_OPCODE
	.word	Z_PIRACY

JUMP_TABLE_ONE
	.word	Z_JZ
	.word	Z_GET_SIBLING
	.word	Z_GET_CHILD
	.word	Z_GET_PARENT
	.word	Z_GET_PROP_LEN
	.word	Z_INC
	.word	Z_DEC
	.word	Z_PRINT_ADDR
	.word	Z_CALL
	.word	Z_REMOVE_OBJ
	.word	Z_PRINT_OBJ
	.word	Z_RET
	.word	Z_JUMP
	.word	Z_PRINT_PADDR
	.word	Z_LOAD
	.word	Z_CALL_LN

JUMP_TABLE_TWO
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
	.word	Z_CALL
	.word	Z_CALL_LN
	.word	Z_SET_COLOR
	.word	Z_THROW_VALUE
	.word	Z_ERROR_04
	.word	Z_ERROR_04
	.word	Z_ERROR_04

JUMP_TABLE_VAR
	.word	Z_CALL
	.word	Z_STOREW
	.word	Z_STOREB
	.word	Z_PUT_PROP
	.word	Z_AREAD
	.word	Z_PRINT_CHAR
	.word	Z_PRINT_NUM
	.word	Z_RANDOM
	.word	Z_PUSH
	.word	Z_PULL
	.word	Z_SPLIT_WINDOW
	.word	Z_SET_WINDOW
	.word	Z_CALL
	.word	Z_ERASE_WINDOW
	.word	Z_ERASE_LINE
	.word	Z_SET_CURSOR
	.word	Z_GET_CURSOR
	.word	Z_SET_TEXT_STYLE
	.word	Z_BUFFER_MODE
	.word	Z_OUTPUT_STREAM
	.word	Z_INPUT_STREAM
	.word	Z_SOUND_EFFECT
	.word	Z_READ_CHAR
	.word	Z_SCAN_TABLE
	.word	Z_NOT
	.word	Z_CALL_LN
	.word	Z_CALL_LN
	.word	Z_TOKENIZE
	.word	Z_ENCODE_TEXT
	.word	Z_COPY_TABLE
	.word	Z_PRINT_TABLE
	.word	Z_CHECK_ARG_COUNT

JUMP_TABLE_EXT
	.word	Z_SAVE
	.word	Z_RESTORE
	.word	Z_LOG_SHIFT
	.word	Z_ART_SHIFT
	.word	Z_SET_FONT
	.word	Z_DRAW_PICTURE
	.word	Z_PICTURE_DATA
	.word	Z_DRAW_PICTURE
	.word	Z_SET_MARGINS
	.word	Z_SAVE_RESTORE_UNDO
	.word	Z_SAVE_RESTORE_UNDO

FETCH_BYTE_FROM_VECTOR
        sei
        lda     R6510
        and     #MAP_RAM
        sta     R6510
        ldy     $14
        lda     ($17),y
        tax
        sei
        lda     R6510
        ora     #MAP_ROM
        sta     R6510
        cli
        txa
L172A:  inc     $14
        bne     L1731
        jsr     L1A14
L1731:  tay
        rts

FETCH_NEXT_ZBYTE
        sei
        lda     R6510
        and     #MAP_RAM
        sta     R6510
        ldy     Z_PC
        lda     ($11),y
        tax
        sei
        lda     R6510
        ora     #MAP_ROM
        sta     R6510
        cli
        txa
L1755:  inc     Z_PC
        bne     L175C
        jsr     L1A20
L175C:  tay
        rts

L175E:  lda     Z_VECTOR2
        sta     $14
        lda     Z_VECTOR2+1
        sta     $15
        lda     #$00
        sta     $16
        jmp     VIRT_TO_PHYS_ADDR

L176D:  .byte 0
L176E:  .byte 0
L176F:  .byte 0
L1770:  .byte 0
L1771:  .byte 0
L1772:  .byte 0
L1773:  .byte 0
L1774:  .byte 0
L1775:  .byte 0
L1776:  .byte 0

VIRT_TO_PHYS_ADDR
.(
	lda     $16
        bne     L1786
        lda     $15
        cmp     Z_BASE_PAGE+1
        bcs     L1786

        adc     #>Z_HEADER
        sta     $18
L1785:  rts

L1786
	lda     $16
        ldy     $15
        jsr     CALC_NONRESIDENT_PHYS_ADDR
        clc
        adc     MAX_RES_PAGE_CALC
        sta     $18
        lda     L17BA
        beq     L1785
.)

VIRT_TO_PHYS_ADDR_1
.(
	lda     $10
        bne     L17A6
        lda     Z_PC+1
        cmp     Z_BASE_PAGE+1
        bcs     L17A6
        adc     #>Z_HEADER
        sta     $12
L17A5:  rts

L17A6:  lda     $10
        ldy     Z_PC+1
        jsr     CALC_NONRESIDENT_PHYS_ADDR
        clc
        adc     MAX_RES_PAGE_CALC
        sta     $12
        lda     L17BA
        beq     L17A5
        jmp     VIRT_TO_PHYS_ADDR
.)

L17BA:  .byte 0

CALC_NONRESIDENT_PHYS_ADDR
.(	
	sta     L176E
        sty     L176D
        ldx     #$00
        stx     L17BA
        jsr     L18A9
        bcc     L17EF
        ldx     L176F
        lda     $0D00,x
        sta     L176F
        tax
        lda     L176E
        sta     $0E00,x
        lda     L176D
        sta     $0E80,x
        tay
        txa
        pha
        lda     L176E
        jsr     REU_FETCH
        dec     L17BA
        pla
        rts
L17EF:  sta     L1770
        cmp     L176F
        bne     L17F8
        rts
L17F8:  ldy     L176F	; 16dc
        lda     $0D00,y
        sta     L1773
        lda     L1770
        jsr     L188B
        ldy     L176F
        lda     L1770
        jsr     L1865
        lda     L1770
        sta     L176F
.)
L1816:  rts

REU_FETCH
.(
	sta     STORY_INDEX+1
        sty     STORY_INDEX
        txa
        clc
        adc     MAX_RES_PAGE_CALC
        sta     PAGE_VECTOR+1

        jsr     UIEC_ONLY
        bcc     L1
        clc
        ldx     STORY_INDEX+1
        lda     STORY_INDEX
        jsr     IEC_FETCH
        jmp     L2

L1
	lda     STORY_INDEX
        sec
        sbc     Z_BASE_PAGE+1
        tay				; pha
        lda     STORY_INDEX+1
        sbc     $1C
        tax

	jsr	IREU_FETCH
L2
	jsr	SECBUF_TO_PVEC
	rts
.)

L1865:  sta     L1775
        sty     L1774
        tax
        tya
        sta     $0D80,x
        lda     $0D00,y
        sta     L1776
        txa
        ldx     L1776
        sta     $0D80,x
        txa
        ldx     L1775
        sta     $0D00,x
        lda     L1775
        sta     $0D00,y
        rts

L188B:  tax
        lda     $0D00,x
        sta     L1771
        lda     $0D80,x
        sta     L1772
        tax
        lda     L1771
        sta     $0D00,x
        lda     L1772
        ldx     L1771
        sta     $0D80,x
        rts

L18A9:  ldx     #$0D
L18AB:  lda     L176E
        cmp     $0E00,x
        beq     L18B8
L18B3:  dex
        bpl     L18AB
        sec
        rts

L18B8:  tya
        cmp     $0E80,x
        bne     L18B3
        txa
        clc
        rts

LOAD_RESIDENT:  ldx     #$0D
        stx     L176F
        lda     #$FF
L18C8:  sta     $0E00,x
        dex
        bpl     L18C8
        ldx     #$00
        ldy     #$01
L18D2:  tya
        sta     $0D80,x
        inx
        iny
        cpx     #$0E
        bcc     L18D2
        lda     #$00
        dex
        sta     $0D80,x
        ldx     #$00
        ldy     #$FF
        lda     #$0D
L18E8:  sta     $0D00,x
        inx
        iny
        tya
        cpx     #$0E
        bcc     L18E8
        lda     Z_HDR_FILE_LENGTH+1
        sta     Z_VECTOR3
        lda     Z_HDR_FILE_LENGTH
        ldy     #$05
L18FC:  lsr
        ror     Z_VECTOR3
        dey
        bpl     L18FC
        sta     Z_VECTOR3+1
        jsr     L349E
        ldy     #$03
        clc
        jsr     PLOT
        ldy     #$23
        lda     #"*"
L1911:  jsr     CHROUT
        dey
        bne     L1911
        lda     #$05
        sta     L32EC
L191C:  jsr     DEC_PAGE_COUNT
        bcc     L1956
        dec     L32EC
        bne     L1930
        lda     #$14
        jsr     CHROUT
        lda     #$05
        sta     L32EC
L1930
	ldx	#5
	jsr     READ_BUFFER
        bcc     LOAD_NONRESIDENT
        jmp     FATAL_ERROR_0E
L1956:  rts				; relocated from up there

LOAD_NONRESIDENT
	lda     PAGE_VECTOR+1
        cmp     MAX_RES_PAGE_CALC
        bne     L191C

        lda     REU_PRESENT
        and     #%00000100
        beq     LQ0a

                        ; at this point, EF_VEC1+2 has non-res base page and
                        ; EF_BANK has non-res base bank ...
        lda     EF_VEC1+2
        sta     EF_NONRES_PAGE_BASE
        lda     EF_BANK
        sta     EF_NONRES_BANK_BASE
	rts
LQ0a
        jsr     UIEC_ONLY
        bcc     LQ0aa
        clc
        rts

LQ0aa
        ldy     #$01
        ldx     #$0F
        clc
        jsr     PLOT
        ldx     #<REU_TXT
        lda     #>REU_TXT
	ldy     #$28
        jsr     PRINT_MESSAGE

	lda     #$00
        sta     Z_VECTOR2+1
        sta     Z_VECTOR2
        sta     Z_VECTOR4
L1968:  jsr     DEC_PAGE_COUNT
        bcc     L197E
;	jsr	DO_TWIRLY
        lda     #>SECTOR_BUFFER
        sta     PAGE_VECTOR+1
	ldx	#5
        jsr     READ_BUFFER
        bcc     REU_STASH
        jmp     FATAL_ERROR_0E
L197E
	rts

REU_STASH
.(
	jsr	IREU_STASH
	inc     Z_VECTOR2+1
        bne     L1
        inc     Z_VECTOR4
L1	jmp     L1968
.)

DEC_PAGE_COUNT:  lda     Z_VECTOR3
        sec
        sbc     #$01
        sta     Z_VECTOR3
        lda     Z_VECTOR3+1
        sbc     #$00
        sta     Z_VECTOR3+1
        rts

L1A14:  pha
        inc     $15
        bne     L1A1B
        inc     $16
L1A1B:  jsr     VIRT_TO_PHYS_ADDR
        pla
        rts

L1A20:  pha
        inc     Z_PC+1
        bne     L1A27
        inc     $10
L1A27:  jsr     VIRT_TO_PHYS_ADDR_1
        pla
        rts

L1A2C:  lda     Z_VECTOR2
        asl
        sta     $14
        lda     Z_VECTOR2+1
        rol
        sta     $15
        lda     #$00
        rol
        sta     $16
L1A3B:  asl     $14
        rol     $15
        rol     $16
        jmp     VIRT_TO_PHYS_ADDR

L1A44:  rts

L1A45:  ldx     #$00
        stx     $30
        stx     $34
        dex
        stx     $31
L1A4E:  jsr     L1B2B
        bcs     L1A44
        sta     $32
        tax
        beq     L1A99
        cmp     #$04
        bcc     L1AB7
        cmp     #$06
        bcc     L1A9D
        jsr     L1B0D
        tax
        bne     L1A71
        lda     #$5B
L1A68:  clc
        adc     $32
L1A6B:  jsr     L2C49
        jmp     L1A4E

L1A71:  cmp     #$01
        bne     L1A79
        lda     #$3B
        bne     L1A68
L1A79:  lda     $32
        sec
        sbc     #$06
        beq     L1A87
        tax
        lda     VALID_PUNCTUATION,x
        jmp     L1A6B

L1A87:  jsr     L1B2B
        asl
        asl
        asl
        asl
        asl
        sta     $32
        jsr     L1B2B
        ora     $32
        jmp     L1A6B

L1A99:  lda     #$20
        bne     L1A6B
L1A9D:  sec
        sbc     #$03
        tay
        jsr     L1B0D
        bne     L1AAB
        sty     $31
        jmp     L1A4E

L1AAB:  sty     $30
        cmp     $30
        beq     L1A4E
        lda     #$00
        sta     $30
        beq     L1A4E
L1AB7:  sec
        sbc     #$01
        asl
        asl
        asl
        asl
        asl
        asl
        sta     $33
        jsr     L1B2B
        asl
        clc
        adc     $33
        tay
        lda     ($21),y
        sta     Z_VECTOR2+1
        iny
        lda     ($21),y
        sta     Z_VECTOR2
        lda     $16
        pha
        lda     $15
        pha
        lda     $14
        pha
        lda     $30
        pha
        lda     $34
        pha
        lda     $36
        pha
        lda     $35
        pha
        jsr     L1B19
        jsr     L1A45
        pla
        sta     $35
        pla
        sta     $36
        pla
        sta     $34
        pla
        sta     $30
        pla
        sta     $14
        pla
        sta     $15
        pla
        sta     $16
        ldx     #$FF
        stx     $31
        jsr     VIRT_TO_PHYS_ADDR
        jmp     L1A4E

L1B0D:  lda     $31
        bpl     L1B14
        lda     $30
        rts

L1B14:  ldy     #$FF
        sty     $31
        rts

L1B19:  lda     Z_VECTOR2
        asl
        sta     $14
        lda     Z_VECTOR2+1
        rol
        sta     $15
        lda     #$00
        rol
        sta     $16
        jmp     VIRT_TO_PHYS_ADDR

L1B2B:  lda     $34
        bpl     L1B31
        sec
        rts

L1B31:  bne     L1B46
        inc     $34
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $36
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $35
        lda     $36
        lsr
        lsr
        jmp     L1B6F

L1B46:  sec
        sbc     #$01
        bne     L1B61
        lda     #$02
        sta     $34
        lda     $35
        sta     Z_VECTOR2
        lda     $36
        asl     Z_VECTOR2
        rol
        asl     Z_VECTOR2
        rol
        asl     Z_VECTOR2
        rol
        jmp     L1B6F

L1B61:  lda     #$00
        sta     $34
        lda     $36
        bpl     L1B6D
        lda     #$FF
        sta     $34
L1B6D:  lda     $35
L1B6F:  and     #$1F
        clc
        rts

L1B73:  lda     #$05
        ldx     #$08
L1B77:  sta     L32DF,x
        dex
        bpl     L1B77
        lda     #$09
        sta     $37
        lda     #$00
        sta     $38
        sta     $39
L1B87:  ldx     $38
        inc     $38
        lda     L32D6,x
        sta     $32
        bne     L1B96
        lda     #$05
        bne     L1BC3
L1B96:  lda     $32
        jsr     L1C10
        beq     L1BBE
        clc
        adc     #$03
        ldx     $39
        sta     L32DF,x
        inc     $39
        dec     $37
        bne     L1BAE
        jmp     L1C29

L1BAE:  lda     $32
        jsr     L1C10
        cmp     #$02
        beq     L1BD1
        lda     $32
        sec
        sbc     #$3B
        bpl     L1BC3
L1BBE:  lda     $32
        sec
        sbc     #$5B
L1BC3:  ldx     $39
        sta     L32DF,x
        inc     $39
        dec     $37
        bne     L1B87
        jmp     L1C29

L1BD1:  lda     $32
        jsr     L1C00
        bne     L1BC3
        lda     #$06
        ldx     $39
        sta     L32DF,x
        inc     $39
        dec     $37
        beq     L1C29
        lda     $32
        lsr
        lsr
        lsr
        lsr
        lsr
        and     #$03
        ldx     $39
        sta     L32DF,x
        inc     $39
        dec     $37
        beq     L1C29
        lda     $32
        and     #$1F
        jmp     L1BC3

L1C00:  ldx     #$19
L1C02:  cmp     VALID_PUNCTUATION,x
        beq     L1C0B
        dex
        bne     L1C02
        rts

L1C0B:  txa
        clc
        adc     #$06
        rts

L1C10:  cmp     #$61
        bcc     L1C1B
        cmp     #$7B
        bcs     L1C1B
        lda     #$00
        rts

L1C1B:  cmp     #$41
        bcc     L1C26
        cmp     #$5B
        bcs     L1C26
        lda     #$01
        rts

L1C26:  lda     #$02
        rts

L1C29:  lda     L32E0
        asl
        asl
        asl
        asl
        rol     L32DF
        asl
        rol     L32DF
        ora     L32E1
        sta     L32E0
        lda     L32E3
        asl
        asl
        asl
        asl
        rol     L32E2
        asl
        rol     L32E2
        ora     L32E4
        tax
        lda     L32E2
        sta     L32E1
        stx     L32E2
        lda     L32E6
        asl
        asl
        asl
        asl
        rol     L32E5
        asl
        rol     L32E5
        ora     L32E7
        sta     L32E4
        lda     L32E5
        ora     #$80
        sta     L32E3
        rts

L1C8F:  stx     Z_VECTOR2+1
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
        bcc     L1CB7
        inc     Z_VECTOR2+1
L1CB7:  clc
        adc     $23
        sta     Z_VECTOR2
        lda     Z_VECTOR2+1
        adc     $24
        sta     Z_VECTOR2+1
        rts

L1CC3:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
        ldy     #$0C
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

L1CE1:  lda     (Z_VECTOR2),y
        and     #$3F
        rts

L1CE6:  lda     (Z_VECTOR2),y
        and     #$80
        beq     L1CF2
        iny
        lda     (Z_VECTOR2),y
        and     #$3F
        rts

L1CF2:  lda     (Z_VECTOR2),y
        and     #$40
        beq     L1CFB
        lda     #$02
        rts

L1CFB:  lda     #$01
        rts

L1CFE:  jsr     L1CE6
        tax
L1D02:  iny
        bne     L1D0B
        inc     Z_VECTOR2
        bne     L1D0B
        inc     Z_VECTOR2+1
L1D0B:  dex
        bne     L1D02
        iny
        rts

L1D10:  jsr     L1CFE
        tya
        clc
        adc     Z_VECTOR2
        sta     Z_VECTOR2
        bcc     L1D1D
        inc     Z_VECTOR2+1
L1D1D:  ldy     #$00
        rts

L1D20:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
        lda     Z_OPERAND2
        cmp     #$10
L1D2B:  bcc     L1D51
        sbc     #$10
        tax
        cmp     #$10
        bcc     L1D45
        sbc     #$10
        tax
        lda     Z_VECTOR2
        clc
        adc     #$04
        sta     Z_VECTOR2
        bcc     L1D50
        inc     Z_VECTOR2+1
        jmp     L1D50

L1D45:  lda     Z_VECTOR2
        clc
        adc     #$02
        sta     Z_VECTOR2
        bcc     L1D50
        inc     Z_VECTOR2+1
L1D50:  txa
L1D51:  sta     $0A
        ldx     #$01
        stx     Z_VECTOR3
        dex
        stx     Z_VECTOR3+1
        lda     #$0F
        sec
        sbc     $0A
        tax
        beq     L1D69
L1D62:  asl     Z_VECTOR3
        rol     Z_VECTOR3+1
        dex
        bne     L1D62
L1D69:  ldy     #$00
        lda     (Z_VECTOR2),y
        sta     $0B
        iny
        lda     (Z_VECTOR2),y
        sta     $0A
        rts

Z_RTRUE:  ldx     #$01
L1D77:  lda     #$00
L1D79:  stx     Z_OPERAND1
        sta     Z_OPERAND1+1
        jmp     Z_RET

Z_RFALSE:  ldx     #$00
        beq     L1D77
Z_PRINT_LITERAL:  ldx     #$05
L1D86:  lda     Z_PC,x
        sta     $14,x
        dex
        bpl     L1D86
        jsr     L1A45
        ldx     #$05
L1D92:  lda     $14,x
        sta     Z_PC,x
        dex
        bpl     L1D92
        rts

Z_PRINT_RET_LITERAL   jsr     Z_PRINT_LITERAL
        jsr     L2D1A
        jmp     Z_RTRUE

Z_RET_POPPED   jsr     L14E4
        jmp     L1D79

VERSION_TEXT:
        .aasc   "C64 Version 8J (", CUR_DATE, "-01)", $0d
        .aasc   "uIEC fixes by Chris Kobayashi", $0d
        .aasc   "For Saya, Ao, Karie, and the KobaCats", $0d
        .aasc   $0d
VERSION_LENGTH = 30 + 29 + 38 + 1

Z_VERIFY
        jsr     Z_NEW_LINE
        ldx     #<VERSION_TEXT
        lda     #>VERSION_TEXT
        ldy     #VERSION_LENGTH
        jsr     PRINT_MESSAGE
	jsr     L2D1A
        ldx     #$03
        lda     #$00
L1DB0:  sta     $0A,x
        sta     $14,x
        dex
        bpl     L1DB0
        lda     #$40
        sta     $14
        lda     Z_HDR_FILE_LENGTH
        sta     Z_VECTOR2+1
        lda     Z_HDR_FILE_LENGTH+1
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
        lda     REU_PRESENT
        and     #%00000100
        beq     LQQ1a

        lda     EF_START_BANK
        sta     EF_BANK
        lda     #$80
        sta     EF_VEC1+2
	jmp	LQQ1b
LQQ1a
        jsr     UIEC_ONLY
        bcc     LQQ1a1
        clc
        lda     #0
        tax
        tay
        jsr     UIEC_SEEK
        jmp     LQQ1b
LQQ1a1
	jsr	STORY_OPEN
LQQ1b
        jmp     L1DDC

L1DD8:  lda     $14
        bne     L1DE8
L1DDC:  lda     #$08
        sta     PAGE_VECTOR+1
	ldx	#5
        jsr     READ_BUFFER
        bcc     L1DE8
        jmp     FATAL_ERROR_0E

L1DE8:  ldy     $14
        lda     SECTOR_BUFFER,y
        inc     $14
        bne     L1DF7
        inc     $15
        bne     L1DF7
        inc     $16
L1DF7:  clc
        adc     Z_VECTOR4
        sta     Z_VECTOR4
        bcc     L1E00
        inc     Z_VECTOR4+1
L1E00:  lda     $14
        cmp     Z_VECTOR2
        bne     L1DD8
        lda     $15
        cmp     Z_VECTOR2+1
        bne     L1DD8
        lda     $16
        cmp     $0A
        bne     L1DD8

        lda     REU_PRESENT
        and     #%00000100
        bne     L1E00a
	jsr	CLOSE_STORY_FILE
        jsr     UIEC_ONLY
        bcc     L1E00a
        clc
        jsr     COMMAND_CLOSE
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN
L1E00a
        lda     Z_HDR_CHKSUM+1
        cmp     Z_VECTOR4
        bne     L1E23
        lda     Z_HDR_CHKSUM
        cmp     Z_VECTOR4+1
L1E1E:  bne     L1E23
        jmp     L15A5

L1E23:  jmp     L1599

Z_POP   ldx     $69
        lda     $68
        jmp     RETURN_VALUE

Z_PIRACY   jmp     L15A5

Z_JZ   lda     Z_OPERAND1
        ora     Z_OPERAND1+1
        beq     L1E5E
L1E36:  jmp     L1599

Z_GET_SIBLING   lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
        ldy     #$08
        bne     L1E4D

Z_GET_CHILD   lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
        ldy     #$0A
L1E4D:  lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        jsr     RETURN_VALUE
        lda     Z_VECTOR1
        bne     L1E5E
        lda     Z_VECTOR1+1
        beq     L1E36
L1E5E:  jmp     L15A5

Z_GET_PARENT   lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
        ldy     #$06
        lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        jmp     RETURN_VALUE

Z_GET_PROP_LEN   lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_VECTOR2+1
        lda     Z_OPERAND1
        sec
        sbc     #$01
        sta     Z_VECTOR2
        bcs     L1E85
        dec     Z_VECTOR2+1
L1E85:  ldy     #$00
        lda     (Z_VECTOR2),y
        bmi     L1E97
        and     #$40
        beq     L1E93
        lda     #$02
        bne     L1E99
L1E93:  lda     #$01
        bne     L1E99
L1E97:  and     #$3F
L1E99:  ldx     #$00
        jmp     RETURN_VALUE

Z_INC:  lda     Z_OPERAND1
        jsr     L14B8
        inc     Z_VECTOR1
        bne     L1EA9
        inc     Z_VECTOR1+1
L1EA9:  jmp     L1EBE

Z_DEC:  lda     Z_OPERAND1
        jsr     L14B8
        lda     Z_VECTOR1
        sec
        sbc     #$01
        sta     Z_VECTOR1
        lda     Z_VECTOR1+1
        sbc     #$00
        sta     Z_VECTOR1+1
L1EBE:  lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

Z_PRINT_ADDR   lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jsr     L175E
        jmp     L1A45

Z_REMOVE_OBJ:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
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
        beq     L1F43
        lda     $0A
        jsr     L1C8F
        ldy     #$0A
        lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND1
        bne     L1F16
        cpx     Z_OPERAND1+1
        bne     L1F16
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
        bne     L1F34
L1F16:  jsr     L1C8F
        ldy     #$08
        lda     (Z_VECTOR2),y
        tax
        iny
L1F1F:  lda     (Z_VECTOR2),y
        cmp     Z_OPERAND1
        bne     L1F16
        cpx     Z_OPERAND1+1
        bne     L1F16
        ldy     #$08
        lda     (Z_VECTOR3),y
        sta     (Z_VECTOR2),y
        iny
        lda     (Z_VECTOR3),y
        sta     (Z_VECTOR2),y
L1F34:  lda     #$00
        ldy     #$06
        sta     (Z_VECTOR3),y
        iny
        sta     (Z_VECTOR3),y
        iny
        sta     (Z_VECTOR3),y
        iny
        sta     (Z_VECTOR3),y
L1F43:  rts

Z_PRINT_OBJ   lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
        ldy     #$0C
        lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
        sta     Z_VECTOR2
        stx     Z_VECTOR2+1
        inc     Z_VECTOR2
        bne     L1F5D
        inc     Z_VECTOR2+1
L1F5D:  jsr     L175E
        jmp     L1A45

Z_RET:  lda     $68
        sta     Z_STACK_POINTER
        lda     $69
        sta     Z_STACK_POINTER+1
        jsr     L14E4
        stx     Z_VECTOR2+1
        jsr     L14E4
        sta     L3303
        ldx     Z_VECTOR2+1
        txa
        beq     L1F94
        dex
        txa
        asl
        sta     Z_VECTOR2
L1F80:  jsr     L14E4
        ldy     Z_VECTOR2
        sta     Z_LOCAL_VARIABLES+1,y
        txa
        sta     Z_LOCAL_VARIABLES,y
        dec     Z_VECTOR2
        dec     Z_VECTOR2
        dec     Z_VECTOR2+1
        bne     L1F80
L1F94:  jsr     L14E4
        stx     Z_PC+1
        sta     $10
        jsr     L14E4
        stx     L32F9
        sta     Z_PC
        jsr     L14E4
        stx     $68
        sta     $69
        lda     Z_PC
        bne     L1FBC
        lda     Z_PC+1
        bne     L1FBC
        lda     $10
        bne     L1FBC
        jsr     L161B
        jmp     L32BE

L1FBC:  jsr     VIRT_TO_PHYS_ADDR_1
        lda     L32F9
        beq     L1FC5
        rts

L1FC5:  jsr     L161B
        jmp     RETURN_NULL

Z_JUMP   jsr     L161B
        jmp     L15DF

Z_PRINT_PADDR   lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jsr     L1A2C
        jmp     L1A45

Z_LOAD   lda     Z_OPERAND1
        jsr     L14B8
        jmp     RETURN_NULL

RETURN_VECTOR1:  stx     Z_VECTOR1
        sta     Z_VECTOR1+1
        jmp     RETURN_NULL

Z_JL   jsr     L161B
        jmp     L1FF7

Z_DEC_CHK   jsr     Z_DEC
L1FF7:  lda     Z_OPERAND2
        sta     Z_VECTOR2
        lda     Z_OPERAND2+1
        sta     Z_VECTOR2+1
        jmp     L2020

Z_JG   lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        sta     Z_VECTOR2+1
        jmp     L2018

Z_INC_CHK   jsr     Z_INC
        lda     Z_VECTOR1
        sta     Z_VECTOR2
        lda     Z_VECTOR1+1
        sta     Z_VECTOR2+1
L2018:  lda     Z_OPERAND2
        sta     Z_VECTOR1
        lda     Z_OPERAND2+1
        sta	Z_VECTOR1+1
L2020:  lda     Z_VECTOR2+1
        eor     Z_VECTOR1+1
        bpl     L202F
        lda     Z_VECTOR2+1
	cmp	Z_VECTOR1+1
	bcc	L2067
        jmp     L1599

L202F:  lda     Z_VECTOR1+1
        cmp     Z_VECTOR2+1
        bne     L2039
        lda     Z_VECTOR1
        cmp     Z_VECTOR2
L2039:  bcc     L2067
        jmp     L1599

Z_JIN   lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
        ldy     #$06
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND2+1
        bne	L2054
        iny
        lda     (Z_VECTOR2),y
        cmp     Z_OPERAND2
        beq     L2067
L2054:  jmp     L1599

Z_TEST   lda     Z_OPERAND2
        and     Z_OPERAND1
        cmp     Z_OPERAND2
L205D:  bne     L2054
        lda     Z_OPERAND2+1
L2061:  and     Z_OPERAND1+1
        cmp     Z_OPERAND2+1
        bne     L2054
L2067:  jmp     L15A5

Z_OR   lda     Z_OPERAND1
L206C:  ora     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        ora     Z_OPERAND2+1
        jmp	RETURN_VECTOR1

Z_AND   lda     Z_OPERAND1
        and     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        and     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

Z_TEST_ATTR   jsr     L1D20
        lda     $0B
        and     Z_VECTOR3+1
        sta     $0B
        lda     $0A
        and     Z_VECTOR3
        ora     $0B
        bne     L2067
        jmp     L1599

Z_SET_ATTR   jsr     L1D20
        ldy     #$00
        lda     $0B
        ora     Z_VECTOR3+1
        sta     (Z_VECTOR2),y
        iny
        lda     $0A
        ora     Z_VECTOR3
        sta     (Z_VECTOR2),y
        rts

Z_CLEAR_ATTR   jsr     L1D20
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

Z_STORE   lda     Z_OPERAND2
        sta     Z_VECTOR1
        lda     Z_OPERAND2+1
        sta     Z_VECTOR1+1
        lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

Z_INSERT_OBJ   jsr     Z_REMOVE_OBJ
        lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
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
        jsr     L1C8F
        ldy     #$0A
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
        ora     $0B
        beq     L210F
        txa
        ldy     #$09
        sta     (Z_VECTOR3),y
        dey
        lda     $0B
        sta     (Z_VECTOR3),y
L210F:  rts

Z_LOADW   jsr     L2127
        jsr     FETCH_BYTE_FROM_VECTOR
L2116:  sta     Z_VECTOR1+1
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     Z_VECTOR1
        jmp     RETURN_NULL

Z_LOADB   jsr     L212B
        lda     #$00
        beq     L2116
L2127:  asl     Z_OPERAND2
        rol     Z_OPERAND2+1
L212B:  lda     Z_OPERAND2
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

Z_GET_PROP   jsr     L1CC3
L2144:  jsr     L1CE1
        cmp     Z_OPERAND2
        beq     L2166
        bcc     L2153
        jsr     L1D10
        jmp     L2144

L2153:  lda     Z_OPERAND2
        sec
        sbc     #$01
        asl
        tay
        lda     ($23),y
        sta     Z_VECTOR1+1
        iny
        lda     ($23),y
        sta     Z_VECTOR1
        jmp     RETURN_NULL

L2166:  jsr     L1CE6
        iny
        cmp     #$01
        beq     L2177
        cmp     #$02
        beq     L217D
        lda     #$07
        jmp     FATAL_ERROR

L2177:  lda     (Z_VECTOR2),y
        ldx     #$00
        beq     L2183
L217D:  lda     (Z_VECTOR2),y
        tax
        iny
        lda     (Z_VECTOR2),y
L2183:  sta     Z_VECTOR1
        stx     Z_VECTOR1+1
        jmp     RETURN_NULL

Z_GET_PROP_ADDR   lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        jsr     L1C8F
        ldy     #$0C
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
L21A7:  lda     (Z_VECTOR2),y
        and     #$3F
        cmp     Z_OPERAND2
        beq     L21E8
        bcs     L21B4
        jmp     L2216

L21B4:  lda     (Z_VECTOR2),y
        and     #$80
        beq     L21C2
        iny
        lda     (Z_VECTOR2),y
        and     #$3F
        jmp     L21CF

L21C2:  lda     (Z_VECTOR2),y
        and     #$40
        beq     L21CD
        lda     #$02
        jmp     L21CF

L21CD:  lda     #$01
L21CF:  tax
L21D0:  iny
        bne     L21D5
        inc     Z_VECTOR2+1
L21D5:  dex
        bne     L21D0
        iny
        tya
        clc
        adc     Z_VECTOR2
        sta     Z_VECTOR2
        bcc     L21E3
        inc     Z_VECTOR2+1
L21E3:  ldy     #$00
        jmp     L21A7

L21E8:  lda     (Z_VECTOR2),y
        and     #$80
        beq     L21F6
        iny
        lda     (Z_VECTOR2),y
        and     #$3F
        jmp     L2203

L21F6:  lda     (Z_VECTOR2),y
        and     #$40
        beq     L2201
        lda     #$02
        jmp     L2203

L2201:  lda     #$01
L2203:  iny
        tya
        clc
        adc     Z_VECTOR2
        sta     Z_VECTOR1
        lda     Z_VECTOR2+1
        adc     #$00
        sec
        sbc     Z_BASE_PAGE
        sta     Z_VECTOR1+1
        jmp     RETURN_NULL

L2216:  jmp     RETURN_ZERO

Z_GET_NEXT_PROP   jsr     L1CC3
        lda     Z_OPERAND2
        beq     L2232
L2220:  jsr     L1CE1
        cmp     Z_OPERAND2
        beq     L222F
        bcc     L2216
        jsr     L1D10
        jmp     L2220

L222F:  jsr     L1CFE
L2232:  jsr     L1CE1
        ldx     #$00
        jmp     RETURN_VALUE

Z_ADD   lda     Z_OPERAND1
        clc
        adc     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        adc     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

Z_SUB   lda     Z_OPERAND1
        sec
        sbc     Z_OPERAND2
        tax
        lda     Z_OPERAND1+1
        sbc     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

Z_MUL   jsr     L233A
L2257:  ror     L32ED
        ror     L32EC
        ror     Z_OPERAND2+1
        ror     Z_OPERAND2
        bcc     L2274
        lda     Z_OPERAND1
        clc
        adc     L32EC
        sta     L32EC
        lda     Z_OPERAND1+1
        adc     L32ED
        sta     L32ED
L2274:  dex
        bpl     L2257
        ldx     Z_OPERAND2
        lda     Z_OPERAND2+1
        jmp     RETURN_VECTOR1

Z_DIV   jsr     DO_MATH_DIV
        ldx     MATH_SCRATCH1
        lda     MATH_SCRATCH1+1
        jmp     RETURN_VECTOR1

Z_MOD   jsr     DO_MATH_DIV
        ldx     MATH_SCRATCH2
        lda     MATH_SCRATCH2+1
        jmp     RETURN_VECTOR1

DO_MATH_DIV:  lda     Z_OPERAND1+1
        sta     L32EF
        eor     Z_OPERAND2+1
        sta     L32EE
        lda     Z_OPERAND1
        sta     MATH_SCRATCH1
        lda     Z_OPERAND1+1
        sta     MATH_SCRATCH1+1
        bpl     L22AF
        jsr     L22E0
L22AF:  lda     Z_OPERAND2
        sta     MATH_SCRATCH2
        lda     Z_OPERAND2+1
        sta     MATH_SCRATCH2+1
        bpl     L22BE
        jsr     L22CE
L22BE:  jsr     L22F2
        lda     L32EE
        bpl     L22C9
        jsr     L22E0
L22C9:  lda     L32EF
        bpl     L22DF
L22CE:  lda     #$00
        sec
        sbc     MATH_SCRATCH2
        sta     MATH_SCRATCH2
        lda     #$00
        sbc     MATH_SCRATCH2+1
        sta     MATH_SCRATCH2+1
L22DF:  rts

L22E0:  lda     #$00
        sec
        sbc     MATH_SCRATCH1
        sta     MATH_SCRATCH1
        lda     #$00
        sbc     MATH_SCRATCH1+1
        sta     MATH_SCRATCH1+1
        rts

L22F2:  lda     MATH_SCRATCH2
        ora     MATH_SCRATCH2+1
        beq     L2335
        jsr     L233A
L22FD:  rol     MATH_SCRATCH1
        rol     MATH_SCRATCH1+1
        rol     L32EC
        rol     L32ED
        lda     L32EC
        sec
        sbc     MATH_SCRATCH2
        tay
        lda     L32ED
        sbc     MATH_SCRATCH2+1
        bcc     L231F
        sty     L32EC
        sta	L32ED
L231F:  dex
        bne     L22FD
        rol     MATH_SCRATCH1
        rol     MATH_SCRATCH1+1
        lda     L32EC
        sta     MATH_SCRATCH2
        lda     L32ED
        sta     MATH_SCRATCH2+1
        rts

L2335:  lda     #$08
        jmp     FATAL_ERROR

L233A:  ldx     #$10
        lda     #$00
        sta     L32EC
        sta     L32ED
        clc
        rts

Z_THROW_VALUE   lda     Z_OPERAND2
        sta     $68
        lda     Z_OPERAND2+1
        sta     $69
        jmp     Z_RET

Z_JE   dec     $77
        bne     L235A
        lda     #$09
        jmp     FATAL_ERROR

L235A:  lda     Z_OPERAND1
        ldx     Z_OPERAND1+1
        cmp     Z_OPERAND2
        bne     L2366
        cpx     Z_OPERAND2+1
        beq     L237E
L2366:  dec     $77
        beq     L2381
        cmp     $7D
        bne     L2372
        cpx     $7E
        beq     L237E
L2372:  dec     $77
        beq     L2381
        cmp     $7F
        bne     L2381
        cpx     $80
        bne     L2381
L237E:  jmp     L15A5

L2381:  jmp     L1599

Z_CALL_LN   lda     #$01
        sta     L32F9
        bne     L2390
Z_CALL   lda     #$00
        sta     L32F9
L2390:  lda     Z_OPERAND1
        ora     Z_OPERAND1+1
        bne     L23A1
        lda     L32F9
        beq     L239C
        rts

L239C:  ldx     #$00
        jmp     RETURN_VALUE

L23A1:  ldx     $68
        lda     $69
        jsr     PUSH_AX_TO_STACK
        lda     Z_PC
        ldx     L32F9
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
        beq     L23FB
        lda     #$00
        sta     Z_VECTOR2
L23DE:  ldy     Z_VECTOR2
        ldx     Z_LOCAL_VARIABLES,y
        lda     Z_LOCAL_VARIABLES+1,y
        jsr     PUSH_AX_TO_STACK
        ldy     Z_VECTOR2
        lda     #$00
        sta     Z_LOCAL_VARIABLES,y
        sta     Z_LOCAL_VARIABLES+1,y
        iny
        iny
        sty     Z_VECTOR2
        dec     Z_VECTOR3
        bne     L23DE
L23FB:  lda     L3303
        jsr     PUSH_AX_TO_STACK
        dec     $77
        lda     $77
        sta     L3303
        beq     L2468
        lda     Z_OPERAND2
        sta     Z_LOCAL_VARIABLES
        lda     Z_OPERAND2+1
        sta     Z_LOCAL_VARIABLES+1
        dec     $77
        beq     L2468
        lda     $7D
        sta     $0F02
        lda     $7E
        sta     $0F03
        dec     $77
        beq     L2468
        lda     $7F
        sta     $0F04
        lda     $80
        sta     $0F05
        dec     $77
        beq     L2468
        lda     $81
        sta     $0F06
        lda     $82
        sta     $0F07
        dec     $77
        beq     L2468
        lda     $83
        sta     $0F08
        lda     $84
        sta     $0F09
        dec     $77
        beq     L2468
        lda     $85
        sta     $0F0A
        lda     $86
        sta     $0F0B
        dec     $77
        beq     L2468
        lda     $87
        sta     $0F0C
        lda     $88
        sta     $0F0D
L2468:  ldx     Z_VECTOR3+1
        txa
        jsr     PUSH_AX_TO_STACK
        lda     Z_STACK_POINTER+1
        sta     $69
        lda     Z_STACK_POINTER
        sta     $68
        rts

Z_STOREW   asl     Z_OPERAND2
        rol     Z_OPERAND2+1
        jsr     L248D
        lda     $7E
        sta     (Z_VECTOR2),y
        iny
        bne     L2488
Z_STOREB   jsr     L248D
L2488:  lda     $7D
        sta     (Z_VECTOR2),y
        rts

L248D:  lda     Z_OPERAND2
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

Z_PUT_PROP   jsr     L1CC3
L24A3:  jsr     L1CE1
        cmp     Z_OPERAND2
        beq     L24B2
        bcc     L24C8
        jsr     L1D10
	jmp     L24A3

L24B2:  jsr     L1CE6
        iny
        cmp     #$01
        beq     L24C3
        cmp     #$02
        bne     L24CD
        lda     $7E
        sta     (Z_VECTOR2),y
        iny
L24C3:  lda     $7D
        sta     (Z_VECTOR2),y
        rts

L24C8:  lda     #$0A
        jmp     FATAL_ERROR

L24CD:  lda     #$0B
        jmp     FATAL_ERROR

Z_PRINT_CHAR   lda     Z_OPERAND1
        jmp     L2C49

Z_PRINT_NUM   lda     Z_OPERAND1
        sta     MATH_SCRATCH1
        lda     Z_OPERAND1+1
        sta     MATH_SCRATCH1+1
        lda     MATH_SCRATCH1+1
        bpl     L24EE
        lda     #$2D
        jsr     L2C49
        jsr     L22E0
L24EE:  lda     #$00
        sta     L32F0
L24F3:  lda     MATH_SCRATCH1
        ora     MATH_SCRATCH1+1
        beq     L2511
        lda     #$0A
        sta     MATH_SCRATCH2
        lda     #$00
        sta     MATH_SCRATCH2+1
        jsr     L22F2
        lda     MATH_SCRATCH2
        pha
        inc     L32F0
        bne     L24F3
L2511:  lda     L32F0
        bne     L251B
        lda     #$30
        jmp     L2C49

L251B:  pla
        clc
        adc     #$30
        jsr     L2C49
        dec     L32F0
        bne     L251B
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
	lda     Z_OPERAND1
        ora     Z_OPERAND1+1
        bne     DO_RAND
        sta     RAND_SEED	; zero, so reseed random generator
        sta     RAND_SEED+1	; (this isn't random at all)
        jmp     RETURN_ZERO

DO_RAND
	lda     RAND_SEED
        ora     RAND_SEED+1
        bne     L2580
        lda     Z_OPERAND1+1	; they're zero, so we're in initial state.
        bpl     L255A		; positive number?
        eor     #$FF		; negative, so seed to that value
        sta     RAND_SEED+1
        lda     Z_OPERAND1
        eor     #$FF
        sta     RAND_SEED
        inc     RAND_SEED
        lda     #$00
        sta     $47
        sta     Z_CURRENT_WINDOW
        beq     L2580		; effectively a jmp L2580
L255A:  lda     Z_OPERAND1
        sta     Z_OPERAND2
        lda     Z_OPERAND1+1
        sta     Z_OPERAND2+1
        jsr     RNG_HW
        stx     Z_OPERAND1	; should be very random
        and     #$7F
        sta     Z_OPERAND1+1	; also should be very random
        jsr     DO_MATH_DIV
        lda     MATH_SCRATCH2	; remainder high-byte
        clc
        adc     #$01
        sta     Z_VECTOR1
        lda     MATH_SCRATCH2+1 ; remainder low-byte
        adc     #$00
        sta     Z_VECTOR1+1
        jmp     RETURN_NULL

L2580:  lda     Z_CURRENT_WINDOW
        cmp     RAND_SEED+1
        bcc     L2598
        lda     $47
        cmp     RAND_SEED
        bcc     L2598
        beq     L2598
        lda     #$01
        sta     $47
        lda     #$00
        sta     Z_CURRENT_WINDOW
L2598:  lda     $47
        sta     Z_VECTOR1
        lda     Z_CURRENT_WINDOW
        sta     Z_VECTOR1+1
        inc     $47
        bne     L25A6
        inc     Z_CURRENT_WINDOW
L25A6:  jmp     RETURN_NULL
.)

Z_PUSH   ldx     Z_OPERAND1
        lda     Z_OPERAND1+1
        jmp     PUSH_AX_TO_STACK

Z_PULL   jsr     L14E4
        lda     Z_OPERAND1
        jmp     SET_GLOBAL_OR_LOCAL_WORD

Z_SCAN_TABLE   lda     $7E
        bmi     L2639
        ora     $7D
        beq     L2639
        lda     $77
        cmp     #$04
        beq     L25CA
L25C6:  lda     #$82
        sta     $7F
L25CA:  lda     $7F
        beq     L25C6
        lda     #$00
        asl     $7F
        rol
        lsr     $7F
        sta     L3302
        lda     L3302
        bne     L25E1
        lda     Z_OPERAND1
        sta     Z_OPERAND1+1
L25E1:  lda     Z_OPERAND2
        sta     $14
        lda     Z_OPERAND2+1
        sta     $15
        lda     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
L25F0:  lda     $14
        sta     !$0009
        lda     $15
        sta     !$000A
        lda     $16
        sta     !$000B
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     Z_OPERAND1+1
        bne     L2612
        lda     L3302
        beq     L2645
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     Z_OPERAND1
        beq     L2645
L2612:  lda     !$0009
        clc
        adc     $7F
        sta     $14
        bcc     L262D
        lda     !$000A
        adc     #$00
        sta     $15
        lda     !$000B
        adc     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
L262D:  dec     $7D
        bne     L25F0
        lda     $7E
        beq     L2639
        dec     $7E
        bne     L25F0
L2639:  lda     #$00
        sta     Z_VECTOR1
        sta     Z_VECTOR1+1
        jsr     RETURN_NULL
        jmp     L1599

L2645:  lda     !$0009
        sta     Z_VECTOR1
        lda     !$000A
        sta     Z_VECTOR1+1
        jsr     RETURN_NULL
        jmp     L15A5

Z_NOT   lda     Z_OPERAND1
        eor     #$FF
        sta     Z_VECTOR1
        lda     Z_OPERAND1+1
        eor     #$FF
        sta     Z_VECTOR1+1
        jmp     RETURN_NULL

Z_COPY_TABLE   lda     Z_OPERAND2
        ora     Z_OPERAND2+1
        bne     L266D
        jmp     L2721

L266D:  lda     $7E
        cmp     #$7F
        bcc     L2676
        jmp     L2748

L2676:  lda     Z_OPERAND1+1
        cmp     Z_OPERAND2+1
        bcc     L2689
        beq     L2681
        jmp     L26A2

L2681:  lda     Z_OPERAND1
        cmp     Z_OPERAND2
        beq     L2689
        bcs     L26A2
L2689:  lda     Z_OPERAND1
        clc
        adc     $7D
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        adc     $7E
        cmp     Z_OPERAND2+1
        bcc     L26A2
        bne     L26DA
        lda     Z_VECTOR2
        cmp     Z_OPERAND2
        beq     L26A2
        bcs     L26DA
L26A2:  lda     #$00
        sta     $16
        lda     Z_OPERAND1+1
        sta     $15
        lda     Z_OPERAND1
        sta     $14
        jsr     VIRT_TO_PHYS_ADDR
        lda     Z_OPERAND2
        sta     Z_VECTOR2
        lda     Z_OPERAND2+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_VECTOR2+1
        lda     $7D
        sta     Z_VECTOR3
        lda     $7E
        sta     Z_VECTOR3+1
L26C4:  jsr     DEC_PAGE_COUNT
        bcc     L26D9
        jsr     FETCH_BYTE_FROM_VECTOR
        ldy     #$00
        sta     (Z_VECTOR2),y
        inc     Z_VECTOR2
        bne     L26C4
        inc     Z_VECTOR2+1
        jmp     L26C4

L26D9:  rts

L26DA:  lda     $7D
        sta     Z_VECTOR3
        lda     $7E
        sta     Z_VECTOR3+1
        jsr     DEC_PAGE_COUNT
        lda     Z_OPERAND1
        clc
        adc     Z_VECTOR3
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        adc     Z_VECTOR3+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_VECTOR2+1
        lda     Z_OPERAND2
        clc
        adc     Z_VECTOR3
        sta     $0A
        lda     Z_OPERAND2+1
        adc     Z_VECTOR3+1
        clc
        adc     Z_BASE_PAGE
        sta     $0B
L2705:  ldy     #$00
        lda     (Z_VECTOR2),y
        sta     ($0A),y
        lda     Z_VECTOR2
        bne     L2711
        dec     Z_VECTOR2+1
L2711:  dec     Z_VECTOR2
        lda     $0A
        bne     L2719
        dec     $0B
L2719:  dec     $0A
        jsr     DEC_PAGE_COUNT
        bcs     L2705
        rts

L2721:  lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_VECTOR2+1
        lda     $7D
        sta     Z_VECTOR3
        lda     $7E
        sta     Z_VECTOR3+1
        ldy     #$00
L2736:  jsr     DEC_PAGE_COUNT
        bcc     L2747
        lda     #$00
        sta     (Z_VECTOR2),y
        iny
        bne     L2736
        inc     Z_VECTOR2+1
        jmp     L2736

L2747:  rts

L2748:  lda     $7D
        eor     #$FF
        sta     $7D
        lda     $7E
        eor     #$FF
        sta     $7E
        inc     $7D
        bne     L275A
        inc     $7E
L275A:  jmp     L26A2

Z_CHECK_ARG_COUNT   lda     Z_OPERAND1
        cmp     L3303
        bcc     L2769
        beq     L2769
        jmp     L1599

L2769:  jmp     L15A5

Z_LOG_SHIFT:  lda     Z_OPERAND1
        sta     Z_VECTOR1
        lda     Z_OPERAND1+1
        sta     Z_VECTOR1+1
        lda     Z_OPERAND2
        cmp     #$80
        bcs     L2785
        tay
L277B:  asl     Z_VECTOR1
        rol     Z_VECTOR1+1
        dey
        bne     L277B
        jmp     RETURN_NULL

L2785:  eor     #$FF
        tay
L2788:  lsr     Z_VECTOR1+1
        ror     Z_VECTOR1
        dey
        bpl     L2788
        jmp     RETURN_NULL

Z_ART_SHIFT   lda     Z_OPERAND2
        cmp     #$80
        bcc     Z_LOG_SHIFT
        ldx     Z_OPERAND1
        stx     Z_VECTOR1
        ldx     Z_OPERAND1+1
        stx     Z_VECTOR1+1
        eor     #$FF
        tay
L27A3:  lda     Z_OPERAND1+1
        asl
        ror     Z_VECTOR1+1
        ror     Z_VECTOR1
        dey
        bpl     L27A3
        jmp     RETURN_NULL

Z_AREAD   lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     $4A
        lda     Z_OPERAND1
        sta     $49
        lda     #$00
        sta     L330E
        sta     L330F
        ldx     $77
        dex
        beq     L27DD
        ldx     #$00
        lda     Z_OPERAND2+1
        ora     Z_OPERAND2
        beq     L27DD
        lda     Z_OPERAND2+1
        clc
        adc     Z_BASE_PAGE
        sta     $4C
        lda     Z_OPERAND2
        sta     $4B
        ldx     #$01
L27DD:  stx     L32F4
        ldy     #$00
        lda     ($49),y
        cmp     #$4F
        bcc     L27EA
        lda     #$4E
L27EA:  iny
        sec
        sbc     ($49),y
        sta     $46
        jsr     L3068
        lda     L32F4
        beq     L27FB
        jsr     L2803
L27FB:  lda     L3304
        ldx     #$00
        jmp     RETURN_VALUE

L2803:  ldy     #$01
        lda     ($49),y
        sta     $29
        lda     #$00
        sta     $2A
        sta     ($4B),y
        iny
        sty     $27
        sty     $28
L2814:  ldy     #$00
        lda     ($4B),y
        beq     L281E
        cmp     #$3B
        bcc     L2822
L281E:  lda     #$3A
        sta     ($4B),y
L2822:  iny
        cmp     ($4B),y
        bcc     L282D
        lda     $29
        ora     $2A
        bne     L282E
L282D:  rts

L282E:  lda     $2A
        cmp     #$09
        bcc     L2837
        jsr     L296A
L2837:  lda     $2A
        bne	L2860
	ldx	#$08
L283D:  sta     L32D6,x
        dex
        bpl     L283D
        jsr     L295C
        lda     $27
        ldy     #$03
        sta     ($2B),y
        tay
        lda     ($49),y
        jsr     L2998
        bcs     L287B
        jsr     L298C
        bcc     L2860
L2858   inc     $27
        dec     $29
        jmp     L2814

L2860:  lda     $29
        beq     L2884
        ldy     $27
        lda     ($49),y
        jsr     L2987
        bcs     L2884
        ldx     $2A
        sta     L32D6,x
        dec     $29
        inc     $2A
        inc     $27
        jmp     L2814

L287B:  sta     L32D6
        dec     $29
        inc     $2A
        inc     $27
L2884:  lda     $2A
        bne     L288B
        jmp     L2814

L288B:  jsr     L295C
        lda     $2A
        ldy     #$02
        sta     ($2B),y
        jsr     L1B73
        jsr     L29C3
        ldy     #$01
        lda     ($4B),y
        clc
        adc     #$01
        sta     ($4B),y
        ldy     #$00
        sty     $2A
        lda     L330E
        beq     L28B2
        lda     Z_VECTOR1+1
        ora     Z_VECTOR1
        beq     L28BB
L28B2:  lda     Z_VECTOR1+1
        sta     ($2B),y
        iny
        lda     Z_VECTOR1
        sta     ($2B),y
L28BB:  lda     $28
        clc
        adc     #$04
        sta     $28
        jmp     L2814

Z_TOKENIZE   lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     $4A
        lda     Z_OPERAND1
        sta     $49
        lda     Z_OPERAND2+1
        clc
        adc     Z_BASE_PAGE
        sta     $4C
        lda     Z_OPERAND2
        sta     $4B
        dec     $77
        dec     $77
        beq     L28F4
        lda     #$01
        sta     L330F
        lda     #$00
        dec     $77
        beq     L28EE
        lda     #$01
L28EE:  sta     L330E
        jmp     L28FC

L28F4:  lda     #$00
        sta     L330F
        sta     L330E
L28FC:  jmp     L2803

Z_ENCODE_TEXT   lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     $4A
        lda     Z_OPERAND1
        sta     $49
        lda     $7D
        clc
        adc     $49
        sta     $49
        lda     $7E
        adc     $4A
        sta     $4A
        lda     $80
        clc
        adc     Z_BASE_PAGE
        sta     $4C
        lda     $7F
        sta     $4B
        lda     #$09
        sta     $29
        lda     #$00
        sta     $2A
L292A:  ldx     #$08
L292C:  sta     L32D6,x
        dex
        bpl     L292C
L2932:  ldy     $2A
        lda     ($49),y
        jsr     L2987
        bcs     L294A
        ldy     $2A
        lda     ($49),y
        ldx     $2A
        sta     L32D6,x
        inc     $2A
        dec     $29
        bne     L2932
L294A:  lda     $2A
        beq     L295B
L294E:  jsr     L1B73
        ldy     #$05
L2953:  lda     L32DF,y
        sta     ($4B),y
        dey
        bpl     L2953
L295B:  rts

L295C:  lda     $4B
        clc
        adc     $28
        sta     $2B
        lda     $4C
        adc     #$00
        sta     $2C
        rts

L296A:  lda     $29
        beq     L297F
        ldy     $27
        lda     ($49),y
        jsr     L2987
        bcs     L297F
        dec     $29
        inc     $2A
        inc     $27
        bne     L296A
L297F:  rts

PUNCTUATION
	.asc	"!?,.", $0d, " ", $00

L2987:  jsr     L2998
        bcs     L29C1
L298C:  ldx     #$06
L298E:  cmp     PUNCTUATION,x
        beq     L29C1
        dex
        bpl     L298E
        clc
        rts

L2998:  sta     Z_TEMP1
        lda     Z_HDR_DICTIONARY
        ldy     Z_HDR_DICTIONARY+1
        sta     $15
        sty     $14
        lda     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     Z_VECTOR3
L29B0:  jsr     FETCH_BYTE_FROM_VECTOR
        cmp     Z_TEMP1
        beq     L29BF
        dec     Z_VECTOR3
        bne     L29B0
        lda     Z_TEMP1
        clc
        rts

L29BF:  lda     Z_TEMP1
L29C1:  sec
        rts

L29C3:  lda     L330F
        beq     L29CF
        lda     $7E
        ldy     $7D
        jmp     L29D5

L29CF:  lda     Z_HDR_DICTIONARY
        ldy     Z_HDR_DICTIONARY+1
L29D5:  sta     $15
        sty     $14
        lda     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
        jsr     FETCH_BYTE_FROM_VECTOR
        clc
        adc     $14
        sta     $14
        bcc     L29EC
        inc     $15
L29EC:  jsr     VIRT_TO_PHYS_ADDR
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $2F
        sta     Z_VECTOR2
        lda     #$00
        sta     Z_VECTOR2+1
        sta     Z_VECTOR3
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $2E
        jsr     FETCH_BYTE_FROM_VECTOR
        sta     $2D
        lda     $2E
        bpl     L2A0D
        jmp     L2B41

L2A0D:  lda     #$00
        sta     $6D
        sta     $6E
        sta     $6F
        ldx     $2F
L2A17:  clc
        lda     $6D
        adc     $2D
        sta     $6D
        lda     $6E
L2A20:  adc     $2E
        sta     $6E
        lda     $6F
        adc     #$00
        sta     $6F
L2A2A:  dex
        bne     L2A17
        clc
        lda     $6D
        adc     $14
        sta     $6D
        lda     $6E
        adc     $15
        sta     $6E
        lda     $6F
        adc     $16
        sta     $6F
        lda     $6D
        sec
        sbc     $2F
        sta     $6D
        lda     $6E
        sbc     #$00
        sta     $6E
        lsr     $2E
        ror     $2D
L2A51:  asl     Z_VECTOR2
        rol     Z_VECTOR2+1
        rol     Z_VECTOR3
        lsr     $2E
        ror     $2D
        bne     L2A51
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
        sbc     $2F
        sta     $14
        bcs     L2A88
        lda     $15
        sec
        sbc     #$01
        sta     $15
        bcs     L2A88
        lda     $16
        sbc     #$00
        sta     $16
L2A88:  lsr     Z_VECTOR3
        ror     Z_VECTOR2+1
        ror     Z_VECTOR2
        lda     $14
        sta     Z_VECTOR3+1
        lda     $15
        sta     $0A
        lda     $16
        sta     $0B
        jsr     VIRT_TO_PHYS_ADDR
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32DF
        bcc     L2AD9
        bne     L2B0D
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E0
        bcc     L2AD9
        bne     L2B0D
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E1
        bcc     L2AD9
        bne     L2B0D
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E2
        bcc     L2AD9
        bne     L2B0D
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E3
        bcc     L2AD9
        bne     L2B0D
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E4
        beq     L2B38
        bcs     L2B0D
L2AD9:  lda     Z_VECTOR3+1
        clc
        adc     Z_VECTOR2
        sta     $14
        lda     $0A
        adc     Z_VECTOR2+1
        bcs     L2AFE
        sta     $15
        lda     #$00
        sta     $16
        lda     $15
        cmp     $6E
        beq     L2AF6
        bcs     L2AFE
        bcc     L2B20
L2AF6:  lda     $14
        cmp     $6D
        bcc     L2B20
        beq     L2B20
L2AFE:  lda     $6D
        sta     $14
        lda     $6E
        sta     $15
        lda     $6F
        sta     $16
        jmp     L2B20

L2B0D:  lda     Z_VECTOR3+1
        sec
        sbc     Z_VECTOR2
        sta     $14
        lda     $0A
        sbc     Z_VECTOR2+1
        sta     $15
        lda     $0B
        sbc     Z_VECTOR3
        sta     $16
L2B20:  lda     Z_VECTOR3
        bne     L2B2E
        lda     Z_VECTOR2+1
        bne     L2B2E
        lda     Z_VECTOR2
        cmp     $2F
        bcc     L2B31
L2B2E:  jmp     L2A88

L2B31:  lda     #$00
        sta     Z_VECTOR1
        sta     Z_VECTOR1+1
        rts

L2B38:  lda     Z_VECTOR3+1
        sta     Z_VECTOR1
        lda     $0A
        sta     Z_VECTOR1+1
        rts

L2B41:  lda     #$FF
        eor     $2E
        sta     $2E
        lda     #$FF
        eor     $2D
        sta     $2D
        inc     $2D
        bne     L2B53
        inc     $2E
L2B53:  lda     $14
        sta     Z_VECTOR3+1
        lda     $15
        sta     $0A
        lda     $16
        sta     $0B
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32DF
        bne     L2B8F
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E0
        bne     L2B8F
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E1
        bne     L2B8F
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E2
        bne     L2B8F
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E3
        bne     L2B8F
        jsr     FETCH_BYTE_FROM_VECTOR
        cmp     L32E4
        beq     L2B38
L2B8F:  lda     Z_VECTOR3+1
        clc
        adc     $2F
        sta     $14
        bcc     L2BA5
        lda     $0A
        adc     #$00
        sta     $15
        lda     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
L2BA5:  dec     $2D
        bne     L2B53
        lda     $2E
        beq     L2B31
        dec     $2E
        jmp     L2B53

FATAL_ERROR
	jsr	CLOSE_ALL_FILES
	ldy     #$01
L2BC8:  ldx     #$00
L2BCA:  cmp     #$0A
        bcc     L2BD3
        sbc     #$0A
        inx
        bne     L2BCA
L2BD3:  ora     #$30
        sta     INT_ERROR_TEXT+15,y
        txa
        dey
        bpl     L2BC8
        ldx     #<INT_ERROR_TEXT
        lda     #>INT_ERROR_TEXT
        ldy     #$14
        jsr     PRINT_MESSAGE


Z_QUIT   jsr     L2D1A
        ldx     #<END_SESSION_TEXT
        lda     #>END_SESSION_TEXT
        ldy     #$2C
        jsr     PRINT_MESSAGE
        jmp     L2BF7

Z_RESTART   jsr     L2D1A
L2BF7	jsr	PRESS_RETURN

L2C0F:  lda     Z_HDR_FLAGS2+1
        and     #$01
        sta     INTERP_FLAGS
        jmp     STARTUP

GET_MAX_PAGE:  lda     MAX_RES_PAGE_CALC
        rts

L2C49:  sta     Z_TEMP1
        ldx     $6C
        beq     L2C52
        jmp     L2CC2

L2C52:  ldx     $6A
        bne     L2C5B
        ldx     $6B
        bne     L2C5B
        rts

L2C5B:  lda     Z_TEMP1
        ldx     $45
        bne     L2C83
        cmp     #$0D
        bne     L2C68
        jmp     L2D1A

L2C68:  cmp     #$20
        bcc     L2C82
        ldx     $4E
        sta     $0200,x
        lda     Z_CURRENT_WINDOW
        bne	L2C80
        ldy     $4D
        inc     $4D
        cpy     $70
        bcc     L2C80
        jmp     L2CDC

L2C80:  inc     $4E
L2C82:  rts

L2C83:  sta     Z_TEMP1
        cmp     #$20
        bcc     L2CBF
        jsr     L349E
        lda     Z_CURRENT_WINDOW
        beq     L2C9A
        cpy     #$28
        bcs     L2CBF
        cpx     $55
        bcs     L2CBF
        bcc     L2CA2
L2C9A:  cpy     #$27
        bcs     L2CBF
        cpx     $55
        bcc     L2CBF
L2CA2:  lda     $6A
        beq     L2CAB
        lda     Z_TEMP1
        jsr     PRINT_CHAR_AT_COORDINATE
L2CAB:  lda     Z_CURRENT_WINDOW
        bne     L2CBF
        lda     #$01
        sta     $5B
        lda     Z_TEMP1
        sta     $0200
        jsr     LOG_TO_PRINTER
        lda     #$00
        sta     $5B
L2CBF:  jmp     L36B7

L2CC2:  tax
        lda     $41
        clc
        adc     $3F
        sta     Z_VECTOR2
        lda     $42
        adc     $40
        sta     Z_VECTOR2+1
        ldy     #$00
        txa
        sta     (Z_VECTOR2),y
        inc     $41
        bne     L2CDB
        inc     $42
L2CDB:  rts

L2CDC:  lda     #$20
        stx     $50
L2CE0:  cmp     $0200,x
        beq     L2CF1
        dex
        bne     L2CE0
        ldx     $70
        inx
        lda     Z_CURRENT_WINDOW
        beq     L2CF1
        ldx     #$28
L2CF1:  stx     $4F
        stx     $4E
        jsr     L2D1A
        ldx     $4F
        ldy     #$00
L2CFC:  inx
        cpx     $50
        bcc     L2D08
        beq     L2D08
        sty     $4D
        sty     $4E
        rts

L2D08:  lda     $0200,x
        sta     $0200,y
        iny
        bne     L2CFC

Z_NEW_LINE
	ldx     $6C
        beq     L2D1A
        lda     #$0D
        jmp     L2CC2

L2D1A:  ldx     $4E
        lda     Z_CURRENT_WINDOW
        beq     L2D24
        cpx     #$28
        bcs     L2D2B
L2D24:  lda     #$0D
        sta     $0200,x
        inc     $4E
L2D2B:  lda     $6A
L2D2D:  beq     L2D81
        lda     Z_CURRENT_WINDOW
L2D31:  bne     L2D35
        inc     $52
L2D35:  ldx     $52
        inx
        cpx     $53
        bcc     L2D81
        lda     #$00
        sta     $52
        sta     $C6
	lda	#$00 ;PREF_MORE_COLOR		; v4 has #$00
        sta     COLOR
        jsr     L349E
        sty     L32FF
        stx     L32FE
        ldx     #<MORE_TEXT
        lda     #>MORE_TEXT
        ldy     #$06
        jsr     PRINT_MESSAGE
L2D59:  jsr     GETIN
        tax
        beq     L2D59
        ldy     L32FF
        ldx     L32FE
        clc
        jsr     PLOT
	lda	#$01	; PREF_FG_COLOR		; v4 has #$01
        sta     COLOR
        ldx     #<BLANK_TEXT
        lda     #>BLANK_TEXT
        ldy     #$06
        jsr     PRINT_MESSAGE
        ldy     L32FF
        ldx     L32FE
        clc
        jsr     PLOT
L2D81:  jsr     L2D8B
        lda     #$00
        sta     $4D
        sta     $4E
        rts

L2D8B:  ldy     $4E
        beq     L2DA8
        sty     $5B
        lda     $6A
        beq     L2DA1
        ldx     #$00
L2D97:  lda     $0200,x
        jsr     PRINT_CHAR_AT_COORDINATE
        inx
        dey
        bne     L2D97
L2DA1:  lda     Z_CURRENT_WINDOW
        bne     L2DA8
        jsr     LOG_TO_PRINTER
L2DA8:  rts

L2DA9:  jsr     L2D8B
        ldx     #$00
        stx     $4E
        rts

Z_ILLEGAL2   rts

Z_BUFFER_MODE   ldx     Z_OPERAND1
        bne     L2DC1
        jsr     L2D8B
        ldx     #$00
        stx     $4E
        inx
        stx     $45
        rts

L2DC1:  dex
        bne     L2DC6
        stx     $45
L2DC6:  rts

Z_OUTPUT_STREAM   ldx     Z_OPERAND1
        bmi     L2DD8
        dex
        beq     L2DE5
        dex
        beq     L2DEC
        dex
        beq     L2E03
        dex
        beq     L2DD7
L2DD7:  rts

L2DD8:  inx
        beq     L2DE9
        inx
        beq     L2DF8
        inx
        beq     L2E1A
        inx
        beq     L2DE4
L2DE4:  rts

L2DE5:  inx
        stx     $6A
        rts

L2DE9:  stx     $6A
        rts

L2DEC:  inx
        stx     $6B
        lda     Z_HDR_FLAGS2+1
        ora     #$01
        sta     Z_HDR_FLAGS2+1
        rts

L2DF8:  stx     $6B
        lda     Z_HDR_FLAGS2+1
        and     #$FE
        sta     Z_HDR_FLAGS2+1
        rts

L2E03:  inx
        stx     $6C
        lda     Z_OPERAND2+1
        clc
        adc     Z_BASE_PAGE
        ldx     Z_OPERAND2
        stx     $3F
        sta     $40
        lda     #$02
        sta     $41
        lda     #$00
        sta     $42
        rts

L2E1A:  lda     $6C
        beq     L2E48
        stx     $6C
        lda     $41
        clc
        adc     $3F
        sta     Z_VECTOR2
        lda     $42
        adc     $40
        sta     Z_VECTOR2+1
        lda	#$00
        tay
        sta     (Z_VECTOR2),y
        ldy     #$01
        lda     $41
        sec
        sbc     #$02
        sta     ($3F),y
        bcs     L2E3F
        dec     $42
L2E3F:  lda     $42
        dey
        sta     ($3F),y
        lda     #$00
        sta     $3E
L2E48:  rts

Z_SET_CURSOR   jsr     L2DA9
        lda     Z_CURRENT_WINDOW
        beq     L2E5A
        ldx     Z_OPERAND1
        dex
        ldy     Z_OPERAND2
        dey
        clc
        jsr     PLOT
L2E5A:  rts

Z_GET_CURSOR   jsr     L2DA9
        lda     Z_OPERAND1
        sta     Z_VECTOR2
        lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     Z_VECTOR2+1
        jsr     L349E
        inx
        iny
        tya
        ldy     #$03
        sta     (Z_VECTOR2),y
        dey
        lda     #$00
        sta     (Z_VECTOR2),y
        dey
        txa
        sta     (Z_VECTOR2),y
        dey
        lda     #$00
        sta     (Z_VECTOR2),y
        rts

Z_INPUT_STREAM   rts

Z_SET_TEXT_STYLE   ldx     Z_OPERAND1
        bne     L2E92
        lda     #$92
        jsr     L2EA1
        lda     #$82
        jmp     L2EA1

L2E91:  rts

L2E92:  cpx     #$01
        bne     L2E9B
        lda     #$12
        jmp     L2EA1

L2E9B:  cpx     #$04
        bne     L2E91
        lda     #$02
L2EA1:  sta     Z_TEMP1
        lda     $6A
        bne     L2EAC
        lda     $6B
        bne     L2EAC
        rts

L2EAC:  lda     Z_TEMP1
        ldx     $45
        beq     L2EB5
        jmp     CHROUT

L2EB5:  ldx     $4E
        sta     $0200,x
        inc     $4E
        rts

Z_ERASE_LINE   beq     L2EF1
        lda     Z_OPERAND1
        cmp     #$01
        bne     L2EF1
        jsr     L349E
        stx     L32FE
        sty     L32FF
L2ECE:  iny
        cpy     #$27
        bcs     L2EDB
        lda     #$20
        jsr     CHROUT
        jmp     L2ECE

L2EDB:  ldx     Z_CURRENT_WINDOW
        beq     L2EE4
        lda     #$20
        jsr     CHROUT
L2EE4:  ldx     L32FE
        ldy     L32FF
        clc
        jsr     PLOT
        jmp     L36B7

L2EF1:  rts

Z_ERASE_WINDOW   jsr     L2DA9
        jsr     L349E
        txa
        ldx     Z_CURRENT_WINDOW
        sta     L32FC,x
        tya
        sta     L32FA,x
        lda     Z_OPERAND1
        beq     L2F1A
        cmp     #$01
        beq     L2F4A
        cmp     #$FF
        bne     L2EF1
        jsr     L3584
        jsr     CLEAR_SCREEN
        lda     #$00
        tax
        tay
        beq     L2F68
L2F1A:  ldx     $55
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
        sta     $52
        lda     #$18
        sec
        sbc     $55
        sta     $0A
        ldx     #$27
        jsr     L2F74
        ldx     #$00
        lda     $55
        beq     L2F68
L2F4A:  lda     #$04
        sta     Z_VECTOR2+1
        lda     #$D8
        sta     Z_VECTOR3+1
        ldy     #$00
        sty     Z_VECTOR2
        sty     Z_VECTOR3
        sty     SPENA
        lda     $55
        sta     $0A
        ldx     #$28
        jsr     L2F74
        ldx     #$01
        lda     #$00
L2F68:  sta     L32FC,x
        lda     #$00
        sta     L32FA,x
        jmp     L35D7

L2F73   rts

L2F74:  stx     Z_VECTOR4
L2F76:  lda     #$20
        sta     (Z_VECTOR2),y
        lda     #$01
        sta     (Z_VECTOR3),y
        dex
        bne     L2F87
        dec     $0A
        beq     L2F90
        ldx     Z_VECTOR4
L2F87:  iny
        bne     L2F76
        inc     Z_VECTOR2+1
        inc     Z_VECTOR3+1
        bne     L2F76
L2F90:  rts

Z_PRINT_TABLE   lda     Z_OPERAND1
        sta     $14
        lda     Z_OPERAND1+1
        sta     $15
        lda     #$00
        sta     $16
        jsr     VIRT_TO_PHYS_ADDR
        lda     Z_OPERAND2
        cmp     #$00
        beq     L2FE8
        sta     Z_VECTOR3+1
        sta     Z_VECTOR3
        dec     $77
        lda     $77
        cmp     #$01
        beq     L2FB4
        lda     $7D
L2FB4:  sta     $0A
        lda     Z_CURRENT_WINDOW
        beq     L2FBD
        jsr     L2DA9
L2FBD:  jsr     L349E
        stx     L32FE
        sty     L32FF
L2FC6:  jsr     FETCH_BYTE_FROM_VECTOR
        jsr     L2C49
        dec     Z_VECTOR3
        bne     L2FC6
        dec     $0A
        beq     L2FE8
        inc     L32FE
        ldy     L32FF
        ldx     L32FE
        clc
        jsr     PLOT
        lda     Z_VECTOR3+1
        sta     Z_VECTOR3
        jmp     L2FC6

L2FE8:  rts

Z_SET_FONT
	lda     Z_OPERAND1
        ldx     Z_CURRENT_WINDOW
        cmp     L3307,x
        beq     L2FF7
        jsr     L300B
        bcs     L3008
L2FF7:  ldx     Z_CURRENT_WINDOW
        lda     L3307,x
        pha
        lda     Z_OPERAND1
        sta     L3307,x
        pla
        ldx     #$00
        jmp     RETURN_NULL

L3008:  jmp     RETURN_ZERO

L300B:  cmp     #$04
        beq     L303D
        cmp     #$03
        beq     L302E
        cmp     #$01
        beq     L301A
        jmp     L304E

L301A:  lda     TEXT_REVERSE_TOGGLE
        beq     L3024
        lda     #$12		; turn on reverse
        jmp     L3026

L3024:  lda     #$92		; turn off reverse
L3026:  jsr     L3050
        lda     #$0E		; turn on text mode
        jmp     L3049

L302E:  lda	L3305
	bne     L304E
        lda     #$92		; turn off reverse
        jsr     L3050
        lda     #$8E		; turn on graphics mode
        jmp     L3049

L303D:  lda     L3306
        bne     L304E
        lda     #$8E		; turn on graphics mode
        jsr     L3050
        lda     #$12		; turn on reverse
L3049:  jsr     L3050
        clc
        rts

L304E:  sec
        rts

L3050:  ldx     $45
        beq     L3057
        jmp     PRINT_CHAR_AT_COORDINATE

L3057:  ldx     $4E
        sta     $0200,x
        inc     $4E
        lda     $4E
        cmp     #$80
        bcc     L3067
        jsr     L2DA9
L3067:  rts

L3068:  jsr     L2DA9
        ldy     #$00
        sty     $52
        sty     Z_VECTOR2+1
        sty     Z_VECTOR2
        sty     Z_VECTOR3+1
        sty     Z_VECTOR3
        sty     $C6
        iny
        lda     ($49),y
        tax
        inx
        inx
        stx     L31C0
        jsr     L334A
        lda     $77
        cmp     #$02
        beq     L30A1
        lda     $7D
        sta     Z_VECTOR2+1
        lda     $77
        cmp     #$04
        bne     L309D
        lda     $7F
        sta     Z_VECTOR3
        lda     $80
        sta     Z_VECTOR3+1
L309D:  lda     Z_VECTOR2+1
        sta     Z_VECTOR2
L30A1:  lda     #$FA
        sta     $A2
L30A5:  jsr     GETIN
        cmp     #$00
        bne     L30E4
L30AC:  jsr     L3182
        lda     $A2
        bne     L30A5
        jmp     L30B6

L30B6:  lda     Z_VECTOR2
        beq     L30A1
        dec     Z_VECTOR2
        bne     L30A1
        jsr     L319F
        lda     Z_VECTOR3
        ora     Z_VECTOR3+1
        bne     L30CA
        jmp     L3181

L30CA:  jsr     L3294
        lda     Z_VECTOR1
        beq     L30D4
        jmp     L3181

L30D4:  lda     $52
        beq     L30DB
        jsr     L31AB
L30DB:  jsr     L334A
        jsr     L31A5
        jmp     L309D

L30E4:  jsr     L3398
        tax
        bne     L30ED
        jmp     L3131

L30ED:  jsr     L31C1
        bcs     L3102
        sta     L3304
        jsr     L319F
        lda     L3304
        cmp     #$0D
        beq     L3153
        jmp     L3177

L3102:  tay
        bmi     L314D
        cmp     #$0D
        beq     L3153
        cmp     #$14
        beq     L3137
        ldy     L31C0
        cpy     $46
        bcs     L314D
        cmp     #$80
        bcs     L311F
        sta     Z_TEMP1
        jsr     PRINT_CHAR_AT_COORDINATE
        lda     Z_TEMP1

L311F:  cmp	#$41
	bcc	L3129
	cmp	#$5b
        bcs     L3129
        adc     #$20
L3129:  ldy     L31C0
        sta     ($49),y
        inc	L31C0
L3131:  jsr     L334A
        jmp     L30AC

L3137:  sta     L3304
        lda     L31C0
        cmp     #$02
        beq     L314D
        dec     L31C0
        lda     L3304
        jsr     PRINT_CHAR_AT_COORDINATE
        jmp     L3131

L314D:  jsr     L363B
        jmp     L3131

L3153:  sta     L3304
        jsr     L319F
        lda     L3304
        jsr     PRINT_CHAR_AT_COORDINATE
        ldy     L31C0
        lda     #$00
        sta     ($49),y
        lda     $6B
        beq     L3177
        lda     Z_HDR_FLAGS2+1
        and     #$01
        beq     L3177
        jsr     L31E8
        jsr     LOG_TO_PRINTER
L3177:  ldx     L31C0
        dex
        dex
        txa
        ldy     #$01
        sta     ($49),y
L3181:  rts

L3182:  inc     L32F1
        bne     L319E
        inc     L32F2
        lda     L32F2
        cmp     #$0A
        bne     L319E
        lda     #$00
        sta     L32F2
        lda     $0340
        eor     #$FF
        sta     $0340
L319E:  rts

L319F:  lda     #$00
        sta	$0340
        rts

L31A5:  lda     #$FF
        sta     $0340
        rts

L31AB:  ldy     #$01
L31AD:  iny
        cpy     L31C0
        beq     L31BB
        lda     ($49),y
        jsr     PRINT_CHAR_AT_COORDINATE
        jmp     L31AD

L31BB:  lda     #$00
        sta     $52
        rts

L31C0:  .byte 0
L31C1:  pha
        lda     $26
        ora     $25
        beq     L31E3
        pla
        ldx     L330D
        beq     L31D4
        cmp     #$80
        bcs     L31E6
        bcc     L31E4
L31D4:  ldy     #$00
L31D6:  cmp     ($25),y
        beq     L31E6
        pha
        lda     ($25),y
        beq     L31E3
        pla
        iny
        bne     L31D6
L31E3:  pla
L31E4:  sec
        rts

L31E6:  clc
        rts

L31E8:  ldy     #$02
        ldx     #$00
L31EC:  lda     ($49),y
        cmp     #$80
        bcs     L3201
        cmp     #$00
        bne     L31F8
        lda     #$0D
L31F8:  sta     $0200,x
        inx
        cpy     L31C0
        beq     L3204
L3201:  iny
        bne     L31EC
L3204:  stx     $5B
        rts

Z_READ_CHAR   lda     Z_OPERAND1
        cmp     #$01
        beq     L3210
        jmp     RETURN_ZERO

L3210:  jsr     L2DA9
        lda     #$00
        sta     $4E
        sta     $52
        sta     $C6
        dec     $77
        bne     L3222
        jmp     L327C

L3222:  lda     Z_OPERAND2
        sta     Z_VECTOR2+1
        lda     #$00
        sta     Z_VECTOR3+1
        sta     Z_VECTOR3
        dec     $77
        beq     L3238
        lda     $7D
        sta     Z_VECTOR3
        lda     $7E
L3236:  sta     Z_VECTOR3+1
L3238:  jsr     L334A
L323B:  lda     Z_VECTOR2+1
        sta     Z_VECTOR2
L323F:  lda     #$FA
        sta     $A2
L3243:  jsr     GETIN
        cmp     #$00
        bne     L3254
        jsr     L3182
        lda     $A2
        bne     L3243
        jmp     L325E

L3254:  jsr     L3398
        cmp     #$00
        beq     L325E
        jmp     L327F

L325E:  dec     Z_VECTOR2
        bne     L323F
        jsr     L319F
        lda     Z_VECTOR3
        ora     Z_VECTOR3+1
        beq     L3291
        lda     Z_VECTOR3
        ora     Z_VECTOR3+1
        jsr     L3294
        lda     Z_VECTOR1
        bne     L3291
        jsr     L334A
        jmp     L323B

L327C:  jsr     GET_KEY
L327F:  sta     Z_VECTOR2
        jsr     L319F
        lda     Z_VECTOR2
        cmp     #$14
        bne     L328C
        lda     #$08
L328C:  ldx     #$00
        jmp     RETURN_VALUE

L3291:  jmp     RETURN_ZERO

L3294:  lda     Z_VECTOR2+1
        pha
        lda     Z_VECTOR3+1
        sta     Z_OPERAND1+1
        pha
        lda     Z_VECTOR3
        sta     Z_OPERAND1
        pha
        ldx     #$01
        stx     $77
        dex
        stx     L32F9
        lda     Z_PC
        pha
        stx     Z_PC
        lda     Z_PC+1
        pha
        stx     Z_PC+1
        lda     $10
        pha
        stx     $10
        jsr     L23A1
        jmp     MAIN_LOOP

L32BE:  pla
        pla
        pla
        sta     $10
        pla
        sta     Z_PC+1
        pla
        sta     Z_PC
        jsr     VIRT_TO_PHYS_ADDR_1
        pla
        sta     Z_VECTOR3
        pla
        sta     Z_VECTOR3+1
        pla
        sta     Z_VECTOR2+1
        rts

L32D6:  .byte 0
        .byte 0
        .byte 0
        .byte 0
        .byte 0
        .byte 0
        .byte 0
        .byte 0
        .byte 0
L32DF:  .byte 0
L32E0:  .byte 0
L32E1:  .byte 0
L32E2:  .byte 0
L32E3:  .byte 0
L32E4:  .byte 0
L32E5:  .byte 0
L32E6:  .byte 0
L32E7:  .byte 0
MATH_SCRATCH1:  .word 0
MATH_SCRATCH2:  .word 0
L32EC:  .byte 0
L32ED:  .byte 0
L32EE:  .byte 0
L32EF:  .byte 0
L32F0:  .byte 0
L32F1:  .byte 0
L32F2:  .byte 0
        .byte 0
L32F4:  .byte 0

RAND_SEED:  .word 0

L32F9:  .byte 0
L32FA:  .byte 0
L32FB:  .byte 0
L32FC:  .byte 0
L32FD:  .byte 0
L32FE:  .byte 0
L32FF:  .byte 0
        .byte 0
L3301:  .byte 0
L3302:  .byte 0
L3303:  .byte 0
L3304:  .byte 0
L3305   .byte 0
L3306:  .byte 0
L3307:  .byte	1, 1
        .byte	0, 0, 0, 0
L330D:  .byte	0
L330E:  .byte	0
L330F:  .byte	0
TEXT_REVERSE_TOGGLE:  .byte	0
Z_STATIC_ADDR:  .byte 0
Z_MAX_SAVES	.byte 0

MORE_TEXT	.aasc	"[MORE]"

L334A:  ldx     #$FF
        stx     $0340
        stx     SPENA
        inx
        stx     L32F1
        stx     L32F2
        jsr     L349E
        txa
        asl
        asl
        asl
        clc
        adc     #$39
        sta     $D001
        tya
        ldx     #$00
        cmp     #$1D
        bcc     L336E
        inx
L336E:  stx     $D010
        asl
        asl
        asl
        clc
        adc     #$18
        sta     IO_ADDR
        rts

GET_KEY:  jsr     L334A
L337E:  jsr     GETIN
        tax
        bne     L338A
        jsr     L3182
        jmp     L337E

L338A:  sta     Z_TEMP1
        jsr     L319F
        lda     Z_TEMP1
        jsr     L3398
        tax
        beq     L337E
        rts

L3398:  cmp     #$41
        bcc     L33AD
        cmp     #$5B
        bcs     L33AD
        adc     #$20
        jmp     L33D7

        cmp     #$85
        bcc     L33AD
        cmp     #$8D
        bcc     L33D7
L33AD:  ldx     #$0B
L33AF:  cmp     L33EC,x
        beq     L33B9
        dex
        bpl     L33AF
        bmi     L33BE
L33B9:  lda     L33F8,x
        bne     L33D7
L33BE:  and     #$7F
        cmp     #$20
        bcc     L33D2
        ldx     #$03
L33C6:  cmp     L33E8,x
        beq     L33D2
        dex
        bpl     L33C6
        cmp     #$5B
        bcc     L33D7
L33D2:  jsr     ERROR_SOUND
        lda     #$00
L33D7:  sta     Z_TEMP1
        adc     RANDOM
        sta     RANDOM
        eor     $D012
        sta     $D012
        lda     Z_TEMP1
        rts

L33E8:  .byte	$25, $26, $3d, $40

L33EC:	.byte	$8d, $0d, $94, $14, $3c, $3e, $91, $11
	.byte	$9d, $1d, $5e, $5f

L33F8:	.byte	$0d, $0d, $14, $14, $2c, $2e, $81, $82
	.byte	$83, $84, $81, $83

PUT_CHARACTER:  cmp     #$61
        bcc     L3411
        cmp     #$7B
        bcs     L341B
        and     #$5F
        jmp     CHROUT

L3411:  cmp     #$41
        bcc     L341B
        cmp     #$5B
        bcs     L341B
        ora     #$20
L341B:  jmp     CHROUT

PRINT_CHAR_AT_COORDINATE:  sta     Z_TEMP1
        txa
        pha
        tya
        pha
        jsr     L349E
        lda     Z_TEMP1
        cmp     #$0D
        beq     L3497
        cpx     #$17
        bcc     L346A
        cpy     #$27
        bcc     L346A
L3435:  dex
        clc
        jsr     PLOT
        ldx     $55
L343C:  cpx     #$18
        beq     L3460
        lda     VIC_ROW_ADDR_LO,x
        sta     $59
        lda     VIC_ROW_ADDR_HI,x
        sta     $5A
        inx
        lda     VIC_ROW_ADDR_LO,x
        sta     $57
        lda     VIC_ROW_ADDR_HI,x
        sta     $58
        ldy     #$27
L3457:  lda     ($57),y
        sta     ($59),y
        dey
        bpl     L3457
        bmi     L343C
L3460:  ldx     #$27
        lda     #$20
L3464:  sta     $07C0,x
        dex
        bpl     L3464
L346A:  lda     Z_TEMP1
        cmp     #$22
        bne     L347A
        jsr     PUT_CHARACTER
        lda     #$00
        sta     $D4
        jmp     L3492

L347A:  cmp     #$0D
        bne     L348F
        jsr     L349E
        ldy     Z_HDR_ROUTINES+1
        inx
        clc
        jsr     PLOT
        lda     #$00
        sta     $4E
        beq     L3492
L348F:  jsr     PUT_CHARACTER
L3492:  pla
        tay
        pla
        tax
        rts

L3497:  cpx     #$17
        bcc     L346A
        bcs     L3435
        .byte 0
L349E:  sec
        jsr     PLOT
        tya
        cmp     #$28
        bcc     L34AA
        sbc     #$28
        tay
L34AA:  rts

PRINT_MESSAGE:
	stx     L34B3+1
        sta     L34B3+2
        ldx     #$00
L34B3:  lda	!$0000,x
        jsr     PRINT_CHAR_AT_COORDINATE
        inx
        dey
        bne     L34B3
        rts

L3541:  .byte 0

Z_SPLIT_WINDOW   lda     $55
        sta     Z_VECTOR2
        ldx     Z_OPERAND1
        beq     L3584
        cpx     #$18
        bcs     L3583
        stx     $55
        stx     $56
        cpx     $52
        bcs     L3558
        stx     $52
L3558:  lda     #$17
        sec
        sbc     $55
        sta     $53
        lda     #$00
        sta     L32FB
        sta     L32FD
        jsr     L349E
        cpx     Z_VECTOR2
        bcc     L357B
        cpx     $55
        bcs     L3583
        ldx     $55
        ldy     Z_HDR_ROUTINES+1
        clc
        jmp     PLOT

L357B:  ldx     #$00
        ldy     #$00
        clc
        jmp     PLOT

L3583:  rts

L3584:  jsr     L35B2
L3587:  ldx     #$00
        stx     $55
        stx     $56
        stx     $52
        stx     Z_CURRENT_WINDOW
        lda     #$18
        sta     $53
        rts

Z_SET_WINDOW
	lda     $56
        beq     L3583
        jsr     L2DA9
        jsr     L349E
        txa
        ldx     Z_CURRENT_WINDOW
        sta     L32FC,x
        tya
        sta     L32FA,x
        lda     Z_OPERAND1
        bne     L35C0
        lda     #$00		; window 0 (main body)
        sta     Z_CURRENT_WINDOW
                                ; CK mod - switch to color white
        lda     #05
        jsr     CHROUT
                                ; end CK mod
L35B2:  jsr     L3558
        lda     L3301
        sta     $70
        lda     #$FF
        sta     $51
        bne     L35D7
L35C0:  cmp     #$01
        bne     L3583		; we handle only windows 0 and 1 :)
        sta     Z_CURRENT_WINDOW		; window 1 (status line)
                                ; CK mod - switch to color black
        lda     #$90
        jsr     CHROUT
                                ; end CK mod
        lda     #$00
        sta     $51
L35CA:  lda     $70
        sta     L3301
        lda     #$27
        sta     $70
        ldx     #$00
        ldy     #$00
L35D7:  ldx     Z_CURRENT_WINDOW
        lda     L32FA,x
        tay
        lda     L32FC,x
        tax
        clc
        jsr     PLOT
        jmp     L36B7

Z_DRAW_PICTURE   rts

Z_PICTURE_DATA   jmp     L1599

Z_SET_MARGINS   jsr     L2DA9
        lda     Z_OPERAND2
        sta     Z_HDR_STATIC+1
        lda     Z_OPERAND1
        sta     Z_HDR_ROUTINES+1
        lda     #$27
        sec
        sbc     Z_OPERAND2
        sbc     Z_OPERAND1
        beq     L3612
        bmi     L3612
        sta     $70
        sta     L3301
        jsr     L349E
        ldy     Z_OPERAND1
        clc
        jmp     PLOT
L3612:  rts

Z_SET_COLOR
	rts

L3614   jmp     L1599

Z_SOUND_EFFECT   lda     Z_HDR_MODE_BITS
        and     #$20
        beq     L3629
        ldx     Z_OPERAND1
        dex
        bne     L3626
        jmp     L363B

L3626:  dex
        beq     ERROR_SOUND
L3629:  rts

ERROR_SOUND:  lda     #$60
        sta     FRELO1
        lda     #$16
        sta     FREHI1
        lda     #$F2
        sta     $A2
        jmp     L3649

L363B:  lda     #$3C
        sta     FRELO1
        lda     #$32
        sta     FREHI1
        lda     #$FC
        sta     $A2
L3649:  lda     #$F0
        sta     SUREL1
        lda     #$8F
        sta     SIGVOL
        lda     #$41
        sta     VCREG1
L3658:  lda     $A2
        bne     L3658
        sta     VCREG1
        lda     #$80
        sta     SIGVOL
        rts

RNG_HW
.(
	inc     RANDOM
        dec     RASTER
        lda     RANDOM
        adc     $8C
        tax
        lda     RASTER
        sbc     $8D
        sta     $8C
        stx     $8D
        rts
.)

CLEAR_SCREEN
	lda     #>VICSCN
        sta     Z_VECTOR2+1
        lda     #>COLRAM
        sta     $0B
        ldy     #<COLRAM
        sty     Z_VECTOR2
        sty     $0A
L3689:  sty     SPENA
        ldx     #$04
L368E:  lda     #$20
        sta     (Z_VECTOR2),y
        lda     #$01
        sta     ($0A),y
        iny
        bne     L368E
        inc     Z_VECTOR2+1
        inc     $0B
        dex
        bne     L368E
        lda     #$0D
        sta     $07F8
        jsr     L35CA
        jsr     L3587
        sei
        lda     #<IRQ_HANDLER
        sta     $0318
        lda     #>IRQ_HANDLER
        sta     $0319
        cli
L36B7:  ldx     #$18
L36B9:  lda     VIC_ROW_ADDR_HI,x
        ora     #$80
        sta     $D9,x
        dex
        bpl     L36B9
        rts

IRQ_HANDLER     rti

L38FF:  jsr     L2D1A
        ldx     #$00
        stx     $51
        stx     $52
        rts

L3909	.aasc " (Default is "
L3916	.aasc "*):"

PRINT_DEFAULT_SLOT:  clc
        adc     #$31
        sta     L3916
        ldx     #<L3909
        lda     #>L3909
        ldy     #$10
        jsr     PRINT_MESSAGE
        ldx     #$00
        stx     $C6
        inx
        stx     SPENA
        rts

SAVE_SLOT_TEXT   .aasc	$0d, "Position 1-"
SAVE_SLOT:  .aasc	"*"
POS_CONFIRM_TEXT	.aasc	$0d, $0d
	.aasc	"Position "
L3956:  .aasc	"*.", $0d
	.aasc	"Are you sure? (Y or N):"

#define	POS_TEXT_LENGTH	#$25
#define CONFIRM_TEXT_LENGTH #$12

SET_POSITION
	ldx     #<SAVE_SLOT_TEXT
        lda     #>SAVE_SLOT_TEXT
        ldy     #$0D
        jsr     PRINT_MESSAGE
        lda     $5E
        jsr     PRINT_DEFAULT_SLOT
L39AF:  jsr     GET_KEY
        cmp     #$0D
        beq     L39C4
        sec
        sbc     #$31
        cmp     Z_MAX_SAVES
        bcc     L39C6
        jsr     ERROR_SOUND
        jmp     L39AF

L39C4:  lda     $5E
L39C6:  sta     $60
        clc
        adc     #$31
        sta     L3956
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
L3A1D:  jsr     GET_KEY
        cmp     #$59
        beq     L3A42
        cmp     #$79
        beq     L3A42
        cmp     #$4E
        beq     L3A36
        cmp     #$6E
        beq     L3A36
        jsr     ERROR_SOUND
        jmp     L3A1D

L3A36:  ldx     #<NO_TEXT
        lda     #>NO_TEXT
        ldy     #$03
        jsr     PRINT_MESSAGE
        jmp     SET_POSITION

L3A42:  lda     #$00
        sta     SPENA
        ldx     #<YES_TEXT
        lda     #>YES_TEXT
        ldy     #$04
        jsr     PRINT_MESSAGE
	clc
        rts

PRESS_RETURN:  ldx     #<L3B92
        lda     #>L3B92
        ldy     #$1E
        jsr     PRINT_MESSAGE
L3B7E:  jsr     GETIN
        cmp     #$00
        beq     L3B7E
        and     #$7F
        cmp     #$0D
        beq     L3B91
        jsr     ERROR_SOUND
        jmp     L3B7E

L3B91:  rts

L3B92	.aasc	$0d, "Press [RETURN] to continue.", $0d, $0d

Z_SAVE
.(
	lda	#$4e
        ldx	$77
        beq     L3BDD
        lda     #$50
L3BDD:  sta     L3302
        jsr     L38FF
        ldx     #<SAVE_POSITION_TEXT
        lda     #>SAVE_POSITION_TEXT
        ldy     #$0E
        jsr     PRINT_MESSAGE
        jsr     SET_POSITION
        bcc     L3BFC
L3BF1	jsr	CLOSE_SAVE_FILE
L3BF9:  jmp     RETURN_ZERO

L3BFC:  ldx     #<SAVING_POSITION_TEXT
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
        lda     $68
        sta     $0F24
	lda	$69
	sta	$0F25
        ldx     #$02
L3C2C:  lda     Z_PC,x
        sta     $0F26,x
        dex
        bpl     L3C2C
        lda     L3302
        sta     $0F29
        cmp     #$50
	bne     L3C4B
        ldy     #$00
        lda     ($7D),y
        tay
L3C43:  lda     ($7D),y
        sta     $0F2A,y
        dey
        bpl     L3C43
L3C4B:  lda     #$0F
        sta     PAGE_VECTOR+1

        jsr     UIEC_ONLY
        bcc     L3C4Ba
        clc
        jsr     CLOSE_STORY_FILE
        jsr     COMMAND_CLOSE

L3C4Ba

	jsr	SAVEFILE_OPEN_WRITE
        jsr     SEND_BUFFER_TO_DISK
        bcs     L3BF1
        lda     L3302
        cmp     #$50
        bne     L3C6A
        lda     Z_OPERAND1+1
        clc
        adc     Z_BASE_PAGE
        sta     PAGE_VECTOR+1
        ldx     Z_OPERAND2+1
        inx
        stx     Z_VECTOR2
        jmp     L3C88

L3C6A:  lda     #$09
        sta     PAGE_VECTOR+1
        lda     #$04
        sta     Z_VECTOR4
L3C72:  jsr     SEND_BUFFER_TO_DISK
        bcc     L3C7A
        jmp     L3BF1

L3C7A:  dec     Z_VECTOR4
        bne     L3C72
        lda     Z_BASE_PAGE
        sta     PAGE_VECTOR+1
        ldx     Z_HDR_DYN_SIZE
        inx
        stx     Z_VECTOR2
L3C88:  jsr     SEND_BUFFER_TO_DISK
        bcc     L3C90
        jmp     L3BF1

L3C90:  dec     Z_VECTOR2
        bne     L3C88
	jsr	CLOSE_SAVE_FILE

        jsr     UIEC_ONLY
        bcc     L3C9C
        clc
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN

L3C9C:  lda     $61
        sta     $5F
        lda     $60
        sta     $5E
        lda     #$01
        ldx     #$00
        jmp     RETURN_VALUE
.)

Z_RESTORE
.(
        lda	#$4e
	ldx	$77
        beq     L3CDE
        lda     #$50
L3CDE:  sta     L3302
        jsr     L38FF

        ldx     #<RESTORE_POSITION_TEXT
        lda     #>RESTORE_POSITION_TEXT
        ldy     #$11
        jsr     PRINT_MESSAGE
        jsr     SET_POSITION
        ldx     #<RESTORING_POSITION_TEXT
        lda     #>RESTORING_POSITION_TEXT
        ldy     #$1A
        jsr     PRINT_MESSAGE
L3D0A:  ldx     #$1F
L3D0C:  lda     Z_LOCAL_VARIABLES,x
        sta     STACK,x
        dex
        bpl     L3D0C
        lda     #>Z_LOCAL_VARIABLES	; $0F
        sta     PAGE_VECTOR+1

        jsr     UIEC_ONLY
        bcc     L3D0Ca
        clc
        jsr     CLOSE_STORY_FILE
        jsr     COMMAND_CLOSE
L3D0Ca
	jsr	SAVEFILE_OPEN_READ
	bcs	L3D2E
	ldx	#2
        jsr     READ_BUFFER_FROM_DISK
        bcs     L3D2E
        lda     $0F20
        cmp     Z_HDR_MODE_BITS+1
L3D24:  bne     L3D2E
        lda     $0F21
        cmp     Z_HDR_MODE_BITS+2
        beq     L3D44
L3D2E: 
	jsr	CLOSE_SAVE_FILE
        jsr     UIEC_ONLY
        bcc     L3D2Ea
        clc
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN
L3D2Ea
	ldx     #$1F
L3D30:  lda     STACK,x
        sta     Z_LOCAL_VARIABLES,x
        dex
        bpl     L3D30
L3D39:
L3D41:  jmp     RETURN_ZERO

L3D44:  lda     Z_HDR_FLAGS2
        sta     Z_VECTOR2
        lda     Z_HDR_FLAGS2+1
        sta     Z_VECTOR2+1
        lda     #$09
        sta     PAGE_VECTOR+1
        lda     #$04
        sta     Z_VECTOR4
L3D56
	ldx	#2
	jsr     READ_BUFFER_FROM_DISK
        bcc     L3D5E
        jmp     FATAL_ERROR_0E

L3D5E:  dec     Z_VECTOR4
        bne     L3D56
        lda     Z_BASE_PAGE
        sta     PAGE_VECTOR+1
	ldx	#2
        jsr     READ_BUFFER_FROM_DISK
        bcc     L3D6E
        jmp     FATAL_ERROR_0E

L3D6E:  lda     Z_VECTOR2
        sta     Z_HDR_FLAGS2
        lda     Z_VECTOR2+1
        sta     Z_HDR_FLAGS2+1
        lda     Z_HDR_DYN_SIZE
        sta     Z_VECTOR2
L3D7D
	ldx	#2
	jsr     READ_BUFFER_FROM_DISK
        bcc     L3D85
        jmp     FATAL_ERROR_0E

L3D85:  dec     Z_VECTOR2
        bne     L3D7D
	jsr	CLOSE_SAVE_FILE

        jsr     UIEC_ONLY
        bcc     L3D85a
        clc
        jsr     COMMAND_OPEN
        jsr     STORY_OPEN

L3D85a
        lda     $0F22
        sta     Z_STACK_POINTER
        lda     $0F23
        sta     Z_STACK_POINTER+1
        lda     $0F24
        sta     $68
        lda     $0F25
        sta     $69
        ldx     #$02
L3D9F:  lda     $0F26,x
        sta     Z_PC,x
        dex
        bpl     L3D9F
L3DA7:  lda     #$18
        sta     Z_HDR_SCREEN_ROWS
        lda     #SCREEN_WIDTH
        sta     Z_HDR_SCREEN_COLS
L3DB9:  jsr     VIRT_TO_PHYS_ADDR_1
        jsr     REQUEST_STATUS_LINE_REDRAW
        lda     $61
        sta     $5F
        lda     $60
        sta     $5E
        lda     #$02
        ldx     #$00
        jmp     RETURN_VALUE
.)

Z_ILLEGAL1   rts

Z_SAVE_RESTORE_UNDO   jmp     RETURN_ZERO

;
; local status stuff
;

MAX_RES_PAGE_CALC .byte 0


#include "common.s"
#include "sd2iec.s"
#include "ramexp.s"

; pad up to next page
.dsb    $100 - (* & $00FF), $FF

Z_HEADER = *
