//==============================================================================
// calc_gui.s — a windowed calculator in AArch64 assembly for macOS.
//
// Pure assembly: the GUI is built by talking to Cocoa (AppKit) through the
// Objective-C runtime — objc_getClass / sel_registerName / objc_msgSend, plus
// objc_allocateClassPair to define a delegate class whose methods are our own
// assembly routines. No C, no Swift, no nib.
//
// Build:  clang -o calc_gui calc_gui.s -framework Cocoa
// Run:    ./calc_gui
//==============================================================================

//------------------------------------------------------------------------------
// Selector indices (into the `sels` table, populated at startup)
//------------------------------------------------------------------------------
.equ S_sharedApplication,      0
.equ S_setActivationPolicy,    1
.equ S_alloc,                  2
.equ S_initWithContentRect,    3
.equ S_setTitle,               4
.equ S_center,                 5
.equ S_makeKeyAndOrderFront,   6
.equ S_contentView,            7
.equ S_addSubview,             8
.equ S_buttonWithTitle,        9
.equ S_setFrame,              10
.equ S_setTag,                11
.equ S_tag,                   12
.equ S_initWithFrame,         13
.equ S_setStringValue,        14
.equ S_setEditable,           15
.equ S_setBezeled,            16
.equ S_setAlignment,          17
.equ S_setFont,               18
.equ S_stringWithUTF8String,  19
.equ S_setDelegate,           20
.equ S_activateIgnoring,      21
.equ S_run,                   22
.equ S_systemFontOfSize,      23
.equ S_init,                  24
.equ S_COUNT,                 25

//------------------------------------------------------------------------------
// Class indices (into the `classes` table)
//------------------------------------------------------------------------------
.equ C_NSApplication,     0
.equ C_NSWindow,          1
.equ C_NSButton,          2
.equ C_NSTextField,       3
.equ C_NSString,          4
.equ C_NSObject,          5
.equ C_NSFont,            6
.equ C_NSAutoreleasePool, 7
.equ C_COUNT,             8

//------------------------------------------------------------------------------
// Handy macros
//------------------------------------------------------------------------------
.macro LEA reg, sym
    adrp    \reg, \sym@PAGE
    add     \reg, \reg, \sym@PAGEOFF
.endm

