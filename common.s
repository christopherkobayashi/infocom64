; $Id$
;

LOG_TO_PRINTER
.(
	rts
.)

; This fatal error is common.

FATAL_ERROR_0E
        lda     #$0E
        jmp     FATAL_ERROR

; retrieve page from somewhere in RAM (including under ROM) and stash it where
; PAGE_VECTOR points.

SECBUF_TO_PVEC
.(
        sei
        lda     R6510
        and     #MAP_RAM        ; including RAM underneath $D000
        sta     R6510
        ldy     #$00
L1      lda     SECTOR_BUFFER,y
        sta     (PAGE_VECTOR),y
        iny
        bne     L1
        sei
        lda     R6510           ;  unilaterally turn kernel back on
        ora     #MAP_ROM
        sta     R6510
        cli
        inc     PAGE_VECTOR+1
        inc     STORY_INDEX
        bne     L2
        inc     STORY_INDEX+1
L2      rts
.)

;
; convert flat sixteen-bit (high byte in x, low byte in a) into 16kb banks
; (bank in a, page in x)
;


SHIFT_ADDRESS
.(
        pha
        and     #$C0
        clc
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        sta     SCRATCH
        txa
        asl
        asl
        ora     SCRATCH
        sta     SCRATCH

        pla
        and     #$3f
        tax
        lda     SCRATCH
        rts
.)

READ_BUFFER
.(
        tay
        lda     REU_PRESENT
        and     #%00000100
        beq     READ_BUFFER_FROM_DISK

        lda     EF_BANK
        sta     EASYFLASH_BANK          ; bank should already be set?
        lda     #EASYFLASH_16K + EASYFLASH_LED
        sta     EASYFLASH_CONTROL
        lda     R6510
        pha
        sei
        lda     #$37
        sta     R6510

                                        ; we now have that bank at $8000
        ldy     #0
-EF_VEC1
        lda     $8000,y
        sta     SECTOR_BUFFER,y         ; 1a (PAGE_VECTOR)
        iny
        bne     EF_VEC1

        pla
        sta     R6510
        lda     #EASYFLASH_KILL
        sta     EASYFLASH_CONTROL
        cli

        inc     EF_VEC1+2
        lda     EF_VEC1+2               ; probably not needed, but just in case
        cmp     #$C0                    ; page finished?
        bne     L3
        lda     #$80
        sta     EF_VEC1+2
        inc     EF_BANK

L3      jsr     SECBUF_TO_PVEC          ; 1a
        clc
        rts
.)

READ_BUFFER_FROM_DISK
.(
        tya
        clc
        jsr     CHKIN
        bcc     L1
        jmp     STORY_READ_PAGE_ERROR

L1      ldy     #$00
L2      jsr     CHRIN
        sta     SECTOR_BUFFER,y
        jsr     READST                  ; EOF yet?
        and     #$40
        bne     L3                      ; might be wrong
        iny
        bne     L2

L3      jsr     SECBUF_TO_PVEC
        jsr     CLRCHN
        clc
        rts
.)


SAVEFILE_OPEN_READ:
.(
        lda     #2
        ldx     FA
        tay
        jsr     SETLFS
        lda     #7
        ldx     #<REST_FILENAME
        ldy     #>REST_FILENAME
        jsr     SETNAM
        jmp     OPEN
.)

SAVEFILE_OPEN_WRITE:
.(
        lda     #15                     ; delete old save file first!
        ldx     FA
        tay
        jsr     SETLFS
        ldx     #8
        ldx     #<SCRATCH_FILENAME
        ldy     #>SCRATCH_FILENAME
        jsr     SETNAM
        jsr     OPEN
        lda     #15
        jsr     CLOSE

        lda     #2
        ldx     FA
        tay
        jsr     SETLFS
        lda     #7
        ldx     #<SAVE_FILENAME
        ldy     #>SAVE_FILENAME
        jsr     SETNAM
        jsr     OPEN
        bcc     L1
        lda     #$46
        jmp     FATAL_ERROR
L1	rts
.)

