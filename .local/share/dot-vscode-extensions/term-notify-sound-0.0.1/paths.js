const path = require("node:path");

/**
 * Resolve the directory shared with the term-notify producer.
 *
 * XDG base directories must be absolute. Ignoring an invalid relative value
 * keeps the extension and shell producer on the same documented fallback.
 */
function signalDir(env = process.env) {
  const stateHome = env.XDG_STATE_HOME;
  if (stateHome && path.isAbsolute(stateHome)) {
    return path.join(stateHome, "term-notify");
  }

  // Match the shell producer exactly. Consulting os.homedir() here would
  // invent a passwd-database fallback that the producer does not use.
  const home = env.HOME;
  if (!home) {
    throw new Error("HOME is not set and XDG_STATE_HOME is not absolute");
  }

  return path.join(home, ".local", "state", "term-notify");
}

module.exports = { signalDir };
