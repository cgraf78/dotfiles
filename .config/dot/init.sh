#!/bin/bash
# Shared environment for dot and dotbootstrap.
# Sources all dot modules in dependency order.

_dir="${BASH_SOURCE[0]%/*}"
. "$_dir/core.sh"
. "$_dir/repos.sh"
. "$_dir/merges.sh"
. "$_dir/cron.sh"
. "$_dir/deps.sh"
