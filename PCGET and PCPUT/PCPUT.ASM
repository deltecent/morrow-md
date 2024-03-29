;
;  PCPUT - This CP/M program sends a file from the CP/M machine to a PC using
;	a serial port. The file transfer uses the XMODEM protocol. 
;
;  Note this program is gutted from the Ward Christenson Modem program.
;
;  Hacked together by Mike Douglas for the Altair 2SIO serial interface board.
;  Modified for Morrow Micro-Decision Models MD2 and MD3 by Patrick Linstruth.
;	Ver	Date	Desc
;	1.0    11/17/21	Initial version
;
;  Serial Port Equates

SIOACR	EQU	0FDh		;console port - control register
SIOADR	EQU	0FCh		;console port - data register
SIOBCR	EQU	0FFh		;2nd port - control register
SIOBDR	EQU	0FEh		;2nd port - data register

XMTMASK	EQU	1		;MASK TO ISOLATE XMIT READY BIT
XMTRDY	EQU	1		;VALUE WHEN READY
RCVMASK	EQU	2		;MASK TO ISOLATE RECEIVE READY BIT
RCVRDY	EQU	2		;BIT ON WHEN READY

ERRLMT	EQU	5		;MAX ALLOWABLE ERRORS

;DEFINE ASCII CHARACTERS USED

SOH	EQU	1
EOT	EQU	4
ACK	EQU	6
NAK	EQU	15H
CTRLC	EQU	3		;Control-C
LF	EQU	10
CR	EQU	13

	org	100h

;  Verify a file name was specified

	lda	PARAM1		;A=1st character of parameter 1
	cpi	' '		;make sure something entered
	jnz	havep1
	lxi	d,mHelp		;display usage message
	mvi	c,print
	call	bdos
	ret			;return to CPM

;  See if port "B" specified (2nd parameter)

havep1	mvi	b,0		;assume port b not used
	lda	PARAM2		;A=1st character of parameter 2
	ani	5fh		;force upper case
	cpi	'B'		;port b specified?
	jnz	doXfer		;no, go do the transfer
	inr	b		;force flag to non-zero value
	
;  doXfer - Switch to local stack and do the transfer

doXfer	mov	a,b		;store the port b flag
	sta	fPortB
	LXI	H,0		;HL=0
	DAD	SP		;HL=STACK FROM CP/M
	SHLD	STACK		;..SAVE IT
	LXI	SP,STACK	;SP=MY STACK
	xra	a		
	sta	SECTNO		;initialize sector number to zero
	CALL	OPEN$FILE	;OPEN THE FILE
	lxi	d,mRcvA		;assume using port A
	lda	fPortB		;using port B?
	ora	a
	jz	sendA
	lxi	d,mRcvB		;using port B
sendA	MVI	C,PRINT
	CALL	BDOS		;PRINT ID MESSAGE

;  GOBBLE UP GARBAGE CHARS FROM THE LINE

purge	MVI	B,1		;times out after 1 second if no data
	CALL	RECV
	jc	lineClr		;line is clear, go wait for initial NAK
	cpi	ctrlc		;exit if abort requested
	jz	abort
	jmp	purge

; WAIT FOR INITIAL NAK, THEN SEND THE FILE
	
lineClr	xra	a		;clear crc flag = checksum mode
	sta	crcFlag
WAITNAK	MVI	B,1		;TIMEOUT DELAY
	CALL	RECV
	JC	WAITNAK
	cpi	ctrlc		;abort requested?
	jz	abort
	CPI	NAK		;NAK RECEIVED?
	jz	SENDB		;yes, send file in checksum mode
	cpi	'C'		;'C' for CRC mode received?
	JNZ	WAITNAK		;no, keep waiting
	sta	crcFlag		;set CRC flag non-zero = true
				;fall through to start the send operation
;
;*****************SEND A FILE***************
;

;READ SECTOR, SEND IT

SENDB	CALL	READ$SECTOR
	LDA	SECTNO		;INCR SECT NO.
	INR	A
	STA	SECTNO

;SEND OR REPEAT SECTOR

REPTB	MVI	A,SOH
	CALL	SEND
	LDA	SECTNO
	CALL	SEND
	LDA	SECTNO
	CMA
	CALL	SEND
	lxi	h,0		;init crc to zero
	shld	crc16
	mov	c,h		;init checksum in c to zero
	LXI	H,80H
SENDC	MOV	A,M
	CALL	SEND
	call	calCrc		;update CRC
	INX	H
	MOV	A,H
	CPI	1		;DONE WITH SECTOR?
	JNZ	SENDC

