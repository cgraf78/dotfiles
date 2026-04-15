const vscode = require('vscode');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Dedicated signal directory — avoids watching the noisy tmpdir.
const SIGNAL_DIR = path.join(os.homedir(), '.claude', 'notify');
const SIGNAL_FILE = path.join(SIGNAL_DIR, 'signal');

const DEFAULT_SOUNDS = {
  darwin: '/System/Library/Sounds/Glass.aiff',
  linux: '/usr/share/sounds/freedesktop/stereo/complete.oga',
};

function activate(context) {
  fs.mkdirSync(SIGNAL_DIR, { recursive: true });

  let lastPlay = 0;
  const fsWatcher = fs.watch(SIGNAL_DIR, (eventType, filename) => {
    if (filename !== 'signal') return;
    if (!fs.existsSync(SIGNAL_FILE)) return;

    const config = vscode.workspace.getConfiguration('claudeNotifySound');
    if (!config.get('enabled')) return;

    const now = Date.now();
    if (now - lastPlay < 500) return;
    lastPlay = now;

    const soundFile = config.get('soundFile') || DEFAULT_SOUNDS[process.platform];
    if (!soundFile || !fs.existsSync(soundFile)) return;

    if (process.platform === 'darwin') {
      execFile('afplay', [soundFile], (err) => {
        if (err) console.error('claude-notify-sound: afplay failed', err);
      });
    } else if (process.platform === 'linux') {
      execFile('paplay', [soundFile], (err) => {
        if (err) console.error('claude-notify-sound: paplay failed', err);
      });
    }

    try { fs.unlinkSync(SIGNAL_FILE); } catch (_) {}
  });

  context.subscriptions.push({ dispose: () => fsWatcher.close() });
}

function deactivate() {}

module.exports = { activate, deactivate };
