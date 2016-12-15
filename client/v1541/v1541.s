
.include "../inc/common.i"
.ifndef KPR_API_VERSION_NUMBER
  .define EQU     =
  .include "../inc/kipper_constants.i"
.endif


SERVER_PORT=1541
.define SERVERNAME  "COMMODORESERVER.COM"

.import ip65_init
.import dhcp_init
.import tcp_connect
.import dns_resolve
.import dns_set_hostname
.import dns_ip
.import	print_a
.import tcp_connect_ip
.import tcp_send
.import tcp_send_data_len
.import tcp_send_string
.import tcp_connect
.import tcp_close
.import tcp_callback
.import ip65_process
.import ip65_error
.import tcp_state
.import copymem
.import check_for_abort_key
.import tcp_inbound_data_ptr
.import tcp_inbound_data_length
.import tcp_send_keep_alive  
.import get_key
.importzp copy_src
.importzp copy_dest
.export keep_alive_counter
pptr=copy_src
IERROR=$300
CINV=$314
ILOAD=$330
ISAVE=$332

FNLEN		=	$B7
FNADDR		=	$BB
CHRGOT=$79
TXTPTR=$7A
MEMSIZ	=	$37		;highest address used by BASIC
.import __CODE_LOAD__
.import __CODE_RUN__
.import __CODE_SIZE__

.import __RODATA_LOAD__
.import __RODATA_RUN__
.import __RODATA_SIZE__

.import __DATA_LOAD__
.import __DATA_RUN__
.import __DATA_SIZE__

.import __IP65_DEFAULTS_LOAD__
.import __IP65_DEFAULTS_RUN__
.import __IP65_DEFAULTS_SIZE__

.import __CODESTUB_LOAD__
.import __CODESTUB_RUN__
.import __CODESTUB_SIZE__

.segment "STARTUP"    ;this is what gets put at the start of the file on the C64
.word basicstub		; load address
basicstub:
	.word @nextline
	.word 10    ;line number
	.byte $9e     ;SYS
	.byte <(((relocate / 1000) .mod 10) + $30)
	.byte <(((relocate / 100 ) .mod 10) + $30)
	.byte <(((relocate / 10  ) .mod 10) + $30)
	.byte <(((relocate       ) .mod 10) + $30)
	.byte 0
@nextline:
	.word 0  
relocate:  

  ldax  #$9000
  stax  $37; MEMSIZ
  jsr $A65E ;do a CLR

  ;relocate everything
	ldax #__CODE_LOAD__
	stax copy_src
	ldax #__CODE_RUN__
	stax copy_dest
	ldax #__CODE_SIZE__
	jsr __copymem
	
  
	ldx ILOAD+1
  cpx #>load_handler
	bne	@not_installed
	ldax #@already_installed_msg    
	jsr	__print
	rts
  
  @installed_msg: .byte "V1541 INSTALLED",0
  @already_installed_msg: .byte "V1541 ALREADY INSTALLED",0
@not_installed:

  
	ldax #__DATA_LOAD__
	stax copy_src
	ldax #__DATA_RUN__
	stax copy_dest
	ldax #__DATA_SIZE__
	jsr __copymem
	
	ldax #__CODESTUB_LOAD__
	stax copy_src
	ldax #__CODESTUB_RUN__
	stax copy_dest
	ldax #__CODESTUB_SIZE__
	jsr __copymem
	
	ldax #__RODATA_LOAD__
	stax copy_src
	ldax #__RODATA_RUN__
	stax copy_dest
	ldax #__RODATA_SIZE__
	jsr __copymem
	
	ldax #__IP65_DEFAULTS_LOAD__
	stax copy_src
	ldax #__IP65_DEFAULTS_RUN__
	stax copy_dest
	ldax #__IP65_DEFAULTS_SIZE__
	jsr __copymem
	

  
	
  jsr	swap_basic_out
  
	jsr	ip65_init
  bcc @init_ok
  ldax #@no_nic
  jsr	print
@fail_and_exit:
  ldax #@not_installed_msg
  jsr print
  jmp	@done
@no_nic: .byte "NO RR-NET FOUND - ",0
@not_installed_msg: .byte "V1541 NOT INSTALLED.",0  
@init_ok:
  ldax #@dhcp_init_msg
  jsr print
	jsr	dhcp_init
  bcc @dhcp_worked
