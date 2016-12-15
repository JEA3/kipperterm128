;use the NB65 API to send a d64 disk via TFTP
;
;

.ifndef NB65_API_VERSION_NUMBER
  .define EQU     =
  .include "../inc/nb65_constants.i"
.endif

.include "../ip65/copymem.s"
.include "../inc/common.i"

.import print_a
.import get_key
.import get_filtered_input
.import filter_dns
.macro cout arg
  lda arg
  jsr print_a
.endmacro   

;######### KERNEL functions
CHKIN   = $ffc6
CHKOUT  = $ffc9
CHRIN = $ffcf
CHROUT  = $ffd2
CLALL = $FFE7
CLOSE = $ffc3
OPEN = $ffc0
READST = $ffb7
SETNAM = $ffbd
SETLFS = $ffba

.bss
 current_byte: .res 1
 track:  .res 1
 sector: .res 1
 sectors_in_track: .res 1
 error_buffer: .res 128
 
 command_buffer: .res 128
 sector_buffer: .res 256
 nb65_param_buffer: .res $20  
sector_buffer_address: .res 2

  .zeropage
  temp_ptr:		.res 2
  
.segment "STARTUP"    ;this is what gets put at the start of the file on the C64

.word basicstub		; load address

.macro print arg
  ldax arg
	ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 
.endmacro 

.macro print_cr
  lda #13
	jsr print_a
.endmacro

.macro call arg
	ldy arg
  jsr NB65_DISPATCH_VECTOR   
.endmacro

basicstub:
	.word @nextline
	.word 2003
	.byte $9e 
	.byte <(((init / 1000) .mod 10) + $30)
	.byte <(((init / 100 ) .mod 10) + $30)
	.byte <(((init / 10  ) .mod 10) + $30)
	.byte <(((init       ) .mod 10) + $30)
	.byte 0
@nextline:
	.word 0


;look for NB65 signature at location pointed at by AX
look_for_signature: 
  stax temp_ptr
  ldy #3
@check_one_byte:
  lda (temp_ptr),y
  cmp nb65_signature,y
  bne @bad_match  
  dey 
  bpl@check_one_byte  
  clc
  rts
@bad_match:
  sec
  rts
init:

  print #signon_message

  ldax #NB65_CART_SIGNATURE  ;where signature should be in cartridge
  jsr  look_for_signature
  bcc @found_nb65_signature

  ldax #NB65_RAM_STUB_SIGNATURE  ;where signature should be in RAM
  jsr  look_for_signature
  bcc :+
  jmp nb65_signature_not_found
:  
  jsr NB65_RAM_STUB_ACTIVATE     ;we need to turn on NB65 cartridge
  
@found_nb65_signature:

  print #initializing
  print #nb65_signature
  ldy #NB65_INITIALIZE
  jsr NB65_DISPATCH_VECTOR 
	bcc :+  
  print #failed
  jsr print_nb65_errorcode
  jmp bad_boot    
:  
  print #ok
  print_cr
    
; ######################## 
; main program goes here:
; 

  jsr CLALL


;  ldx #18
;  stx track
;  ldx #1
;  stx sector
;  ldx #21
;  stx sectors_in_track
;  ldax #sector_buffer
;  jsr send_next_block
;  rts
  

@send_1_image:
  lda #$93  ;cls
  jsr print_a
  print #signon_message
  jsr reset_counters_to_first_sector
  print #enter_filename
  ldax #filter_dns  ;this is pretty close to being a filter for legal chars in file names as well
  jsr get_filtered_input
  bcs @no_filename_entered
  stax nb65_param_buffer+NB65_TFTP_FILENAME
  print #position_cursor_for_track_display
  ldax #send_next_block
  stax nb65_param_buffer+NB65_TFTP_POINTER
  ldax #nb65_param_buffer
  call #NB65_TFTP_CALLBACK_UPLOAD
  bcc :+
  print_cr
  print #failed
  jmp print_nb65_errorcode
:
  lda #15      ; filenumber 15 - command channel
  jsr CLOSE
  print_cr
  print #ok
  print  #press_a_key_to_continue
  jsr get_key
  jmp @send_1_image ;done! so go again
@no_filename_entered:
  rts


