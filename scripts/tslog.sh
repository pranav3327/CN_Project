#!/usr/bin/env bash
# Used by tmux pipe-pane: strip terminal escape codes, prefix a timestamp,
# append to the log file given as $1.
exec perl -ne 'BEGIN { $| = 1; use POSIX qw(strftime); }
  s/\e\][^\a\e]*(?:\a|\e\\)//g;   # OSC (window titles)
  s/\e\[[0-9;?]*[ -\/]*[@-~]//g;  # CSI (colours, cursor moves)
  s/\e[()=>][0-9A-Za-z]?//g;      # charset / keypad modes
  s/\r//g;
  next if /^\s*$/;
  print strftime("%H:%M:%S ", localtime), $_;' >> "$1"