// Load selector #idx into x1 (msgSend's second argument)
.macro LDSEL idx
    adrp    x1, sels@PAGE
    add     x1, x1, sels@PAGEOFF
    ldr     x1, [x1, #\idx * 8]
.endm

// Load class #idx into \reg
.macro LDCLS reg, idx
    adrp    \reg, classes@PAGE
    add     \reg, \reg, classes@PAGEOFF
    ldr     \reg, [\reg, #\idx * 8]
.endm

.section __TEXT,__text
.align 2
.globl _main

//==============================================================================
// _main — set everything up, then hand control to the AppKit run loop.
//   Persistent registers held across the setup:
//     x19 = window     x20 = contentView     x21 = calcObj (delegate/target)
//     x22 = app        x23 = button index    x24 = button spec base
//==============================================================================
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      _init_runtime               // fill sels[] and classes[]

    // --- an autorelease pool so autoreleased objects have a home ------------
    LDCLS   x0, C_NSAutoreleasePool
    LDSEL   S_alloc
    bl      _objc_msgSend
    LDSEL   S_init
    bl      _objc_msgSend

    bl      _setup_class                // define Calc class + instance

    // --- NSApplication ------------------------------------------------------
    LDCLS   x0, C_NSApplication
    LDSEL   S_sharedApplication
    bl      _objc_msgSend
    mov     x22, x0                      // app

    mov     x0, x22                      // setActivationPolicy: Regular(0)
    LDSEL   S_setActivationPolicy
    mov     x2, #0
    bl      _objc_msgSend

    // --- NSWindow -----------------------------------------------------------
    LDCLS   x0, C_NSWindow
    LDSEL   S_alloc
    bl      _objc_msgSend
    mov     x19, x0                      // window (unallocated init below)

    mov     x9,  #0                      // contentRect (0,0,240,340)
    mov     x10, #0
    mov     x11, #240
    mov     x12, #340
    bl      _set_rect_regs
    mov     x0, x19
    LDSEL   S_initWithContentRect
    mov     x2, #7                       // Titled|Closable|Miniaturizable
    mov     x3, #2                       // NSBackingStoreBuffered
    mov     x4, #0                       // defer: NO
    bl      _objc_msgSend
    mov     x19, x0                      // window

    LEA     x0, t_title                  // title NSString
    bl      _nsstring
    mov     x2, x0
    mov     x0, x19
    LDSEL   S_setTitle
    bl      _objc_msgSend

    mov     x0, x19                      // center on screen
    LDSEL   S_center
    bl      _objc_msgSend

    mov     x0, x19                      // contentView
    LDSEL   S_contentView
    bl      _objc_msgSend
    mov     x20, x0

    // --- display text field -------------------------------------------------
    LDCLS   x0, C_NSTextField
    LDSEL   S_alloc
    bl      _objc_msgSend
    mov     x25, x0
    mov     x9,  #20                     // frame (20, 280, 200, 44)
    mov     x10, #280
    mov     x11, #200
    mov     x12, #44
    bl      _set_rect_regs
    mov     x0, x25
    LDSEL   S_initWithFrame
    bl      _objc_msgSend
    LEA     x9, g_field
    str     x0, [x9]                     // g_field = display

    LEA     x0, g_field                  // setBezeled: YES
    ldr     x0, [x0]
    LDSEL   S_setBezeled
    mov     x2, #1
    bl      _objc_msgSend
    LEA     x0, g_field                  // setEditable: NO
    ldr     x0, [x0]
    LDSEL   S_setEditable
    mov     x2, #0
    bl      _objc_msgSend
    LEA     x0, g_field                  // setAlignment: right(2)
    ldr     x0, [x0]
    LDSEL   S_setAlignment
    mov     x2, #2
    bl      _objc_msgSend

    LDCLS   x0, C_NSFont                 // font = systemFontOfSize: 30
    LDSEL   S_systemFontOfSize
    mov     x9, #30
    scvtf   d0, x9
    bl      _objc_msgSend
    mov     x9, x0
    LEA     x0, g_field
    ldr     x0, [x0]
    LDSEL   S_setFont
    mov     x2, x9
    bl      _objc_msgSend

    mov     x0, x20                      // add field to content view
    LDSEL   S_addSubview
    LEA     x2, g_field
    ldr     x2, [x2]
    bl      _objc_msgSend

    // --- button grid --------------------------------------------------------
    LEA     x21, g_calcObj               // reuse: load calcObj into x21
    ldr     x21, [x21]
    LEA     x24, btnspec
    mov     x23, #0
.Lbtn:
    add     x9, x24, x23, lsl #4         // &btnspec[i]  (16 bytes/entry)
    ldr     x26, [x9]                    // title C-string
    ldr     x27, [x9, #8]               // tag

    mov     x0, x26                      // NSString from title
    bl      _nsstring
    mov     x26, x0                      // x26 = title NSString

    LDCLS   x0, C_NSButton               // +[NSButton buttonWithTitle:target:action:]
    LDSEL   S_buttonWithTitle
    mov     x2, x26                      // title
    mov     x3, x21                      // target = calcObj
    LEA     x4, g_selButton
    ldr     x4, [x4]                     // action = @selector(buttonClicked:)
    bl      _objc_msgSend
    mov     x26, x0                      // x26 = button

    and     x9,  x23, #3                 // col = i & 3
    lsr     x10, x23, #2                 // row = i >> 2  (0 = top)
    mov     x11, #55
    mul     x9,  x9,  x11
    add     x9,  x9,  #15                // x = 15 + col*55
    mov     x12, #3
    sub     x10, x12, x10                // flip: Cocoa origin is bottom-left
    mul     x10, x10, x11
    add     x10, x10, #15                // y = 15 + (3-row)*55
    mov     x11, #50                     // w
    mov     x12, #50                     // h
    bl      _set_rect_regs
    mov     x0, x26                      // setFrame:
    LDSEL   S_setFrame
    bl      _objc_msgSend

    mov     x0, x26                      // setTag:
    LDSEL   S_setTag
    mov     x2, x27
    bl      _objc_msgSend

    mov     x0, x20                      // [contentView addSubview: button]
    LDSEL   S_addSubview
    mov     x2, x26
    bl      _objc_msgSend

    add     x23, x23, #1
    cmp     x23, #16
    b.lt    .Lbtn

    // --- initial calculator state + display ---------------------------------
    LEA     x9, g_acc
    str     xzr, [x9]
    LEA     x9, g_entry
    str     xzr, [x9]
    LEA     x9, g_pending
    str     xzr, [x9]
    LEA     x9, g_newentry
    mov     x10, #1
    str     x10, [x9]
    mov     x0, #0
    bl      _update_display

    // --- delegate, show, activate, run --------------------------------------
    mov     x0, x22                      // [app setDelegate: calcObj]
    LDSEL   S_setDelegate
    mov     x2, x21
    bl      _objc_msgSend

    mov     x0, x19                      // [window makeKeyAndOrderFront: nil]
    LDSEL   S_makeKeyAndOrderFront
    mov     x2, #0
    bl      _objc_msgSend

    mov     x0, x22                      // [app activateIgnoringOtherApps: YES]
    LDSEL   S_activateIgnoring
    mov     x2, #1
    bl      _objc_msgSend

    mov     x0, x22                      // [app run]  — does not return
    LDSEL   S_run
    bl      _objc_msgSend

    mov     x0, #0                       // exit(0) fallback
    movz    x16, #0x0001
    movk    x16, #0x0200, lsl #16
    svc     #0x80

//==============================================================================
// _init_runtime — register every selector name and look up every class.
//==============================================================================
_init_runtime:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    LEA     x19, selnames
    LEA     x20, sels
    mov     x21, #0
1:  cmp     x21, #S_COUNT
    b.ge    2f
    ldr     x0, [x19, x21, lsl #3]
    bl      _sel_registerName
    str     x0, [x20, x21, lsl #3]
    add     x21, x21, #1
    b       1b

2:  LEA     x19, clsnames
    LEA     x20, classes
    mov     x21, #0
3:  cmp     x21, #C_COUNT
    b.ge    4f
    ldr     x0, [x19, x21, lsl #3]
    bl      _objc_getClass
    str     x0, [x20, x21, lsl #3]
    add     x21, x21, #1
    b       3b

4:  ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

//==============================================================================
// _setup_class — build the "Calc" NSObject subclass at runtime and make one
// instance. Its methods are the assembly routines _onButton / _onTerminate.
//==============================================================================
_setup_class:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    LDCLS   x0, C_NSObject               // objc_allocateClassPair(NSObject,"Calc",0)
    LEA     x1, str_calc
    mov     x2, #0
    bl      _objc_allocateClassPair
    mov     x19, x0                      // the new class
    LEA     x9, g_calcClass
    str     x19, [x9]

    LEA     x0, sel_btnclicked           // add buttonClicked:
    bl      _sel_registerName
    LEA     x9, g_selButton
    str     x0, [x9]
    mov     x1, x0
    mov     x0, x19
    LEA     x2, _onButton
    LEA     x3, types_v
    bl      _class_addMethod

    LEA     x0, sel_terminate            // add applicationShouldTerminate...:
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x19
    LEA     x2, _onTerminate
    LEA     x3, types_c
    bl      _class_addMethod

    mov     x0, x19                      // objc_registerClassPair
    bl      _objc_registerClassPair

    mov     x0, x19                      // instance = [[Calc alloc] init]
    LDSEL   S_alloc
    bl      _objc_msgSend
    LDSEL   S_init
    bl      _objc_msgSend
    LEA     x9, g_calcObj
    str     x0, [x9]

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

//==============================================================================
// _onButton(self, _cmd, sender) — the button action. Reads [sender tag] and
// drives the calculator state machine.
//==============================================================================
_onButton:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x0, x2                       // sender
    LDSEL   S_tag
    bl      _objc_msgSend
    mov     x19, x0                      // tag

    cmp     x19, #9
    b.le    .Ldigit
    cmp     x19, #15
    b.eq    .Lclear
    cmp     x19, #14
    b.eq    .Lequals
    b       .Loperator                   // 10..13

.Ldigit:
    LEA     x9, g_newentry
    ldr     x10, [x9]
    cbz     x10, 1f
    LEA     x11, g_entry                 // starting a fresh number
    str     xzr, [x11]
    str     xzr, [x9]
1:  LEA     x11, g_entry
    ldr     x12, [x11]
    mov     x13, #10
    mul     x12, x12, x13
    add     x12, x12, x19                // entry = entry*10 + digit
    str     x12, [x11]
    mov     x0, x12
    bl      _update_display
    b       .Lret

.Loperator:
    bl      _apply_pending
    LEA     x9, g_pending
    str     x19, [x9]                    // remember this operator
    LEA     x9, g_newentry
    mov     x10, #1
    str     x10, [x9]
    LEA     x9, g_acc
    ldr     x0, [x9]
    bl      _update_display
    b       .Lret

.Lequals:
    LEA     x9, g_pending
    ldr     x2, [x9]
    cbz     x2, 2f
    LEA     x9, g_acc
    ldr     x0, [x9]
    LEA     x10, g_entry
    ldr     x1, [x10]
    bl      _compute
    LEA     x9, g_acc
    str     x0, [x9]
    LEA     x10, g_entry
    str     x0, [x10]
    LEA     x9, g_pending
    str     xzr, [x9]
2:  LEA     x9, g_newentry
    mov     x10, #1
    str     x10, [x9]
    LEA     x9, g_acc
    ldr     x0, [x9]
    bl      _update_display
    b       .Lret

.Lclear:
    LEA     x9, g_acc
    str     xzr, [x9]
    LEA     x9, g_entry
    str     xzr, [x9]
    LEA     x9, g_pending
    str     xzr, [x9]
    LEA     x9, g_newentry
    mov     x10, #1
    str     x10, [x9]
    mov     x0, #0
    bl      _update_display

.Lret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

//------------------------------------------------------------------------------
// _apply_pending — fold the pending operator: acc = acc OP entry (or acc=entry).
//------------------------------------------------------------------------------
_apply_pending:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    LEA     x9, g_pending
    ldr     x2, [x9]
    cbnz    x2, 1f
    LEA     x9, g_entry                  // no pending op: acc = entry
    ldr     x10, [x9]
    LEA     x11, g_acc
    str     x10, [x11]
    b       2f
1:  LEA     x9, g_acc
    ldr     x0, [x9]
    LEA     x10, g_entry
    ldr     x1, [x10]
    bl      _compute                     // x2 already holds the op
    LEA     x9, g_acc
    str     x0, [x9]
2:  ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// _compute(a=x0, b=x1, op=x2) -> x0   (op: 10=+ 11=- 12=* 13=/)
//------------------------------------------------------------------------------
_compute:
    cmp     x2, #10
    b.eq    .cadd
    cmp     x2, #11
    b.eq    .csub
    cmp     x2, #12
    b.eq    .cmul
    cmp     x2, #13
    b.eq    .cdiv
    ret
.cadd:  add     x0, x0, x1
        ret
.csub:  sub     x0, x0, x1
        ret
.cmul:  mul     x0, x0, x1
        ret
.cdiv:  cbz     x1, .cdz                 // divide-by-zero -> 0
        sdiv    x0, x0, x1
        ret
.cdz:   mov     x0, #0
        ret

//------------------------------------------------------------------------------
// _onTerminate(self,_cmd,app) -> BOOL  — quit when the window closes.
//------------------------------------------------------------------------------
_onTerminate:
    mov     w0, #1                       // YES
    ret

//==============================================================================
// _update_display(value in x0) — render value and set the field's stringValue.
//==============================================================================
_update_display:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    LEA     x1, g_dispbuf
    bl      _int_to_cstr

    LEA     x0, g_dispbuf                // NSString from the C string
    bl      _nsstring
    mov     x9, x0

    LEA     x0, g_field
    ldr     x0, [x0]
    LDSEL   S_setStringValue
    mov     x2, x9
    bl      _objc_msgSend

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// _nsstring(cstr in x0) -> NSString in x0   [NSString stringWithUTF8String:]
//------------------------------------------------------------------------------
_nsstring:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x2, x0                       // the C string
    LDCLS   x0, C_NSString
    LDSEL   S_stringWithUTF8String
    bl      _objc_msgSend
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// _set_rect_regs — pack integer x9,x10,x11,x12 into d0-d3 as an NSRect
// (x, y, w, h). Cocoa passes NSRect by value in v0-v3.
//------------------------------------------------------------------------------
_set_rect_regs:
    scvtf   d0, x9
    scvtf   d1, x10
    scvtf   d2, x11
    scvtf   d3, x12
    ret

//------------------------------------------------------------------------------
// _int_to_cstr(value=x0, dest=x1) — write NUL-terminated signed decimal.
//------------------------------------------------------------------------------
_int_to_cstr:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #32
    mov     x8, x1                       // dest
    mov     x11, #0                      // negative flag
    add     x9, sp, #32                  // temp cursor (fill backwards)

    cbnz    x0, 1f
    mov     w12, #'0'
    sub     x9, x9, #1
    strb    w12, [x9]
    b       5f
1:  cmp     x0, #0
    b.ge    2f
    mov     x11, #1
    neg     x0, x0
2:  mov     x10, #10
3:  udiv    x12, x0, x10
    msub    x13, x12, x10, x0
    add     w13, w13, #'0'
    sub     x9, x9, #1
    strb    w13, [x9]
    mov     x0, x12
    cbnz    x0, 3b
    cbz     x11, 5f
    mov     w12, #'-'
    sub     x9, x9, #1
    strb    w12, [x9]
5:  add     x14, sp, #32                 // copy temp -> dest
6:  cmp     x9, x14
    b.ge    7f
    ldrb    w12, [x9], #1
    strb    w12, [x8], #1
    b       6b
7:  strb    wzr, [x8]                    // NUL terminate
    add     sp, sp, #32
    ldp     x29, x30, [sp], #16
    ret

//==============================================================================
// Read-only data
//
// NOTE: these strings are referenced by label from the tables below, so they
// must NOT live in __cstring — that section is coalesced and the linker drops
// the local labels, leaving the .quad relocations pointing at 0. A plain
// __const section keeps the labels intact.
//==============================================================================
.section __TEXT,__const
t_title:        .asciz "asm calc"
str_calc:       .asciz "Calc"
sel_btnclicked: .asciz "buttonClicked:"
sel_terminate:  .asciz "applicationShouldTerminateAfterLastWindowClosed:"
types_v:        .asciz "v@:@"
types_c:        .asciz "c@:@"

// button titles
b0: .asciz "0"
b1: .asciz "1"
b2: .asciz "2"
b3: .asciz "3"
b4: .asciz "4"
b5: .asciz "5"
b6: .asciz "6"
b7: .asciz "7"
b8: .asciz "8"
b9: .asciz "9"
bAdd: .asciz "+"
bSub: .asciz "-"
bMul: .asciz "*"
bDiv: .asciz "/"
bEq:  .asciz "="
bClr: .asciz "C"

// selector names (order MUST match the S_* indices)
sn0:  .asciz "sharedApplication"
sn1:  .asciz "setActivationPolicy:"
sn2:  .asciz "alloc"
sn3:  .asciz "initWithContentRect:styleMask:backing:defer:"
sn4:  .asciz "setTitle:"
sn5:  .asciz "center"
sn6:  .asciz "makeKeyAndOrderFront:"
sn7:  .asciz "contentView"
sn8:  .asciz "addSubview:"
sn9:  .asciz "buttonWithTitle:target:action:"
sn10: .asciz "setFrame:"
sn11: .asciz "setTag:"
sn12: .asciz "tag"
sn13: .asciz "initWithFrame:"
sn14: .asciz "setStringValue:"
sn15: .asciz "setEditable:"
sn16: .asciz "setBezeled:"
sn17: .asciz "setAlignment:"
sn18: .asciz "setFont:"
sn19: .asciz "stringWithUTF8String:"
sn20: .asciz "setDelegate:"
sn21: .asciz "activateIgnoringOtherApps:"
sn22: .asciz "run"
sn23: .asciz "systemFontOfSize:"
sn24: .asciz "init"

// class names (order MUST match the C_* indices)
cn0: .asciz "NSApplication"
cn1: .asciz "NSWindow"
cn2: .asciz "NSButton"
cn3: .asciz "NSTextField"
cn4: .asciz "NSString"
cn5: .asciz "NSObject"
cn6: .asciz "NSFont"
cn7: .asciz "NSAutoreleasePool"

// These tables hold absolute pointers, which dyld must rebase for ASLR — that
// only works in a writable-then-readonly __DATA section, never in __TEXT.
.section __DATA,__const
.align 3
selnames:
    .quad sn0,  sn1,  sn2,  sn3,  sn4,  sn5,  sn6,  sn7
    .quad sn8,  sn9,  sn10, sn11, sn12, sn13, sn14, sn15
    .quad sn16, sn17, sn18, sn19, sn20, sn21, sn22, sn23
    .quad sn24
clsnames:
    .quad cn0, cn1, cn2, cn3, cn4, cn5, cn6, cn7

// button grid: {title, tag}, laid out left-to-right, top-to-bottom
btnspec:
    .quad b7, 7
    .quad b8, 8
    .quad b9, 9
    .quad bDiv, 13
    .quad b4, 4
    .quad b5, 5
    .quad b6, 6
    .quad bMul, 12
    .quad b1, 1
    .quad b2, 2
    .quad b3, 3
    .quad bSub, 11
    .quad bClr, 15
    .quad b0, 0
    .quad bEq, 14
    .quad bAdd, 10

//==============================================================================
// Writable state
//==============================================================================
.section __DATA,__bss
.align 3
classes:     .space C_COUNT * 8
sels:        .space S_COUNT * 8
g_calcClass: .space 8
g_calcObj:   .space 8
g_selButton: .space 8
g_field:     .space 8
g_acc:       .space 8                    // accumulator
g_entry:     .space 8                    // number being typed
g_pending:   .space 8                    // pending operator tag (0 = none)
g_newentry:  .space 8                    // 1 = next digit starts a new number
g_dispbuf:   .space 32                   // scratch for the display string