; Send checksum or CRC based on crcFlag

	lda	crcFlag		;crc or checksum?
	ora	a
	jz	sndCsum		;flag clear = checksum
	lda	crc16+1		;a=high byte of CRC
	call	SEND		;send it
	lda	crc16		;a=low byte of crc
	jmp	sndSkip		;skip next instruction	
sndCsum	mov	a,c		;send the checksum byte
sndSkip	call	SEND

;GET ACK ON SECTOR

	MVI	B,4		;WAIT 4 SECONDS MAX
	CALL	RECV
	JC	REPTB		;TIMEOUT, SEND AGAIN

;NO TIMEOUT SENDING SECTOR

	CPI	ACK		;ACK RECIEVED?
	JZ	SENDB		;..YES, SEND NEXT SECT
	cpi	ctrlc		;control-c to abort?
	jz	abort
	JMP	REPTB		;PROBABLY NAK - TRY AGAIN
;
;
; S U B R O U T I N E S
;
;OPEN FILE
OPEN$FILE LXI	D,FCB
	MVI	C,OPEN
	CALL	BDOS
	INR	A		;OPEN OK?
	RNZ			;GOOD OPEN
	CALL	ERXIT
	DB	13,10,'Can''t Open File',13,10,'$'

; - - - - - - - - - - - - - - -
;EXIT PRINTING MESSAGE FOLLOWING 'CALL ERXIT'
ERXIT	POP	D		;GET MESSAGE
	MVI	C,PRINT
	CALL	BDOS		;PRINT MESSAGE
EXIT	LHLD	STACK		;GET ORIGINAL STACK
	SPHL			;RESTORE IT
	RET			;--EXIT-- TO CP/M

; - - - - - - - - - - - - - - -
;MODEM RECV
;-------------------------------------
RECV	PUSH	D		;SAVE
MSEC	LXI	D,(159 shl 8)	;49 cycle loop, 6.272ms/wrap * 159 = 1 second
	lda	fPortB		;using port B?
	ora	a
	jnz	MWTIB

;  port A input

MWTI	IN	SIOACR
	ANI	RCVMASK
	CPI	RCVRDY
	JZ	MCHAR		;GOT CHAR
	DCR	E		;COUNT DOWN
	JNZ	MWTI		;FOR TIMEOUT
	DCR	D
	JNZ	MWTI
	DCR	B		;DCR # OF SECONDS
	JNZ	MSEC

;MODEM TIMED OUT RECEIVING

	POP	D		;RESTORE D,E
	STC			;CARRY SHOWS TIMEOUT
	RET

;GOT MODEM CHAR

MCHAR	IN	SIOADR
	POP	D		;RESTORE DE
	PUSH	PSW		;CALC CHECKSUM
	ADD	C
	MOV	C,A
	POP	PSW
	ORA	A		;TURN OFF CARRY TO SHOW NO TIMEOUT
	RET

;  port B input. Look for Ctrl-C on port A to abort

MWTIB	IN	SIOBCR
	ANI	RCVMASK
	CPI	RCVRDY
	JZ	MCHARB		;GOT CHAR
	DCR	E		;COUNT DOWN
	JNZ	MWTIB		;FOR TIMEOUT
	in	SIOACR		;see if a ctrl-c pressed on console
	rrc			;character present?
	jnc	noCtrlC		;no
	in	SIOADR
	cpi	CTRLC		;is it a Ctrl-C?
	jnz	noCtrlC		;no
	pop	d		;restore d,e
	ret			;carry is clear (no timeout), exit

noCtrlC	DCR	D
	JNZ	MWTIB
	DCR	B		;DCR # OF SECONDS
	JNZ	MSEC

;MODEM TIMED OUT RECEIVING

	POP	D		;RESTORE D,E
	STC			;CARRY SHOWS TIMEOUT
	RET

;GOT MODEM CHAR

MCHARB	IN	SIOBDR
	POP	D		;RESTORE DE
	PUSH	PSW		;CALC CHECKSUM
	ADD	C
	MOV	C,A
	POP	PSW
	ORA	A		;TURN OFF CARRY TO SHOW NO TIMEOUT
	RET

; - - - - - - - - - - - - - - -
;MODEM SEND CHAR ROUTINE
;----------------------------------
;
SEND	PUSH	PSW		;CHECK IF MONITORING OUTPUT
	ADD	C		;CALC CKSUM
	MOV	C,A
	lda	fPortB		;using port B?
	ora	a
	jnz	SENDWB

; Use port A

SENDW	IN	SIOACR
	ANI	XMTMASK
	CPI	XMTRDY
	JNZ	SENDW
	POP	PSW		;GET CHAR
	OUT	SIOADR
	RET

; Use port B