send_next_block:
;tftp upload callback routine
;AX will point to address to fill
  stax  sector_buffer_address
  lda track
  cmp #36
  beq @past_last_track
  print #position_cursor_for_track_display
  jsr print_current_sector
  jsr read_sector
  lda #$30
  cmp error_buffer
  bne @was_an_error  
@after_error_check:
  jsr move_to_next_sector
  bcc @not_last_sector
  ldax  #$100
  rts
@not_last_sector:
  
;  jsr dump_sector ;DEBUG

  inc sector_buffer_address+1
  jsr read_sector
  jsr move_to_next_sector
  ldax  #$200
  
;  jsr dump_sector ;DEBUG
  
  rts
@past_last_track:
  ldax  #$0000
  rts

@was_an_error:
  print #position_cursor_for_error_display
  print #drive_error
  print_cr
  jsr print_current_sector
  print #error_buffer
  jmp @after_error_check

print_current_sector:
  print #track_no
  lda track
  jsr byte_to_ascii
  pha
  txa
  jsr print_a
  pla
  jsr print_a
  print #sector_no
  lda sector
  jsr byte_to_ascii
  pha
  txa
  jsr print_a
  pla
  jsr print_a
  print_cr
  rts


  
dump_sector:
;hex dump sector
  lda #0
  sta current_byte
@dump_byte:
  ldy current_byte
  lda sector_buffer,y
  call #NB65_PRINT_HEX
  inc current_byte
  bne @dump_byte
rts

read_sector:
;routine to read a sector cribbed from http://codebase64.org/doku.php?id=base:reading_a_sector_from_disk
; - requires track and sector values be set first
; sector will be written to address whos value is stored in sector_data
; open the channel file

  jsr make_read_sector_command
  
  lda #1
  ldx #<cname
  ldy #>cname
  jsr SETNAM
  lda #02
  ldx #08
  ldy #02
  jsr SETLFS
  jsr OPEN
  bcs @error
  ldx #<command_buffer
  ldy #>command_buffer
  lda #12
  jsr SETNAM
  lda #15
  ldx $BA ;use whatever was last device #
  ldy #15
  jsr SETLFS
  jsr OPEN
  bcs @error
  
  
  jsr check_error_channel
  lda #$30
  cmp error_buffer
  beq @was_not_an_error  
  print #error_buffer
  
 @was_not_an_error:
  ldx #$02      ; filenumber 2
  jsr CHKIN ;(file 2 now used as input)

  lda sector_buffer_address
  sta temp_ptr
  lda sector_buffer_address+1
  sta temp_ptr+1
  ldy #$00
@loop:
  jsr CHRIN ;(get a byte from file)
  sta (temp_ptr),Y   ; write byte to memory
  iny
  bne @loop     ; next byte, end when 256 bytes are read
@close:
  lda #15      ; filenumber 15
  jsr CLOSE
  lda #$02      ; filenumber 2
  jsr CLOSE
  ldx #$00      ; filenumber 0 = keyboard
  jsr CHKIN ;(keyboard now input device again)
  rts
@error:
  pha
  print #error_opening_channel
  pla
  call #NB65_PRINT_HEX
  jmp @close

check_error_channel:
  LDX #$0F      ; filenumber 15
  JSR CHKIN ;(file 15 now used as input)
  LDY #$00
@loop:
  JSR READST ;(read status byte)
  BNE @eof      ; either EOF or read error
  JSR CHRIN ;(get a byte from file)
  sta error_buffer,y
  iny
  JMP @loop     ; next byte

@eof:
  lda #0
  sta error_buffer,y
  LDX #$00      ; filenumber 0 = keyboard
  JSR CHKIN ;(keyboard now input device again)
  RTS
  
bad_boot:
  print  #press_a_key_to_continue
restart:    
  jsr get_key
  jmp $fce2   ;do a cold start


print_a_as_errorcode:
  pha
  lda #' '
  jsr print_a
  print #error_code
  pla
  call #NB65_PRINT_HEX
  rts

print_nb65_errorcode:
  print #error_code
  call #NB65_GET_LAST_ERROR
  call #NB65_PRINT_HEX
  print_cr
  rts

nb65_signature_not_found:

  ldy #0
:
  lda nb65_signature_not_found_message,y
  beq restart
  jsr print_a
  iny
  jmp :-



