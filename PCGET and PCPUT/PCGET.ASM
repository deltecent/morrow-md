;
;  PCGET - This CP/M program receives a file from a PC via a serial 
;  port and writes it to a file on the CP/M system. The file transfer uses
;  the XMODEM protocol. 
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

;  Transfer related equates

SOH	EQU	1
EOT	EQU	4
ACK	EQU	6
NAK	EQU	15H
CTRLC	EQU	3		;Control-C
LF	EQU	10
CR	EQU	13

	ORG	100H

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
	lxi	d,mSendA	;port a send message
	lda	PARAM2		;A=1st character of parameter 2
	ani	5fh		;force upper case
	cpi	'B'		;port b specified?
	jnz	doXfer		;no, go do the transfer
	inr	b		;force flag to non-zero value
	lxi	d,mSendB	;port b send message
	
;  doXfer - Switch to local stack and do the transfer

doXfer	mov	a,b		;store the port b flag
	sta	fPortB
	LXI	H,0		;HL=0
	DAD	SP		;HL=STACK FROM CP/M
	SHLD	STACK		;..SAVE IT
	LXI	SP,STACK	;SP=MY STACK
	xra	a
	sta	SECTNO		;init sector number to zero
	MVI	C,PRINT		;print the send message
	CALL	BDOS		;PRINT ID MESSAGE

;  GOBBLE UP GARBAGE CHARS FROM THE LINE

purge	MVI	B,1		;times out after 1 second if no data
	CALL	RECV
	jc	RECEIVE$FILE	;line is clear, go receive the file
	cpi	ctrlc		;exit if abort requested
	jz	abort
	jmp	purge
;
;**************RECEIVE FILE****************
;
RECEIVE$FILE:
	CALL	ERASE$OLD$FILE
	CALL	MAKE$NEW$FILE
	MVI	A,NAK
	CALL	SEND		;SEND NAK

RECV$LOOP:
RECV$HDR:
	MVI	B,3		;3 SEC TIMEOUT
	CALL	RECV
	JNC	RHNTO		;NO TIMEOUT

RECV$HDR$TIMEOUT:
RECV$SECT$ERR:			;PURGE THE LINE OF INPUT CHARS
	MVI	B,1		;1 SEC W/NO CHARS
	CALL	RECV
	JNC	RECV$SECT$ERR 	;LOOP UNTIL SENDER DONE
	MVI	A,NAK
	CALL	SEND		;SEND NAK
	JMP	RECV$HDR

;GOT CHAR - MUST BE SOH OR CTRL-C TO ABORT

RHNTO:	CPI	SOH
	JZ	GOT$SOH
	cpi	ctrlc		;control-c to abort?
	jz	abort
	CPI	EOT
	JZ	GOT$EOT
	JMP	RECV$SECT$ERR

GOT$SOH:
	MVI	B,1
	CALL	RECV
	JC	RECV$HDR$TIMEOUT
	MOV	D,A		;D=BLK #
	MVI	B,1
	CALL	RECV		;GET CMA'D SECT #
	JC	RECV$HDR$TIMEOUT
	CMA
	CMP	D		;GOOD SECTOR #?
	JZ	RECV$SECTOR
	JMP	RECV$SECT$ERR

;  Receive Sector

RECV$SECTOR:
	MOV	A,D		;GET SECTOR #
	STA	RSECTNO
	MVI	C,0		;INIT CKSUM
	LXI	H,80H		;POINT TO BUFFER
RECV$CHAR:
	MVI	B,1		;1 SEC TIMEOUT
	CALL	RECV		;GET CHAR
	JC	RECV$HDR$TIMEOUT
	MOV	M,A		;STORE CHAR
	INR	L		;DONE?
	JNZ	RECV$CHAR

;VERIFY CHECKSUM

	MOV	D,C		;SAVE CHECKSUM
	MVI	B,1		;TIMEOUT
	CALL	RECV		;GET CHECKSUM
	JC	RECV$HDR$TIMEOUT
	CMP	D		;CHECK
	JNZ	RECV$SECT$ERR
;
;GOT A SECTOR, WRITE IF = 1+PREV SECTOR
;
	LDA	RSECTNO
	MOV	B,A		;SAVE IT
	LDA	SECTNO		;GET PREV
	INR	A		;CALC NEXT SECTOR #
	CMP	B		;MATCH?
	JNZ	DO$ACK

;GOT NEW SECTOR - WRITE IT

	LXI	D,FCB
	MVI	C,WRITE
	CALL	BDOS
	ORA	A
	JNZ	WRITE$ERROR
	LDA	RSECTNO
	STA	SECTNO		;UPDATE SECTOR #
DO$ACK	MVI	A,ACK
	CALL	SEND
	JMP	RECV$LOOP

WRITE$ERROR:
	CALL	ERXIT
	DB	13,10,10,'Error Writing File',13,10,'$'

GOT$EOT:
	MVI	A,ACK		;ACK THE EOT
	CALL	SEND
	LXI	D,FCB
	MVI	C,CLOSE
	CALL	BDOS
	INR	A
	JNZ	XFER$CPLT
	CALL	ERXIT
	DB	13,10,10,'Error Closing File',13,10,'$'
;
ERASE$OLD$FILE:
	LXI	D,FCB
	MVI	C,SRCHF		;SEE IF IT EXISTS
	CALL	BDOS
	INR	A		;FOUND?
	RZ			;NO, RETURN
ERAY:	LXI	D,FCB
	MVI	C,ERASE
	CALL	BDOS
	RET
;
MAKE$NEW$FILE:
	LXI	D,FCB
	MVI	C,MAKE
	CALL	BDOS
	INR	A		;FF=BAD
	RNZ			;OPEN OK

;DIRECTORY FULL - CAN'T MAKE FILE
	CALL	ERXIT
	DB	13,10,10,'Error - Can''t Make File',13,10
	DB	'(directory must be full)',13,10,'$'
;
; S U B R O U T I N E S
;
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
MSEC	lxi	d,(159 shl 8)	;49 cycle loop, 6.272ms/wrap * 159 = 1 second
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
	cpi	ctrlc		;is it a Ctrl-C?
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

mSendA	db	'Send the file now using XMODEM...$'
mSendB	db	'Send the file now using XMODEM on modem port...$'
mHelp	db	CR,LF,'PCGET Ver 1.0 for Morrow Micro-Decision 2/3',CR,LF,LF
	db	'Usage: PCGET file.ext [B]',CR,LF
	DB	'       (B specifies modem port for transfer)',CR,LF,'$'

;DONE - CLOSE UP SHOP

XFER$CPLT:
	CALL	ERXIT
	DB	13,10,10,'Transfer Complete',13,10,'$'

abort:	call	erxit
	db	13,10,10,'Transfer Aborted',13,10,'$'

	DS	40	;STACK AREA
STACK	DS	2	;STACK POINTER
RSECTNO	DS	1	;RECEIVED SECTOR NUMBER
SECTNO	DS	1	;CURRENT SECTOR NUMBER 
fPortB	ds	1	;flag to use modem port instead of console
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
FCB	EQU	5CH	;DEFAULT FCB
PARAM1	EQU	FCB+1	;COMMAND LINE PARAMETER 1 IN FCB
PARAM2	EQU	PARAM1+16	;COMMAND LINE PARAMETER 2
	END
