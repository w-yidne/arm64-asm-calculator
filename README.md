# arm64-asm-calculator — calculators in AArch64 assembly

Two integer calculators written in raw **ARM64 (AArch64) assembly** for macOS on
Apple Silicon:

- **`calc_gui`** — a windowed calculator with a real Cocoa GUI.
- **`calculator`** — a terminal / REPL calculator.

Both are hand-written assembly. No C, no Swift.

## Build & run

```sh
git clone https://github.com/w-yidne/arm64-asm-calculator.git
cd arm64-asm-calculator

make            # build both
make run        # build and launch the GUI app
./calc_gui      # windowed calculator
./calculator    # terminal calculator
```

---

## `calc_gui` — the GUI app

A **clock-face** layout: the ten digits ring the outside like the hours on a
clock, the operators cluster in the middle, and a display bar sits across the
top. Buttons use the circular bezel style, so they read as round clock keys.

```
   ┌──────────────────────────────┐
   │                          0   │ ← display
   │              1               │
   │       0             2        │
   │                              │
   │    9        ÷        3       │
   │          C  =                │
   │    8     ×     −    4        │
   │             +                │
   │       7             5        │
   │              6               │
   └──────────────────────────────┘
```

(The digits sit at evenly-spaced angles around a centre of (190, 205) at
radius 140; the operators are clustered at the middle — `÷` top, `+` bottom,
`×` left, `−` right, `=` dead centre, `C` on the top-left diagonal.)

Click digits and an operator, then `=`. `C` clears. Integer arithmetic;
`/` truncates; negative results are shown with a leading `-`.

### How it's built (pure assembly + Cocoa)

There is no libc UI layer here — the program talks to **AppKit through the
Objective-C runtime** directly:

- `objc_getClass` / `sel_registerName` — startup registers every class
  (`NSApplication`, `NSWindow`, `NSButton`, `NSTextField`, `NSString`, …) and
  selector into two lookup tables (`classes[]`, `sels[]`).
- `objc_msgSend` — every Cocoa call is a hand-assembled message send: receiver
  in `x0`, selector in `x1`, args in `x2…`; `NSRect` frames are passed as a
  homogeneous float aggregate in `d0–d3`.
- `objc_allocateClassPair` / `class_addMethod` — a `Calc` subclass of `NSObject`
  is *created at runtime*, with its `buttonClicked:` and
  `applicationShouldTerminateAfterLastWindowClosed:` methods pointing straight at
  assembly routines (`_onButton`, `_onTerminate`).
- Each button gets an integer `tag` (0–9 for digits, 10–15 for `+ - * / = C`).
  `_onButton` reads `[sender tag]` and drives the calculator state machine
  (`g_acc`, `g_entry`, `g_pending`, `g_newentry`), then formats the result and
  calls `[field setStringValue:]`.

Build: `clang -o calc_gui calc_gui.s -framework Cocoa`

#### Assembly gotchas worth knowing

- **Pointer tables must live in `__DATA,__const`, not `__TEXT,__const`.** The
  selector/class/button tables hold absolute pointers that dyld rebases for
  ASLR; that rebasing only works in a writable-then-readonly data section. In
  read-only `__TEXT` they link as **all zeros** — which showed up as null
  selectors and a jump-to-null crash.
- **`objc_msgSend` clobbers `x0`.** Results being displayed are stashed in a
  callee-saved register before any intermediate message send.
- Darwin syscall numbers (`0x2000004`, …) don't fit a single `mov` immediate —
  they're loaded with `movz`/`movk`.

---

## `calculator` — the terminal app

Freestanding: no libc, talks to the kernel via Darwin syscalls
(`read`/`write`/`exit`). Reads `<int> <op> <int>` per line:

```
> 12 + 30
= 42
> 7 * -6
= -42
> 100 / 7
= 14
> 100 % 7
= 2
> q
```

Operators: `+ - * (or x) / %`. Quit with `q`, `Q`, or Ctrl-D.
Errors are reported inline (`error: divide by zero`, `error: bad expression`).
