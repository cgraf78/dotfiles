# shellcheck shell=sh

# Stock WezTerm's integration appends duplicate hooks if sourced twice.
if [ -z "${__wezterm_sourced:-}" ]; then
  for _wezterm_bundle in "$HOME/Applications/WezTerm.app" /Applications/WezTerm.app; do
    _wezterm_integration=$_wezterm_bundle/Contents/Resources/wezterm.sh
    if [ -r "$_wezterm_integration" ]; then
      # shellcheck source=/dev/null
      . "$_wezterm_integration"
      __wezterm_sourced=1
      break
    fi
  done
  unset _wezterm_bundle _wezterm_integration
fi
