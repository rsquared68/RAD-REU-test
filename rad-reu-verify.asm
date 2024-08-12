// rjr tries to learn reu programming to verify rad dma integrity 2024-08-09
//
// 	v240811 add some #define switches, incorporate includes/macros, docs, etc. for lemon64 users
//
// 	I've tried most REU test programs and found them to be inconsistent in error reporting for the frenetic RAD I assembled:
//
// 	Gum+Pan/Alter tester	https://csdb.dk/release/?id=172121					always reports an error or crashes on start
//	REU tools Walt/Bonzai	https://csdb.dk/release/?id=198460					never reports an error
//	CBM Test/Demo Disk 1.0	https://www.zimmers.net/anonftp/pub/cbm/demodisks/other/index.html	never reports an error
//	CMD 1750XL disk		https://www.zimmers.net/anonftp/pub/cbm/demodisks/cmd/index.html	reports an error every 15 minutes of run time
//	MemTest64 Rosettif	https://csdb.dk/release/?id=158763					never reports an error
//
//	Tentative/early observation was that most testers don't find the error because 1) it's infrequent, perhaps 1 per hour, and
//	2) some errors are not real; REU contents are good but the very first byte or two verified fails.  The CMD tester is "the best" in this
//	regard because it takes 15 min to fully test a 8MB REU and there is a decent chance of fail during that time.  I think the Alter
//	tester might be good but something like the problem of "first byte(s) verified usually fails" is killing it.
//
//	The errors with the RAD are generally not fatal (if they are even real)--I have been able to stream music, nuvies, play demos, Sonic, etc
//	for long periods of time and I don't notice issues, though e.g. BluREU will eventually crash if loop it for a few hours.
//
//	This program is pretty simple.  It just copies the contents of one address on the C64 side to an entire bank of 64k on the REU side,
//	then uses the verify function of the REU to check.  If the VIC display is enabled (see #defines) the first byte of screen memory will
//	count up the 256 banks as they are filled, then the second byte will count up the banks as they are verified. If any bank fails verification,
//	the third byte of screen memory shows the error count. The 5th-11th bytes show the hex REU address of the last error in inverse video but
//	only after an error has occured. If you run this on a perfect system or emulator, you will never see that hex address poked to the screen.
//
//	Anecdotally (no detailed evidence yet), I think I observe four distinct types of errors
//
//	1) Fails on early byte of first verify e.g. 00:0001, 00:0002 etc, and fine after that. The frequency of this error type may depend on the
//	   RAD cache/preload settings.  Preliminary investigation shows that the RAD memory contents are good, so the verify itself is failing.
//	   This is a very common error and with default RAD settings on a few of my machines it happens more than 30% of the time.
//	2) Fails when VIC is active.  Probably RAD did not respect VIC BA signal assertion on a badline, and this probably can be fixed with some
//	   timing adjustment in rad.cfg.  I only studied this fault with a Kawari, which might have nonstandard BA assert timing--though the overall
//	   error rate on a real VIC was similar.
//	3) Fails when using RAM but not ROM source address.  Probably some timing adjustment needed as well.  ROM probably puts data on the bus
//	   a bit later than RAM (didn't check with logic analyzer yet) so maybe RAD is a little late in sampling the data bus
//	4) Other infrequent error (less than 1 per every 2 hours).  I have only looked at one example in a dump of the RAD contents. There were
//	   two incorrect nybbles in two nearby bytes. In each a single bit (bit 3 or bit 0) was set when it should have been clear.
//
//	All but error type 1 above might be fixable just by tweaking the rad.cfg timing settings.  However, with hours between errors and
//	17 different parameters for preload/cache and bus timing, it's not really practical to do this by cut-and-try iteration alone. So I hope that
//	I can either figure out a systematic way to do it using just code to bang on the corner cases, or worst case with code like this plus a
//	logic analyzer triggering on the infrequent timing misses.  The vast majority of errors with the VIC off seem to occur in the first few bytes
//	of a verify when starting the verify on a new bank.
//
//	On my most stable machine in the least taxing configuration (ROM copy, VIC disabled) it might take *days* of continuous looping to catch
//	just a few errors so getting any meaningful error-rate statistics is very time-consuming.
//
//
//	To use:	Configure #defines and REU size below, assemble with KickAss and run it forever
//
//		If HALT_ON_ERROR defined, you can make a note of the displayed address, save the REU contents to RAD SD card for later investigation,
//		or just type RUN to re-start the test if you are trying to build a statistical sample. If HALT_ON_ERROR is not defined, you can
//		get an idea of the statistics from the contents of the the third screen byte $0402 or the contents of $1000 as they increment.
//
// ------------------------------------------------------------------------------

