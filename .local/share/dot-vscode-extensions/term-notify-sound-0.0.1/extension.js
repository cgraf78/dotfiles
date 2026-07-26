const vscode = require("vscode");
const { execFile } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { signalDir } = require("./paths");

const DEFAULT_SOUNDS = {
  darwin: "/System/Library/Sounds/Glass.aiff",
  linux: "/usr/share/sounds/freedesktop/stereo/complete.oga",
};

function activate(context) {
  // Resolve lazily so an unavailable state root fails activation with the
  // producer's actionable path error instead of failing module discovery.
  const signalDirPath = signalDir();
  const signalFile = path.join(signalDirPath, "signal");
  fs.mkdirSync(signalDirPath, { recursive: true });

  // fs.watch fires multiple events per touch — debounce into one play.
  let pending = null;
  const fsWatcher = fs.watch(signalDirPath, (_eventType, filename) => {
    if (filename !== "signal" || pending) return;
    pending = setTimeout(() => {
      pending = null;
      try {
        fs.unlinkSync(signalFile);
      } catch (_) {
        return;
      }

      const config = vscode.workspace.getConfiguration("termNotifySound");
      if (!config.get("enabled")) return;

      const soundFile = config.get("soundFile") || DEFAULT_SOUNDS[process.platform];
      if (!soundFile || !fs.existsSync(soundFile)) return;

      if (process.platform === "darwin") {
        execFile("afplay", [soundFile], (err) => {
          if (err) console.error("term-notify-sound: afplay failed", err);
        });
      } else if (process.platform === "linux") {
        execFile("paplay", [soundFile], (err) => {
          if (err) console.error("term-notify-sound: paplay failed", err);
        });
      }
    }, 50);
  });

  context.subscriptions.push({ dispose: () => fsWatcher.close() });
}

function deactivate() {}

module.exports = { activate, deactivate };