SEND_BUFFER_TO_DISK:
.(
        sei			;
        lda     R6510		; not present in v3
        and     #$FD		; map out ROMs before copy
        sta     R6510		;
        ldy     #$00		
L1      lda     (PAGE_VECTOR),y
        sta     SECTOR_BUFFER,y
        iny
        bne     L1
        sei			;
        lda     R6510		; ditto
        ora     #$02		;
        sta     R6510		;
        cli			;
L2      ldx     #2
        jsr     CHKOUT
L3      lda     SECTOR_BUFFER,y
        jsr     CHROUT
        iny
        bne     L3
        inc     PAGE_VECTOR+1
        jsr     CLRCHN
        clc                     ; um ...
        rts
.)

STORY_TEXT:     .asc   "story.dat,r"
SCORE_TEXT:	.aasc	"Score: "
TIME_TEXT:	.aasc	"Time: "

COMMAND_OPEN:
.(
	lda	#15
	ldx	FA
	tay
	jsr	SETLFS
	jmp	OPEN
.)

COMMAND_CLOSE
.(
	lda	#15
	jmp	CLOSE
.)

STORY_OPEN:
.(
        lda     #5
        ldx     FA
        tay
        jsr     SETLFS
        lda     #11
        ldx     #<STORY_TEXT
        ldy     #>STORY_TEXT
        jsr     SETNAM
        jsr     OPEN
        bcs	STORY_READ_PAGE_ERROR
	rts
.)

STORY_READ_PAGE_ERROR:
.(
        lda     #$45
        jmp     FATAL_ERROR
.)

UIEC_READ_PAGE_ERROR:
.(
        lda     #$44
        jmp     FATAL_ERROR
.)

CLOSE_SAVE_FILE:
.(
        lda     #2
        jmp     CLOSE
.)

CLOSE_STORY_FILE:
.(
        lda     #5
        jmp     CLOSE
.)

CLOSE_ALL_FILES:
.(
        jsr	CLOSE_SAVE_FILE
        jsr     CLOSE_STORY_FILE
	jmp	COMMAND_CLOSE
.)

;TWIRLY: .byte   188, 172, 187, 190
;TWIRLY_STATE:   .byte 0
                                ; | = 98
                                ; / = 110
                                ; - = 99
                                ; \ = 109

;DO_TWIRLY
;.(
;        ldy     #19
;        ldx     #$10
;        clc
;        jsr     PLOT            ; move cursor to last asterisk spot
;        ldy     TWIRLY_STATE
;        lda     TWIRLY,y
;        jsr     CHROUT
;        iny
;        cpy     #4
;        bne     L1
;        ldy     #0
;L1	sty     TWIRLY_STATE
;        rts
;.)

PREP_SYSTEM
.(
	sta	EF_START_BANK
        lda     #$01
        sta     COLOR
        lda     #$0C
        sta     EXTCOL
        sta     BGCOL0
        lda     #147            ; clear screen
        jsr     CHROUT
        lda     #$0E            ; switch to lower case
        jsr     CHROUT
        lda     #$80
        sta     MODE

        lda     REU_PRESENT
        beq	L0              ; EasyFlash will have set this to #$04

        lda     #EASYFLASH_KILL
        sta     EASYFLASH_CONTROL       ; EasyFlash now off -- turn on and
                                        ; set R6510 to $37 to get ROMs
	bne	L1			; save a byte
L0	
	jsr	PREFERENCES_READ

L1
        lda     R6510
        and     #%11111110
        ora     #%00000110
        sta     R6510

        asl     MSGFLG
        lda     #$00
        sta     INTERP_FLAGS
        ldx     #$1C
L2      sta     SIDBASE,x
        dex
        bpl     L2
        lda     #$02
        sta     PWLO1
        lda     #$08
        sta     PWHI1
        lda     #$80
        sta     SIGVOL
        sta     VCREG3
        lda     #$EE
        sta     FRELO3
        sta     FREHI3
        ldx     #$3F
        lda     #$00
L3      sta     $0340,x
        dex
        bpl     L3
        sta     SP6COL
        sta     YXPAND
        sta     SPBGPR
        sta     SPMC
        sta     SP0COL			; this is 1 in v5!!!!!
        ;
        ; detect expansions
        ;
        ldy     #0
        ldx     #22
        clc
        jsr     PLOT
        lda     REU_PRESENT     ; skip for EasyFlash -- already done this
        beq	L4
	jsr	EASYFLASH_NOTIFY
	jmp	L5
L4      clc
        jsr     REU_DETECT
        bcs     L5
#ifdef GEORAM
        jsr     GEORAM_DETECT	; this is broken on the Ultimate64
#endif
L5	jsr	UIEC_IDENTIFY
	bcc	L6
	lda	REU_PRESENT
	ora	#8
	sta	REU_PRESENT
L6	clc
	rts
.)

