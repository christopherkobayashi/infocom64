; $Id$

; uses code from http://www.cbmhardware.de/georam/index.php

REU_CMD_STASH = 	%11111100
REU_CMD_FETCH =		%11111101
SCRATCH_RAM =		$C000
GEOBUF_RAM =		$DE00
GEOBUF_PAGE =		$DFFE
GEOBUF_BANK =		$DFFF	; each bank is 16k, *not* 64k!

				;  512k = $00-$1f
				; 1024k = $00-$3f
				; 2048k = $00-$7f 

REU_BANKS
	.byte 0
REU_TEMP
	.byte 0

GEORAM_SIZE
	.byte 0

GEORAM_TEMP
	.byte 0

GEORAM_DETECT
.(
	lda	#0
	tax
	sta	GEOBUF_BANK
	sta	GEOBUF_PAGE	; GeoRAM $0000
;L0	lda	GEOBUF_RAM,x
;	sta	SCRATCH_RAM
;	inx
;	bne 	L0
;	txa
	lda     #$bb
L1	sta	GEOBUF_RAM,x	; write 256 bytes to GeoRAM
	lda	GEOBUF_RAM,x	; read,
	cmp	GEOBUF_RAM,x	; and compare ...
	bne	L2		; no good, we can't write
	inx
	bne	L1 
	lda	REU_PRESENT
	ora	#$02		; All good, GeoRAM is there
	sta	REU_PRESENT
;L2	ldx	#0
;L2a	lda	SCRATCH_RAM,x
;	sta	GEOBUF_RAM,x
;	inx
;	bne	L2a
L2	rts
.)

DET_TXT	.asc "Found ",0
EASYFLASH_TXT .asc "EasyFlash", 0
REUk_TXT .asc " bank CBM REU",0
GEO_TXT .asc "k GeoRAM",0
;C128_TXT	.asc " 128", 0
;		.asc " 256", 0
;		.asc " 512", 0
;		.asc "1024", 0
;		.asc "2048", 0
;		.asc "4096", 0
;		.asc "8192", 0
;		.asc "16384", 0
;		.byte 0

REU_DETECT:	; 2c75
.(
	ldy	#$01			; start with bank 1 -- good on 1700
L0	jsr     REU_SETUP_BANK          ; Fill top banks with $BB
	sty	REU_TEMP
	ldy	#$00			; badness detection
	jsr	REU_SETUP_BANK
	ldy	REU_TEMP
	jsr	REU_CHECK_BANK
	bcc	L1
	iny
	bne 	L0

	ldy	#$ff			; if we fallthrough here, it's 16384k
L1	tya
	clc
	sta	REU_BANKS
	cmp	#00
	beq	L2
	lda	REU_PRESENT
        ora     #$01
	sta	REU_PRESENT
	ldy	#0
L1a	lda	DET_TXT,y
	beq	L1a1
	jsr	CHROUT
	iny
	bne 	L1a

L1a1	lda	REU_BANKS
	; from http://forum.6502.org/viewtopic.php?f=2&t=3164 -- byte to ascii
	sed        ;2  @2
	tax        ;2  @4
	and #$0F   ;2  @6
	cmp #9+1   ;2  @8
	adc #$30   ;2  @10
	tay        ;2  @12
	txa        ;2  @14
	lsr        ;2  @16
	lsr        ;2  @18
	lsr        ;2  @20
	lsr        ;2  @22
	cmp #9+1   ;2  @24
	adc #$30   ;2  @26
	cld        ;2  @28
	jsr 	CHROUT
	tya
	jsr	CHROUT

L1b0	ldy	#0
L1b1	lda	REUk_TXT,y
	beq	L1b1a
	jsr	CHROUT
	iny
	bne 	L1b1
L1b1a	sec
	rts

L2	lda     REU_PRESENT
	and	#$FE
        sta     REU_PRESENT
        clc
        rts
.)

REU_SETUP_BANK:	; 2c59
.(
        sty     Z_TEMP1			; bank number we're probing
					; see if we already probed this bank
L1      ldx     #0
	tya
L2      sta     SECTOR_BUFFER,x
        inx
        bne     L2

        lda     #$00
        sta     REU_RBASE+1
        sta     REU_RBASE
        sta     REU_INT
        sta     REU_ACR
        sta     REU_TLEN
        lda     #$01
        sta     REU_TLEN+1
        lda     Z_TEMP1
        sta     REU_RBASE+2
        lda     #>SECTOR_BUFFER
        sta     REU_CBASE+1
        lda     #<SECTOR_BUFFER
        sta     REU_CBASE
        lda     #%11111100		; CBM -> REU
        sta     REU_COMMAND
	rts
.)