@failed:  
  ldax #@fail_msg
  jsr print
  jmp @fail_and_exit
@dhcp_init_msg: .byte "DHCP INITIALISATION"
@elipses: .byte "...",0
@ok_msg: .byte "OK",13,0
@fail_msg: .byte "FAILED",13,0
@dhcp_worked:  
  ldax #@ok_msg  
  jsr print
  
  ldax #@resolve_servername_msg
  jsr print
  ldax  #@elipses
  jsr print
  ldax #@servername
  jsr dns_set_hostname
  jsr dns_resolve  
  bcc @dns_worked
  jmp @failed
@resolve_servername_msg: .byte "RESOLVING "
@servername: .byte SERVERNAME,0
@dns_worked:
  ldax #@ok_msg  
  jsr print
  ldx #3
@copy_server_ip_loop:
  lda dns_ip,x
  sta tcp_connect_ip,x
  dex
  bpl @copy_server_ip_loop

  ldax #@connecting_msg
  jsr print
  ldax #@servername
  jsr print
  ldax  #@elipses
  jsr print
  ldax  #csip_callback
  stax  tcp_callback
  ldax #SERVER_PORT  
  jsr tcp_connect
  bcc @connect_worked
  jmp @failed
@connecting_msg:  .byte "CONNECTING TO ",0

@connect_worked:  
  ldax #@ok_msg  
  jsr print
  ;IP stack OK, now set vectors  
  
  ldax CINV
  stax  old_irq_vector
  
	ldax ILOAD
	stax old_load_vector	
	ldax #load_handler
	stax ILOAD
	ldax #@installed_msg
	jsr	print

ldax #irq_handler
  sei
  stax CINV  
  
@done:	
	jsr	swap_basic_in
  lda #0
  sta $dc08 ;make sure TOD clock is started
  cli

  rts
	
__copymem:
	sta end
	ldy #0

	cpx #0
	beq @tail

:	lda (copy_src),y
	sta (copy_dest),y
	iny
	bne :-
  inc copy_src+1    ;next page
  inc copy_dest+1  ;next page
	dex
	bne :-

@tail:
	lda end
	beq @done

:	lda (copy_src),y
	sta (copy_dest),y
	iny
	cpy end
	bne :-

@done:
	rts

end: .byte 0	

__print:
	sta pptr
	stx pptr + 1
	
@print_loop:
  ldy #0
  lda (pptr),y
	beq @done_print  
	jsr print_a
	inc pptr
	bne @print_loop
  inc pptr+1
  bne @print_loop ;if we ever get to $ffff, we've probably gone far enough ;-)
@done_print:
  rts


.code

load_dev_2:
  ldy #$00
  sty receive_type ;0 = display to screen, 1 = load to memory
  sty buffer_length
  sty buffer_length+1
  lda (FNADDR),y
  cmp #'!'
  beq @do_disks
  cmp #'>'
  beq @do_command
  cmp #'#'  
  beq @do_insert
  cmp #'='
  beq @do_find
  cmp #'/'
  bne @not_cf  
  lda FNLEN
  cmp #1
  bne @do_cf
  ldax #cmd_cf_root
  jmp @send_string_receive_response
@not_cf:
  cmp #'%'
  beq @do_name
  cmp #'$'
  beq @do_cat
  inc receive_type
  ldax #cmd_load
  jmp @copy_prefix
  
@done:

  clc  
	jmp	swap_basic_in

@do_command:
  ldy FNLEN
@copy_cmd:
  lda (FNADDR),y
  sta cmd_buffer-1,y
  dey
  bne @copy_cmd
  
  ldy FNLEN
  lda #$0D
  sta cmd_buffer-1,y
  lda #0
  sta cmd_buffer,y
@send_command_buffer:  
  ldax #cmd_buffer
  jmp @send_string_receive_response

@do_name:
  ldax #cmd_name
  jmp @send_string_receive_response

@do_find:
  ldax #cmd_find
  jmp @copy_prefix

@do_cat:
  ldax #cmd_cat
  jmp @send_string_receive_response


@do_disks:
	ldax	  #cmd_dsks
