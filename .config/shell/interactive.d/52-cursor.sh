# shellcheck shell=bash
# Blinking block cursor for the shell prompt.
# Nvim changes cursor shape per mode; this resets to block after exiting.
# Guard on a tty: interactive shells with redirected/captured stdout must not
# get a literal escape sequence written into the stream.
[ -t 1 ] && printf '\e[1 q'