REU_CHECK_BANK:
.(
	sty	Z_TEMP1
	lda     #$bb
	tax
L1	sta	SECTOR_BUFFER,x
	inx
	bne	L1

	lda	#0
        sta     REU_RBASE+1
        sta     REU_RBASE
        sta     REU_INT
        sta     REU_ACR
        sta     REU_TLEN
        lda     #1
        sta     REU_TLEN+1
        lda     Z_TEMP1
        sta     REU_RBASE+2
        lda     #>SECTOR_BUFFER
        sta     REU_CBASE+1
        lda     #<SECTOR_BUFFER
        sta     REU_CBASE
        lda     #%11111101		; REU -> CBM
        sta     REU_COMMAND

	lda	SECTOR_BUFFER
	cmp	Z_TEMP1
	bne	L2
	sec
	rts
L2	clc
	rts
.)

IREU_FETCH:
.(
        lda     REU_PRESENT
        and     #$07
        cmp     #1
        bne	L1
	jsr	CBM_REU_FETCH
	rts
L1	cmp     #2
        bne	L2
	jsr	GEORAM_FETCH
	rts
L2	cmp     #4
        bne	L3
	jsr	EASYFLASH_FETCH
	rts
L3
DIE	jmp     DIE
.)

CBM_REU_FETCH
.(
        stx     REU_RBASE+2             ; REU bank (derived S_I+1)
        sty     REU_RBASE+1             ; REU page (derived S_I)
        lda     #$00
        sta     REU_RBASE               ; always 0
        sta     REU_INT
        sta     REU_ACR
        sta     REU_TLEN
        lda     #$01
        sta     REU_TLEN+1
        lda     #>SECTOR_BUFFER
        sta     REU_CBASE+1
        lda     #<SECTOR_BUFFER
        sta     REU_CBASE
        lda     #%11111101
        sta     REU_COMMAND
        rts
.)

GEORAM_FETCH
.(
        tya
        jsr     SHIFT_ADDRESS
        stx     GEORAM_PAGE
        sta     GEORAM_BANK

        ldy     #0
L1	lda     GEORAM_RAM,y
        sta     SECTOR_BUFFER,y
        iny
        bne     L1
        rts
.)

EASYFLASH_NOTIFY
.(
	ldy	#0
L1	lda	DET_TXT,y
	cmp	#0
	beq	L101
	jsr	CHROUT
	iny
	bne	L1
L101	ldy	#0
L1a	lda	EASYFLASH_TXT,y
	cmp	#0
	beq	L1a1
	jsr	CHROUT
	iny
	bne 	L1a
L1a1	rts
.)

EASYFLASH_FETCH
.(
        tya
        jsr     SHIFT_ADDRESS
        sta     EF_BANK
        txa
        adc     EF_NONRES_PAGE_BASE
        cmp     #$C0                    ; past ROM page?
        bcc     L1

        inc     EF_BANK                 ; bump up the EasyFlash bank
        sec
        sbc     #$40                    ; and compensate the address

L1	sta     L2+2

        clc
        lda     EF_BANK
        adc     EF_NONRES_BANK_BASE
        sta     EASYFLASH_BANK          ; bank should already be set?
        lda     #EASYFLASH_16K + EASYFLASH_LED
        sta     EASYFLASH_CONTROL
        lda     R6510
        pha
        sei
        lda     #$37
        sta     R6510

        ldy     #0
L2	lda     !$0000,y
        sta     SECTOR_BUFFER,y
        iny
        bne     L2
        pla
        sta     R6510
        lda     #EASYFLASH_KILL
        sta     EASYFLASH_CONTROL
        cli
        rts
.)

IEC_FETCH
.(
        ldy     #0
        jsr     UIEC_SEEK
        ldx     #5
	clc
        jsr     CHKIN
	bcc	L0
	jmp	UIEC_READ_PAGE_ERROR
L0      ldy     #0
L1:     jsr     CHRIN
        sta     SECTOR_BUFFER,y
        iny
        bne     L1
        jsr     CLRCHN
	clc
	rts
.)

IREU_STASH:
.(
        lda     REU_PRESENT
        and     #%00000011
        cmp     #1
        beq     CBM_REU_STASH
        cmp     #2
        beq     GEORAM_STASH
DIE	jmp     DIE
.)

GEORAM_STASH
.(
        lda     Z_VECTOR2+1
        ldx     Z_VECTOR4
        jsr     SHIFT_ADDRESS
        stx     GEORAM_PAGE
        sta     GEORAM_BANK

        ldy     #0
L1      lda     SECTOR_BUFFER,y
        sta     GEORAM_RAM,y
        iny
        bne     L1
        rts
.)

CBM_REU_STASH
.(
        lda     Z_VECTOR2+1
        sta     REU_RBASE+1
        lda     Z_VECTOR2
        sta     REU_RBASE
        lda     #$00
        sta     REU_INT
        sta     REU_ACR
        sta     REU_TLEN
        lda     #$01
        sta     REU_TLEN+1
        lda     Z_VECTOR4
        sta     REU_RBASE+2
        lda     #>SECTOR_BUFFER
        sta     REU_CBASE+1
        lda     #<SECTOR_BUFFER
        sta     REU_CBASE
        lda     #REU_CMD_STASH          ; % 1111 1100
        sta     REU_COMMAND             ; from RAM to REU
	rts
.)