@send_string_receive_response:
  jsr tcp_send_string	
  bcs @error
  lda receive_type
  bne @load_file
	jsr show_list  
	jmp @done
@load_file:
	jsr receive_file
	jmp @done
  
@do_cf:
  ldax #cmd_cf
  jmp @copy_prefix


@do_insert:
  ldax #cmd_insert
@copy_prefix:  
  stax copy_src  
  ldy #0  
@copy_prefix_loop:  
  lda (copy_src),y
  beq @end_copy_prefix
  sta cmd_buffer,y
  iny
  bne @copy_prefix_loop
@end_copy_prefix:  
  tya
  tax
  ldy #1
  lda receive_type
  beq :+
  dey ;if this is a LOAD command, don't skip the first byte
:  
  lda (FNADDR),y  
  sta cmd_buffer,x
  iny
  inx
  cpy FNLEN
  
  bne :-
  
  lda #$0D
  sta cmd_buffer,x
  lda #0
  sta cmd_buffer+1,x
  jmp @send_command_buffer

@error:
  ldax #SERVER_PORT  
  jsr tcp_connect  

  ldax #transmission_error
  jsr print
  
  jmp @done


show_list:  
  
@loop:
  lda $91     ; look for STOP key
  cmp #$7F
  beq @done
  lda #2 ;wait for max 2 seconds
  jsr getc
  bcc @got_data
  rts
@got_data:

  cmp #$03		;ETX byte (indicating end of page)?
  beq @get_user_input
  cmp #$04		;EOT byte (indicating end of list)?
  beq @done
	jsr print_a	;got a byte - output it
  jmp @loop ;continue getting characters

;End of page, so ask for user input
 @get_user_input:
 
  jsr get_key
  
  cmp #'S'
  beq @user_exit

  cmp #$0D
  bne @get_user_input
  ldax #continue_cmd

  jsr tcp_send_string
  jmp @loop

;User wishes to stop - send S to server and quit
@user_exit:
  ldax  #stop_cmd  
  jsr tcp_send_string

@done:

rts


print:
	sta pptr
	stx pptr + 1
	
@print_loop:
  ldy #0
  lda (pptr),y
	beq @done_print  
	jsr print_a
	inc pptr
	bne @print_loop
  inc pptr+1
  bne @print_loop ;if we ever get to $ffff, we've probably gone far enough ;-)
@done_print:
  rts


csip_callback:
  lda tcp_inbound_data_length+1
  cmp #$ff
  bne @not_eof
  rts
@not_eof:
  
  ldax tcp_inbound_data_ptr
  stax copy_src
  ldax #csip_stream_buffer
  stax copy_dest
  stax next_char_ptr

  ldax tcp_inbound_data_length
  stax buffer_length
  jsr copymem
  rts

getc:
  sta getc_timeout_seconds

  clc
  lda $dc09  ;time of day clock: seconds (in BCD)
  sed
  adc getc_timeout_seconds
  cmp #$60
  bcc @timeout_set
  sec
  sbc #$60
@timeout_set:  
  cld
  sta getc_timeout_end  

@poll_loop: 
  jsr next_char
  bcs @no_char
  rts ;done!
@no_char:  
  jsr check_for_abort_key
  bcc @no_abort
  lda #KPR_ERROR_ABORTED_BY_USER
  sta ip65_error
  inc user_abort
  rts
@no_abort:  
  jsr ip65_process
  lda $dc09  ;time of day clock: seconds
  cmp getc_timeout_end  
  bne @poll_loop
  lda #00
  sec
  rts

next_char:
  lda buffer_length
  bne @not_eof
  lda buffer_length+1
  bne @not_eof
  sec
  rts
@not_eof:  
  next_char_ptr=*+1
  lda $ffff
  pha
  inc next_char_ptr
  bne :+
  inc next_char_ptr+1
:  
  sec
  lda   buffer_length
  sbc #1
  sta   buffer_length
  lda   buffer_length+1
  sbc #0
  sta   buffer_length+1
  pla
  clc  
  
  rts

tcp_irq_handler:

  inc keep_alive_counter
  lda keep_alive_counter
  bne @skip
  jsr tcp_send_keep_alive  
@skip:  
  jsr ip65_process
