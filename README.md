# RAD-REU-test

Simple code to exercise RAD (https://github.com/frntc/RAD) or REU DMA transfers and use the verify function to detect errors.  To use, configure #defines and REU size, assemble with Kick Assembler and run forever--as it may take hours to encounter a single bit-error. The pre-assembled .prg file will work with a 2MB RAD or REU only, uses a source address in RAM (results can be different if source address is in ROM), leaves the VIC display enabled during transfers (so transfer can be subject to bus conflict with VIC), and halts on error detection.


# Background

I've tried many REU test programs and found them to be inconsistent in error detection for the frenetic RAD I assembled (not saying all RADs, just my build) with default timings and preload/cache settings in RAD/rad.cfg:

Gum+Pan/Alter tester	https://csdb.dk/release/?id=172121					always reports an error or crashes on start

REU tools Walt/Bonzai	https://csdb.dk/release/?id=198460					never reports an error

CBM Test/Demo Disk 1.0	https://www.zimmers.net/anonftp/pub/cbm/demodisks/other/index.html	never reports an error

CMD 1750XL disk		https://www.zimmers.net/anonftp/pub/cbm/demodisks/cmd/index.html	reports an error every 15 minutes of run time

MemTest64 Rosettif	https://csdb.dk/release/?id=158763					never reports an error


Tentative/early observation was that most testers don't find the error because 1) it's infrequent, perhaps 1 per hour, and 2) some errors are not real; REU contents are good but the very first byte or two verified fails.  The CMD tester is "the best" in this regard because it takes 15 min to fully test a 8MB REU and there is a decent chance of fail during that time.  I think the Alter tester might be good but something like the problem of "first byte(s) verified usually fails" is killing it.

Ultimate goal of this little project is to come up with a systematic/robust way of configuring the dozen+ timing settings, hopefully without resorting to attaching a logic analyzer.
