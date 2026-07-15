//==============================================================================
// calculator.s — an interactive integer calculator in AArch64 assembly (macOS)
//
// Reads lines of the form:   <int> <op> <int>       e.g.   12 + 30
// Supported operators:       +  -  *  /  %
// Type 'q' (or EOF / Ctrl-D) to quit.
//
// Build:  make          (or: clang -o calculator calculator.s)
// Run:    ./calculator
//==============================================================================

.section __TEXT,__text
.align 2

//------------------------------------------------------------------------------
// Darwin arm64 syscall numbers (class 0x2000000 = Unix)
//------------------------------------------------------------------------------
.equ SYS_EXIT,  0x2000001
.equ SYS_READ,  0x2000003
.equ SYS_WRITE, 0x2000004
.equ STDIN,     0
.equ STDOUT,    1

.globl _main

//------------------------------------------------------------------------------
// _main — the read/eval/print loop
//   x19 = cursor into the input buffer
//   x20 = one-past-the-end of the valid input
//------------------------------------------------------------------------------
_main:
    stp     x29, x30, [sp, #-16]!       // save frame pointer + link register
    mov     x29, sp

.Lloop:
    // ---- print the prompt ---------------------------------------------------
    adrp    x1, prompt@PAGE
    add     x1, x1, prompt@PAGEOFF
    mov     x2, #4                       // len("> ") plus room; measured below
    mov     x2, #2
    bl      _write_str

    // ---- read a line from stdin --------------------------------------------
    mov     x0, #STDIN
    adrp    x1, inbuf@PAGE
    add     x1, x1, inbuf@PAGEOFF
    mov     x2, #256
    movz    x16, #0x0003                 // SYS_READ  = 0x2000003
    movk    x16, #0x0200, lsl #16
    svc     #0x80                        // x0 = bytes read (0 = EOF, <0 = error)

    cmp     x0, #0
    b.le    .Ldone                       // EOF or error -> quit

    // set up cursor (x19) and end pointer (x20)
    adrp    x19, inbuf@PAGE
    add     x19, x19, inbuf@PAGEOFF
    add     x20, x19, x0                 // end = buf + bytes_read

    // evaluate every expression remaining in the buffer (one read may hold
    // several lines, e.g. when input is piped)
.Lnext:
    bl      _skip_spaces

    // nothing left in the buffer? read the next line
    cmp     x19, x20
    b.ge    .Lloop

    // ---- quit command ('q') -------------------------------------------------
    ldrb    w0, [x19]
    cmp     w0, #'q'
    b.eq    .Ldone
    cmp     w0, #'Q'
    b.eq    .Ldone

    // ---- parse: <int> <op> <int> -------------------------------------------
    bl      _parse_int                   // x0 = first operand
    mov     x21, x0                      // x21 = a

    bl      _skip_spaces

    cmp     x19, x20                     // need an operator
    b.ge    .Lbad
    ldrb    w22, [x19], #1               // w22 = operator, advance cursor

    bl      _skip_spaces

    bl      _parse_int                   // x0 = second operand
    mov     x23, x0                      // x23 = b

    // ---- evaluate -----------------------------------------------------------
    cmp     w22, #'+'
    b.eq    .Ladd
    cmp     w22, #'-'
    b.eq    .Lsub
    cmp     w22, #'*'
    b.eq    .Lmul
    cmp     w22, #'x'                     // allow 'x' as multiply too
    b.eq    .Lmul
    cmp     w22, #'/'
    b.eq    .Ldiv
    cmp     w22, #'%'
    b.eq    .Lmod
    b       .Lbad                         // unknown operator

.Ladd:
    add     x0, x21, x23
    b       .Lprint
.Lsub:
    sub     x0, x21, x23
    b       .Lprint
.Lmul:
    mul     x0, x21, x23
    b       .Lprint
.Ldiv:
    cbz     x23, .Ldivzero
    sdiv    x0, x21, x23
    b       .Lprint
.Lmod:
    cbz     x23, .Ldivzero
    sdiv    x9, x21, x23                 // q = a / b
    msub    x0, x9, x23, x21             // r = a - q*b
    b       .Lprint

.Lprint:
    // print "= <result>\n"  (stash result in x24; _write_str clobbers x0)
    mov     x24, x0
    adrp    x1, eq@PAGE
    add     x1, x1, eq@PAGEOFF
    mov     x2, #2                        // "= "
    bl      _write_str
    mov     x0, x24
    bl      _print_int                   // prints x0
    bl      _write_nl
    b       .Lnext

.Ldivzero:
    adrp    x1, errdiv@PAGE
    add     x1, x1, errdiv@PAGEOFF
    mov     x2, #22
    bl      _write_str
    b       .Lnext

.Lbad:
    // skip to end of the current line, then continue with the rest
    adrp    x1, errbad@PAGE
    add     x1, x1, errbad@PAGEOFF
    mov     x2, #22
    bl      _write_str
    bl      _skip_to_eol
    b       .Lnext

.Ldone:
    // print a trailing newline so the shell prompt lands cleanly, then exit(0)
    bl      _write_nl
    mov     x0, #0
    movz    x16, #0x0001                 // SYS_EXIT = 0x2000001
    movk    x16, #0x0200, lsl #16
    svc     #0x80

//------------------------------------------------------------------------------
// _skip_spaces — advance x19 past whitespace incl. newlines (but not past x20)
//------------------------------------------------------------------------------
_skip_spaces:
1:  cmp     x19, x20
    b.ge    2f
    ldrb    w9, [x19]
    cmp     w9, #' '
    b.eq    3f
    cmp     w9, #'\t'
    b.eq    3f
    cmp     w9, #'\n'
    b.eq    3f
    cmp     w9, #'\r'
    b.eq    3f
    b       2f
3:  add     x19, x19, #1
    b       1b
2:  ret

//------------------------------------------------------------------------------
// _skip_to_eol — advance x19 to just past the next newline (or to x20).
//   Used to resynchronise after a malformed line.
//------------------------------------------------------------------------------
_skip_to_eol:
1:  cmp     x19, x20
    b.ge    2f
    ldrb    w9, [x19], #1                // load then advance
    cmp     w9, #'\n'
    b.ne    1b
2:  ret

//------------------------------------------------------------------------------
// _parse_int — parse an optionally-signed decimal integer at x19.
//   Advances x19 past the number. Returns value in x0.
//   Non-numeric input yields 0.
//------------------------------------------------------------------------------
_parse_int:
    mov     x0, #0                        // accumulator
    mov     x10, #0                       // negative flag

    cmp     x19, x20
    b.ge    9f
    ldrb    w9, [x19]
    cmp     w9, #'-'
    b.ne    1f
    mov     x10, #1                       // remember sign
    add     x19, x19, #1
    b       2f
1:  cmp     w9, #'+'
    b.ne    2f
    add     x19, x19, #1

2:  cmp     x19, x20
    b.ge    8f
    ldrb    w9, [x19]
    sub     w11, w9, #'0'
    cmp     w11, #9
    b.hi    8f                            // not a digit -> stop
    // acc = acc*10 + digit
    mov     x12, #10
    mul     x0, x0, x12
    add     x0, x0, x11
    add     x19, x19, #1
    b       2b

8:  cbz     x10, 9f                        // apply sign
    neg     x0, x0
9:  ret

//------------------------------------------------------------------------------
// _print_int — print signed 64-bit integer in x0 as decimal to stdout.
//   Uses numbuf (scratch). Clobbers x0-x12.
//------------------------------------------------------------------------------
_print_int:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // point x9 at the END of numbuf; we fill digits backwards
    adrp    x9, numbuf@PAGE
    add     x9, x9, numbuf@PAGEOFF
    add     x9, x9, #32                    // end of scratch region
    mov     x11, #0                        // negative flag

    // handle zero explicitly
    cbnz    x0, 1f
    mov     w12, #'0'
    sub     x9, x9, #1
    strb    w12, [x9]
    b       5f

1:  // handle negative
    cmp     x0, #0
    b.ge    2f
    mov     x11, #1
    neg     x0, x0

2:  mov     x10, #10
3:  udiv    x12, x0, x10                   // q = n / 10
    msub    x13, x12, x10, x0             // r = n - q*10
    add     w13, w13, #'0'
    sub     x9, x9, #1
    strb    w13, [x9]
    mov     x0, x12
    cbnz    x0, 3b

    cbz     x11, 5f                        // prepend '-' if negative
    mov     w12, #'-'
    sub     x9, x9, #1
    strb    w12, [x9]

5:  // write from x9 to end-of-buffer
    adrp    x1, numbuf@PAGE
    add     x1, x1, numbuf@PAGEOFF
    add     x1, x1, #32                    // end
    sub     x2, x1, x9                     // length = end - start
    mov     x1, x9                         // start pointer
    bl      _write_str

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// _write_str — write x2 bytes at x1 to stdout
//------------------------------------------------------------------------------
_write_str:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, #STDOUT
    movz    x16, #0x0004                 // SYS_WRITE = 0x2000004
    movk    x16, #0x0200, lsl #16
    svc     #0x80
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// _write_nl — write a single newline to stdout
//------------------------------------------------------------------------------
_write_nl:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adrp    x1, newline@PAGE
    add     x1, x1, newline@PAGEOFF
    mov     x2, #1
    bl      _write_str
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Read-only data
//------------------------------------------------------------------------------
.section __TEXT,__const
prompt:   .ascii  "> "
eq:       .ascii  "= "
newline:  .ascii  "\n"
errdiv:   .ascii  "error: divide by zero\n"
errbad:   .ascii  "error: bad expression\n"

//------------------------------------------------------------------------------
// Writable scratch / buffers
//------------------------------------------------------------------------------
.section __DATA,__bss
.align 3
inbuf:    .space  256                     // input line buffer
numbuf:   .space  32                      // scratch for print_int