//		******	       define/undef these depending on how you want to use this program		*******

#undef		NO_VIC			// disables VIC display during transfer and verify to avoid possibility of collisions with char ptr dma etc
//#undef	SPRITE_DMA		// add some sprite dma to make the problem more difficult NOT IMPLEMENTED YET
#define		HALT_ON_ERR		// halts and return to BASIC via rts. this allows you to dump the RAD memory to its SD card to examine the fault
#define 	USE_RAM			// uses RAM instead of ROM--this can give dramatically different results if the RAD timing settings are marginal

.const NUMBER_OF_BANKS = 256		// set this or you will immediately see a verify error due address wrapping around and overwriting earlier banks
					// e.g. a 16MB REU has 256 64k banks.  I always test 256 or 128 because 8MB is the largest the CMD 1750XL test 
					// test program, and from the outset I wanted to validate what that particular program was telling me

// ------------------------------------------------------------------------------


// expand the original includes here to give lemon64 a flat file
// REU.asm includes Walt/Bonzai
.const REUStatus		= $df00
.const REUCommand		= $df01
.const REUC64			= $df02
.const REUREU			= $df04
.const REUTransLen		= $df07
.const REUIRQMask		= $df09
.const REUAddrMode		= $df0a
.const REUStatusFault = $20		// Error during compare
.const REUCMDExecute = $80+$10		// Start transfer/compare/swap without waiting for write to $ff00
.const REUCMDExecuteFF00 = $80		// Start transfer/compare/swap after write access to $ff00 (for using RAM below I/O area $d000-$dfff)
.const REUCMDAutoload = $20		// Restore address and length registers after execute
.const REUCMDTransToREU = 0		// Bit 0-1 : 00 = transfer C64 -> REU
.const REUCMDTransToC64 = 1		// Bit 0-1 : 01 = transfer REU -> C64
.const REUCMDSwap = 2			// Bit 0-1 : 10 = swap C64 <-> REU
.const REUCMDCompare = 3		// Bit 0-1 : 11 = compare C64 - REU
.const REUAddrFixedC64 = $80		// Bit 7 : C64 ADDRESS CONTROL  (1 = fix C64 address)
.const REUAddrFixedREU = $40		// Bit 6 : REU ADDRESS CONTROL  (1 = fix REU address)

// old rjr wait-frame macro
.macro WAIT_FRAME_A() {			//wait for a frame to elapse
		lda #$80
!w:					//wait until msbit of raster is clear
		bit $d011
		bne !w-					
!w:
		bit $d011		//wait until msbit of raster is set
		beq !w-
!w:					//wait until msbit of raster is clear
		bit $d011
		bne !w-	
}

// -----------------------------------------------------------------------------------------------------------------------------

.const BASICROM = $a000

.pc = $0801
BasicUpstart(init)

.pc = $0810 "main"
init:
		sei			//for delay macro, no kernal activity
		lda #0
		sta errorCount
		
		lda #$20
		ldx #40
!lp:		sta $400-1,x
		dex			//for option with HALT_ON_ERR, in case the user wants
		bne !lp-		//to restart from BASIC with RUN, clear the old data from the screen

fill:
#if NO_VIC
		lda $d011		//stop vic dma
		eor #$10
		sta $d011
#endif		

		
cfg_xfer:	// tiny bit of setup not done within loops below
		lda #0
		sta REUIRQMask
		
		lda #(REUAddrFixedC64)	//static address 64 side only, always writing from databyte to reu bank:0000
		sta REUAddrMode		//control register



		ldy #0			//count destination bank upwards, makes it easier when inspecting REU contents offline

set_loop:	// setup on each block ...........................................................................................