SENDWB	IN	SIOBCR
	ANI	XMTMASK
	CPI	XMTRDY
	JNZ	SENDWB
	POP	PSW		;GET CHAR
	OUT	SIOBDR
	RET

;
;FILE READ ROUTINE
;
READ$SECTOR:
	LXI	D,FCB
	MVI	C,READ
	CALL	BDOS
	ORA	A
	RZ
	DCR	A		;EOF?
	JNZ	RDERR

;EOF

	XRA	A
	STA	ERRCT
SEOT	MVI	A,EOT
	CALL	SEND
	MVI	B,3		;WAIT 3 SEC FOR TIMEOUT
	CALL	RECV
	JC	EOTTOT		;EOT TIMEOUT
	CPI	ACK
	JZ	XFER$CPLT

;ACK NOT RECIEVED

EOTERR	LDA	ERRCT
	INR	A
	STA	ERRCT
	CPI	ERRLMT
	JC	SEOT
	CALL	ERXIT
	db	13,10,10
	db	'No ACK received on EOT, but transfer is complete.',13,10,'$'
;
;TIMEOUT ON EOT
;
EOTTOT	JMP	EOTERR
;
;READ ERROR
;
RDERR	CALL	ERXIT
	DB	13,10,'File Read Error',13,10,'$'

;DONE - CLOSE UP SHOP

XFER$CPLT:
	CALL	ERXIT
	DB	13,10,10,'Transfer Complete',13,10,'$'

abort	call	erxit
	DB	13,10,10,'Transfer Aborted',13,10,'$'

;-----------------------------------------------------------------------------
; calCrc - update the 16-bit CRC with one more byte. 
;    (Copied from M. Eberhard)
; On Entry:
;   a has the new byte
;   crc16 is current except this byte
; On Exit:
;   crc16 has been updated
;   Trashes a,de
;-----------------------------------------------------------------------------
calCrc	push	b		;save bc, hl
	push	h
	lhld	crc16		;get CRC so far
	xra	h		;XOR into CRC top byte
	mov	h,a
	lxi	b,1021h		;bc=CRC16 polynomial
	mvi	d,8		;prepare to rotate 8 bits

; do 8 bit shift/divide by CRC polynomial

cRotLp	dad	h		;16-bit shift
	jnc	cClr		;skip if bit 15 was 0
	mov	a,h		;CRC=CRC xor 1021H
	xra	b
	mov	h,a
	mov	a,l
	xra	c
	mov	l,a
cClr	dcr	d
	jnz	cRotLp		;rotate 8 times

; save the updated CRC and exit

	shld	crc16		;save updated CRC
	pop	h		;restore hl, bc
	pop	b
	ret

; Messages

mRcvA	db	'Start XMODEM file receive now...$'
mRcvB	db	'Start XMODEM file receive on modem port now...$'
mHelp	db	CR,LF,'PCPUT Ver 1.0 for Morrow Micro-Decision 2/3',CR,LF,LF
	db	'Transmits a file to a PC through a serial port',CR,LF
	db	'using the XMODEM protocol.',CR,LF,LF
	db	'Usage: PCPUT file.ext [B]',CR,LF
	db	'   Console port used by default',CR,LF
	db	'   Specify B to use modem port',CR,LF,'$'


; Data area

	DS	40	;STACK AREA
STACK	DS	2	;STACK POINTER
SECTNO	DS	1	;CURRENT SECTOR NUMBER 
ERRCT	DS	1	;ERROR COUNT
fPortB	ds	1	;flag to use modem port instead of console
crcFlag	ds	1	;non-zero if using CRC
crc16	ds	2	;computed crc
;
; BDOS EQUATES (VERSION 2)
;
RDCON	EQU	1
WRCON	EQU	2
PRINT	EQU	9
CONST	EQU	11	;CONSOLE STAT
OPEN	EQU	15	;0FFH=NOT FOUND
CLOSE	EQU	16	;   "	"
SRCHF	EQU	17	;   "	"
SRCHN	EQU	18	;   "	"
ERASE	EQU	19	;NO RET CODE
READ	EQU	20	;0=OK, 1=EOF
WRITE	EQU	21	;0=OK, 1=ERR, 2=?, 0FFH=NO DIR SPC
MAKE	EQU	22	;0FFH=BAD
REN	EQU	23	;0FFH=BAD
STDMA	EQU	26
BDOS	EQU	5
REIPL	EQU	0
FCB	EQU	5CH	;SYSTEM FCB
PARAM1	EQU	FCB+1	;COMMAND LINE PARAMETER 1 IN FCB
PARAM2	EQU	PARAM1+16	;COMMAND LINE PARAMETER 2
	END
