# Design notes

The code carries no comments. Intent lives in names, reasons live in test
names, and this directory holds the residue: constraints that no Swift name and
no test can express — platform behaviour that was tried and failed, couplings to
build scripts, and measured numbers whose measurement is the justification.

One file per source target. A note is written only when the three homes above it
are ruled out:

1. A comment that restates the code is deleted.
2. A comment that names something becomes the name.
3. A comment recording a bug becomes a test whose name is the record and whose
   input is the reproduction.
4. Only what survives all three lands here.

A note that could have been a test is a test that was not written.