PREFERENCES_READ:
.(
        lda     #5
        ldx     FA
        tay
        jsr     SETLFS
        lda     #7
        ldx     #<PREF_FILENAME
        ldy     #>PREF_FILENAME
        jsr     SETNAM
	clc
        jsr     OPEN
        bcs     L5
        ldx     #5
        jsr     CHKIN
        bcs     L5
        ldy     #$00
L1      jsr     CHRIN
        sta     PREF_FG_COLOR,y
        jsr     READST                  ; EOF yet?
        and     #$40
        bne     L5                      ; might be wrong
        iny
        cpy     #6
        bne     L1
L5	jsr	CLRCHN
	clc
	lda     #5
        jmp     CLOSE
.)

PREF_FILENAME   .asc   "prefs,r"

#ifdef  CK_PREFS
MY_COLOR =              $01
MY_EXTCOLOR =           $0c
MY_MORE_COLOR =         $00
#else
MY_COLOR =              $01
MY_EXTCOLOR =           $00
MY_MORE_COLOR =         $07
#endif

PREF_FG_COLOR   .byte   MY_COLOR
PREF_BG_COLOR   .byte   MY_EXTCOLOR
PREF_MORE_COLOR .byte   MY_MORE_COLOR
PREF_LOGGER     .byte   0
PREF_LOG_ADDR   .word   0

; common text here


RESTORE_POSITION_TEXT:
        .aasc   "Restore Position", $0d
RESTORING_POSITION_TEXT:
        .aasc   $0d, "Restoring position "
REST_POS_NUMBER
        .aasc   "* ...", $0d
REST_FILENAME
        .asc	"save"
REST_FN
        .asc "*,r"
SAVE_POSITION_TEXT
        .aasc   "Save Position", $0d
SAVING_POSITION_TEXT
        .aasc   $0d, "Saving position "
SAVE_POS_NUMBER
        .aasc   "* ...", $0d
SCRATCH_FILENAME
        .asc "s0:"
SAVE_FILENAME
        .asc "save"
SAVE_FN
        .asc "*,w"
BLANK_TEXT
        .byte "      "
END_SESSION_TEXT: .aasc "End of session.", $0d, $0d
                .aasc "Press [RETURN] to restart.", $0d ; extra gunk >v3

REU_TXT:	.aasc "(Loading story data into expansion RAM)", $0d

PATIENT: .aasc "(Loading resident code into system RAM)", $0d
STORY_LOADING_TEXT
	.aasc "The story is loading ...", $0d
YES_TEXT
        .aasc "YES", $0d
NO_TEXT
        .aasc "NO", $0d

INT_ERROR_TEXT .aasc "Internal error 00.  "

VALID_PUNCTUATION:  
        .byte   $00, $0d
        .byte   "0123456789.,!?_#"
        .byte   $27, $22 ; single and double-quotes
        .byte   "/\-:()"