@done:  

  rts

receive_file:
  lda #0
  sta byte_count
@loop:
  lda $91     ; look for STOP key
  cmp #$7F
  beq @done
  lda #2 ;wait for max 2 seconds
  jsr getc  
  bcc @got_data
@done:  
  rts
@got_data:
  ldy byte_count
  sta file_length,y
  inc byte_count
  lda byte_count
  cmp #4
  bne @loop
  ;is the first 4 bytes "500 "  
;  
  lda file_length+1
  cmp  #'0'   ;if 2nd char was '0' this might be an ASCII error message
  bne @real_file_transmission
  lda file_location
  cmp  #$01 
  beq @real_file_transmission
  ;this was probably an ASCII error message
  
  lda #0
  sta byte_count
:
  ldy byte_count
  lda file_length,y
  jsr print_a
  inc byte_count
  lda byte_count
  cmp #4
  bne :-
  jmp show_list
@real_file_transmission:
  ldax file_location
  stax  copy_dest

  lda file_length
  sec
  sbc #2  
  sta file_length
  
  lda file_length+1
  sbc #0
  sta file_length+1
  
@rx_loop:
  lda file_length+1
  bne @not_done
  lda file_length
  bne @not_done
  ;file now fully in RAM, time for housekeeping
  sta $297  ;RS-232 status = 0 (no error)
  sta $90   ;status = 0 (no error)
  ldy copy_dest+1 ;high byte of end of loaded program
  ldx copy_dest     ;lo byte of end of loaded program
  inx
  bne :+
  iny                   ;if X rolled over, bump y
:  
  rts         ;done!
  
@not_done:  
  lda #2 ;wait for max 2 seconds
  jsr getc  
  bcs @rx_error
  ldy #0
  sta (copy_dest),y
  inc copy_dest
  bne :+
  inc copy_dest+1
:  
 lda  file_length
 bne :+
  dec file_length+1
  lda #'.'
  jsr print_a
:
  dec file_length
  jmp @rx_loop
  
@rx_error:
  ldax  #receive_error
  jmp print

.segment "CODESTUB"

swap_basic_out:
	lda $01
  sta underneath_basic
	and #$FE
	sta $01
	rts

swap_basic_in:
	lda $01
	ora #$01
	sta $01
  lda #$0  
  sta underneath_basic
	rts

underneath_basic: .res 1

load_handler:
	ldx $BA       ; Current Device Number
	cpx	#$02
	beq	:+
	.byte $4c	;jmp
old_load_vector:	
	.word	$ffff	
	:
	jsr	swap_basic_out
	jmp	load_dev_2

irq_handler:
  
  lda underneath_basic  
  bne @done 
  jsr swap_basic_out
  jsr tcp_irq_handler
  jsr	swap_basic_in
@done:  
	.byte $4c	;jmp
old_irq_vector:	
	.word	$ffff	


.data
cmd_dsks:  .byte "DISKS 22",$0d,$0
cmd_insert: .byte "INSERT ",0
cmd_cat:  .byte "$",$0d,$00
cmd_find: .byte "FIND ",$00
cmd_name: .byte "NAME",$0d,$00
cmd_cf:   .byte "CF ",0
cmd_load:   .byte "LOAD ",0
cmd_cf_root: .byte "CF /",$0d,0

transmission_error: .byte "TRANSMIT ERROR",13,0
receive_error: .byte "RECEIVE ERROR",13,0

.segment "TCP_VARS"
csip_stream_buffer: .res 1500
cmd_buffer: .res 100
.bss

user_abort: .res 1
getc_timeout_end: .res 1
getc_timeout_seconds: .res 1
buffer_length: .res 2  
keep_alive_counter: .res 1
file_length: .res 2
file_location: .res 2
rx_length: .res 2
receive_type: .res 1
byte_count: .res 1
.data
continue_cmd: .byte $0D,0
stop_cmd: .byte "S",0


;-- LICENSE FOR v1541.s --
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
; The Original Code is ip65.
; 
; The Initial Developer of the Original Code is Jonno Downes,
; jonno@jamtronix.com.
; Portions created by the Initial Developer are Copyright (C) 2010
; Jonno Downes. All Rights Reserved.  
; -- LICENSE END --
