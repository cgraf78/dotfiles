# Dot Lua Helpers

This directory contains Lua helpers owned by dotfiles runtime code.

`shdeps-loader.lua` is a seed loader for Neovim and other Lua consumers inside
dotfiles. It finds shdeps' `lua/shdeps/bootstrap.lua` entry point across local
development clones, source installs, and release installs, then returns
shdeps' public Lua API.

Dotfiles should not reimplement dependency resolution here. Once the shdeps
bootstrap module is found, shdeps owns API discovery, dependency lookup, and
child-process environment behavior.