;
; Offset table for each screen character row
;

VIC_ROW_ADDR_LO
        .byte   <VICSCN
        .byte   <VICSCN+(SCREEN_WIDTH*1)
        .byte   <VICSCN+(SCREEN_WIDTH*2)
        .byte   <VICSCN+(SCREEN_WIDTH*3)
        .byte   <VICSCN+(SCREEN_WIDTH*4)
        .byte   <VICSCN+(SCREEN_WIDTH*5)
        .byte   <VICSCN+(SCREEN_WIDTH*6)
        .byte   <VICSCN+(SCREEN_WIDTH*7)
        .byte   <VICSCN+(SCREEN_WIDTH*8)
        .byte   <VICSCN+(SCREEN_WIDTH*9)
        .byte   <VICSCN+(SCREEN_WIDTH*10)
        .byte   <VICSCN+(SCREEN_WIDTH*11)
        .byte   <VICSCN+(SCREEN_WIDTH*12)
        .byte   <VICSCN+(SCREEN_WIDTH*13)
        .byte   <VICSCN+(SCREEN_WIDTH*14)
        .byte   <VICSCN+(SCREEN_WIDTH*15)
        .byte   <VICSCN+(SCREEN_WIDTH*16)
        .byte   <VICSCN+(SCREEN_WIDTH*17)
        .byte   <VICSCN+(SCREEN_WIDTH*18)
        .byte   <VICSCN+(SCREEN_WIDTH*19)
        .byte   <VICSCN+(SCREEN_WIDTH*20)
        .byte   <VICSCN+(SCREEN_WIDTH*21)
        .byte   <VICSCN+(SCREEN_WIDTH*22)
        .byte   <VICSCN+(SCREEN_WIDTH*23)
        .byte   <VICSCN+(SCREEN_WIDTH*24)  

VIC_ROW_ADDR_HI
        .byte   >VICSCN
        .byte   >VICSCN+(SCREEN_WIDTH*1)
        .byte   >VICSCN+(SCREEN_WIDTH*2)
        .byte   >VICSCN+(SCREEN_WIDTH*3)
        .byte   >VICSCN+(SCREEN_WIDTH*4)
        .byte   >VICSCN+(SCREEN_WIDTH*5)
        .byte   >VICSCN+(SCREEN_WIDTH*6)
        .byte   >VICSCN+(SCREEN_WIDTH*7)
        .byte   >VICSCN+(SCREEN_WIDTH*8)
        .byte   >VICSCN+(SCREEN_WIDTH*9)
        .byte   >VICSCN+(SCREEN_WIDTH*10)
        .byte   >VICSCN+(SCREEN_WIDTH*11)
        .byte   >VICSCN+(SCREEN_WIDTH*12)
        .byte   >VICSCN+(SCREEN_WIDTH*13)
        .byte   >VICSCN+(SCREEN_WIDTH*14)
        .byte   >VICSCN+(SCREEN_WIDTH*15)
        .byte   >VICSCN+(SCREEN_WIDTH*16)
        .byte   >VICSCN+(SCREEN_WIDTH*17)
        .byte   >VICSCN+(SCREEN_WIDTH*18)
        .byte   >VICSCN+(SCREEN_WIDTH*19)
        .byte   >VICSCN+(SCREEN_WIDTH*20)
        .byte   >VICSCN+(SCREEN_WIDTH*21)
        .byte   >VICSCN+(SCREEN_WIDTH*22)
        .byte   >VICSCN+(SCREEN_WIDTH*23)
        .byte   >VICSCN+(SCREEN_WIDTH*24)

EF_START_BANK		.byte 0
EF_BANK			.byte 0
EF_NONRES_PAGE_BASE	.byte 0
EF_NONRES_BANK_BASE	.byte 0
SCRATCH			.byte 0

COLUMNS			.byte 0
INTERP_FLAGS		.byte 0