#if USE_RAM
		// fill bank with databyte from RAM address, contents = bank number
		lda #>dataByte
		sta REUC64+1
		lda #<dataByte
		sta REUC64		//point c64 address to dataByte
		sty dataByte		//put the bank number in the databyte
#else
		// fill all reu banks with data from ROM address
		lda #>BASICROM
		sta REUC64+1
		tya
		clc
		adc #<BASICROM
		sta REUC64		//point c64 address to BASIC+y
#endif

		lda #0
		sta REUTransLen		//this is absolutely necessary to reset on each iteration
		sta REUTransLen+1	//as on successful completion it always = 1 unless verify error
			
		sta REUREU		//if there was an error or wraparound the bank will be wrong (e.g. f8)
		sta REUREU+1		//if there was an error the address will be stuck					
		sty REUREU+2		//select bank number = iteration

		sty $400		//iteration to screen

		lda #(REUCMDExecute | REUCMDTransToREU)
		sta REUCommand		//fill reu bank with byte

		cpy #(NUMBER_OF_BANKS-1)
		beq verify
		iny
		jmp set_loop
		
		
		
verify:			
		ldy #0			//count destination bank upwards, makes it easier when inspecting REU contents offline
chk_loop:	// check each block     ...........................................................................................

#if USE_RAM
		lda #>dataByte
		sta REUC64+1
		lda #<dataByte
		sta REUC64		//point c64 address to dataByte
		sty dataByte		//put the bank number in the databyte
#else
		lda #>BASICROM
		sta REUC64+1
		tya
		clc
		adc #<BASICROM
		sta REUC64		//point c64 address to BASIC+y
#endif

		lda #0
		sta REUTransLen		//this is absolutely necessary to reset on each iteration
		sta REUTransLen+1	//as on successful completion it always = 1 unless verify error

		sta REUREU		//reset because due to wraparounds or errors this may have changed
		sta REUREU+1		
		sty REUREU+2		//select bank number = iteration

		sty $400+1		//and screen

		lda #(REUCMDExecute | REUCMDCompare)
		sta REUCommand		//verify
		lda REUStatus
		and #$20
		beq ok
		
nok:		inc errorCount
		jsr displayAddress	//uses A,Y because only Y contains accurate bank # due to wraparound
#if HALT_ON_ERR
		lda errorCount
		sta $400+2
		lda $d011		//errors are infrequent with vic and ram out of the picture so exit to BASIC for address
		ora #$10		//re-enable display
		sta $d011
		rts			
#endif

ok:		lda errorCount
		sta $400+2		
		cpy #(NUMBER_OF_BANKS-1)
		beq done
		iny
		jmp chk_loop

done:          // .................................................................................................................
#if NO_VIC		
		lda $d011
		eor #$10
		sta $d011
		jsr delay3sec		//so user can see result
#endif
		jmp fill


dataByte:	.byte 0

// ================================================================================================================================
delay3sec:
		ldx #151
!lp:		WAIT_FRAME_A()
		dex
		bne !lp-
		rts


displayAddress:	//bank in Y
		//lda REUREU+2		//bank hi, value in REU not reliable due to wraparound
		tya
		lsr
		lsr
		lsr
		lsr
		jsr toHexCode
		sta $400+4
		//lda REUREU+2
		tya
		and #$0f		//bank lo
		jsr toHexCode
		sta $400+5
		lda #$ba		// ':' inv
		sta $400+6
		
		lda REUREU+1		//addr hi
		lsr
		lsr
		lsr
		lsr
		jsr toHexCode
		sta $400+7
		lda REUREU+1
		and #$0f		//addr lo
		jsr toHexCode
		sta $400+8

		lda REUREU		//addr hi
		lsr
		lsr
		lsr
		lsr
		jsr toHexCode
		sta $400+9
		lda REUREU
		and #$0f		//addr lo
		jsr toHexCode
		sta $400+10
		rts
			
		
toHexCode:	//value in A
		cmp #$0a
		bcs alpha
		clc
		adc #$b0		//'0'
		rts
alpha:		clc
		adc #($81-$0a)
		rts


.pc = $1000	//I just put this here because it's an easy location to remember if I want to peek()
		//the exact number from a BASIC prompt
errorCount:	.byte 0		




		