make_read_sector_command:
;fill command buffer with command to read in track & sector 
;returns length of command in Y

  ldy #0
  lda #85 ;"U"
  sta command_buffer,y
  iny
  lda #$31 ;"1" 
  sta command_buffer,y
  iny
  lda #$20 ;" "
  sta command_buffer,y
  iny
  lda #$32 ;"2" - file number
  sta command_buffer,y
  iny
  lda #$20 ;" "
  sta command_buffer,y
  iny
  lda #$30 ;"0" - drive number
  sta command_buffer,y
  iny
  lda #$20 ;" "
  sta command_buffer,y
  iny
  lda track
  jsr byte_to_ascii
  pha
  txa
  sta command_buffer,y
  pla
  iny
  sta command_buffer,y
  iny
  lda #$20 ;" "
  sta command_buffer,y
  iny
  lda sector
  jsr byte_to_ascii
  pha
  txa
  sta command_buffer,y
  pla
  iny
  sta command_buffer,y
  iny
  
  lda #0
  sta command_buffer,y  ;make it ASCIIZ so we can print it
  
  rts

byte_to_ascii:
  cmp #30
  bmi @not_30
  ldx #$33
  clc
  adc #18
  rts
@not_30:  
  cmp #20
  bmi @not_20
  ldx #$32
  clc
  adc #28
  rts
@not_20:
  cmp #10  
  bmi @not_10
  ldx #$31
  clc
  adc #38
  rts
@not_10:
  ldx #$30
  clc
  adc #48
  rts
 

reset_counters_to_first_sector:
  ldx #1
  stx track
  dex
  stx sector
  ldx #21
  stx sectors_in_track
  rts
  
move_to_next_sector:
  inc sector
  lda sector
  cmp sectors_in_track
  beq @move_to_next_track
  rts
@move_to_next_track:
  lda #0
  sta sector
  inc track
  lda track
  cmp #18
  bne @not_track_18
  lda #19
  sta sectors_in_track
  clc
  rts
@not_track_18:
  cmp #25
  bne @not_track_25
  lda #18
  sta sectors_in_track
  clc
  rts
@not_track_25:
  cmp #31
  bne @not_track_31
  lda #17
  sta sectors_in_track
  clc
  rts
@not_track_31:
  lda track
  cmp #36 ;carry will be set if hit track 36
  rts
  

.rodata

error_code:  
  .byte "ERROR CODE: $",0
press_a_key_to_continue:
  .byte "PRESS A KEY TO CONTINUE",13,0

failed:
	.byte "FAILED ", 0

ok:
	.byte "OK ", 0
  
initializing:  
  .byte "INITIALIZING ",0
track_no:
  .byte "TRACK ",0


sector_no:
  .byte " SECTOR ",0
  
signon_message:
  .byte "D64 UPLOADER V0.1",13,0

enter_filename:
.byte "SEND AS: ",0

drive_error:
  .byte "DRIVE ACCESS ERROR - ",0
 nb65_signature_not_found_message:
 .byte "NO NB65 API FOUND",13,"PRESS ANY KEY TO RESET", 0
 error_opening_channel:
  .byte "ERROR OPENING CHANNEL $",0
 
disk_access:
.byte 13,13,13,13,13,"SENDING TO CHANNEL $",0

nb65_signature:
  .byte $4E,$42,$36,$35  ; "NB65"  - API signature
  .byte ' ',0 ; so we can use this as a string
position_cursor_for_track_display:
;  .byte $13,13,13,13,13,13,13,13,13,13,13,"      SENDING ",0
.byte $13,13,13,"SENDING ",0
position_cursor_for_error_display:
  .byte $13,13,13,13,"LAST ",0

cname: .byte '#'  
;-- LICENSE FOR d64_upload.s --
; The contents of this file are subject to the Mozilla Public License
; Version 1.1 (the "License"); you may not use this file except in
; compliance with the License. You may obtain a copy of the License at
; http://www.mozilla.org/MPL/
; 
; Software distributed under the License is distributed on an "AS IS"
; basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
; License for the specific language governing rights and limitations
; under the License.
; 
; The Original Code is netboot65.
; 
; The Initial Developer of the Original Code is Jonno Downes,
; jonno@jamtronix.com.
; Portions created by the Initial Developer are Copyright (C) 2009
; Jonno Downes. All Rights Reserved.  
; -- LICENSE END --
