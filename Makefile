# Build the AArch64 (Apple Silicon / macOS) assembly calculators.
#
#   make            build both the GUI app and the CLI tool
#   make gui        build ./calc_gui  (windowed Cocoa calculator)
#   make cli        build ./calculator (terminal calculator)
#   make run        build and launch the GUI app
#   make clean      remove build artifacts

CC := clang

all: calc_gui calculator

# GUI app: drives Cocoa/AppKit through the Objective-C runtime, in pure asm.
calc_gui: calc_gui.s
	$(CC) -o calc_gui calc_gui.s -framework Cocoa

# CLI app: freestanding, talks to the kernel via Darwin syscalls.
calculator: calculator.s
	$(CC) -o calculator calculator.s

.PHONY: all gui cli run clean
gui: calc_gui
cli: calculator

run: calc_gui
	./calc_gui

clean:
	rm -f calc_gui calculator
