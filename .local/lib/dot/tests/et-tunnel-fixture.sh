#!/usr/bin/env bash
# et-tunnel-fixture.sh - shared setup for ET tunnel behavior shards.

# shellcheck disable=SC1091,SC2016,SC2034
set -o pipefail
export NO_COLOR=1

. "$HOME/.local/lib/dot/tests/helpers.sh"

SCRIPT="$HOME/.local/bin/et-tunnel"
tmp=$(_tmpdir)
bin="$tmp/bin"
test_home="$tmp/home"
log="$tmp/commands.log"
test_python=$(python3 -c 'import sys; print(sys.executable)')
real_bash=$(command -v bash)
real_ps=$(command -v ps)
printf -v real_ps_q '%q' "$real_ps"
real_mv=$(command -v mv)
printf -v real_mv_q '%q' "$real_mv"
mkdir -p "$bin" "$test_home"

_write_stub() {
  local path="$1"
  shift
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$@"
  } >"$path"
  chmod +x "$path"
}

_write_stub "$bin/lsof" \
  'if [[ -n "${ET_TUNNEL_TEST_LSOF_ESTABLISHED_PORT:-}" ]]; then' \
  '  for arg in "$@"; do' \
  '    if [[ "$arg" == "-iTCP:$ET_TUNNEL_TEST_LSOF_ESTABLISHED_PORT" ]]; then' \
  '      printf "p12345\\nn127.0.0.1:%s->127.0.0.1:443\\n" "$ET_TUNNEL_TEST_LSOF_ESTABLISHED_PORT"' \
  '      exit 0' \
  '    fi' \
  '  done' \
  'fi' \
  'if [[ -n "${ET_TUNNEL_TEST_LSOF_REMOTE_PORT:-}" ]]; then' \
  '  for arg in "$@"; do' \
  '    if [[ "$arg" == "-iTCP:$ET_TUNNEL_TEST_LSOF_REMOTE_PORT" ]]; then' \
  '      printf "p12345\\nn127.0.0.1:54321->127.0.0.1:%s\\n" "$ET_TUNNEL_TEST_LSOF_REMOTE_PORT"' \
  '      exit 0' \
  '    fi' \
  '  done' \
  'fi' \
  'if [[ -n "${ET_TUNNEL_TEST_LSOF_EXIT:-}" ]]; then' \
  '  if [[ "$ET_TUNNEL_TEST_LSOF_EXIT" == 0 ]]; then' \
  '    for arg in "$@"; do' \
  '      [[ "$arg" == -iTCP:* ]] && printf "p12345\\nn*:%s\\n" "${arg#-iTCP:}"' \
  '    done' \
  '  fi' \
  '  exit "$ET_TUNNEL_TEST_LSOF_EXIT"' \
  'fi' \
  'exit 1'
ss_bin="$tmp/ss-bin"
mkdir -p "$ss_bin"
ln -s "$real_bash" "$ss_bin/bash"
_write_stub "$ss_bin/ss" \
  'if [[ " $* " == *" -atn "* && " $* " == *" sport = :$ET_TUNNEL_TEST_SS_LISTENER_PORT "* ]]; then' \
  '  printf "LISTEN 0 128 127.0.0.1:%s 0.0.0.0:*\\n" "$ET_TUNNEL_TEST_SS_LISTENER_PORT"' \
  'fi'
_write_stub "$bin/et" \
  'printf "et\n" >>"$ET_TUNNEL_TEST_LOG"' \
  'previous= tunnel_spec=' \
  'for arg in "$@"; do' \
  '  printf "<%s>\n" "$arg" >>"$ET_TUNNEL_TEST_LOG"' \
  '  if [[ "$previous" == --command ]]; then printf "%s\n" "$arg" >"$ET_TUNNEL_TEST_REMOTE_COMMAND"; fi' \
  '  if [[ "$previous" == -t ]]; then tunnel_spec=$arg; fi' \
  '  previous="$arg"' \
  'done' \
  'printf "%s\n" "--" >>"$ET_TUNNEL_TEST_LOG"' \
  'count=0' \
  '[[ -r "$ET_TUNNEL_TEST_COUNT" ]] && read -r count <"$ET_TUNNEL_TEST_COUNT"' \
  'count=$((count + 1))' \
  'printf "%s\n" "$count" >"$ET_TUNNEL_TEST_COUNT"' \
  'if ((count <= ${ET_TUNNEL_TEST_COLLISIONS:-0})); then' \
  '  printf "%s\n" "$ET_TUNNEL_RETRY_MARKER" >&2' \
  'fi' \
  'if [[ -n "${ET_TUNNEL_TEST_FATAL_STATUS:-}" ]]; then' \
  '  token=${ET_TUNNEL_RETRY_MARKER#ET_TUNNEL_COLLISION:}' \
  '  token=${token%%:*}' \
  '  printf "ET_TUNNEL_FATAL:%s:%s:test-failure\n" "$token" "$ET_TUNNEL_TEST_FATAL_STATUS" >&2' \
  'fi' \
  'if [[ "${ET_TUNNEL_TEST_ECHO_ARGS:-0}" == 1 ]]; then printf "%s\n" "$@"; fi' \
  'if [[ -n "${ET_TUNNEL_TEST_BOOTSTRAP_PAYLOAD:-}" && "${ET_TUNNEL_TEST_EXIT:-0}" == 0 && "${ET_TUNNEL_TEST_COLLISIONS:-0}" == 0 && -z "${ET_TUNNEL_TEST_FATAL_STATUS:-}" ]]; then' \
  '  bootstrap_mapping=${tunnel_spec##*,}' \
  '  bootstrap_port=${bootstrap_mapping%%:*}' \
  '  "$ET_TUNNEL_TEST_PYTHON" - "$bootstrap_port" "$ET_TUNNEL_TEST_BOOTSTRAP_PAYLOAD" "$ET_TUNNEL_RETRY_MARKER" <<PY' \
  'import socket' \
  'import sys' \
  'port, output, retry_marker = sys.argv[1:]' \
  'token = retry_marker.split(":")[1]' \
  'server = socket.socket()' \
  'server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)' \
  'server.bind(("127.0.0.1", int(port)))' \
  'server.listen(2)' \
  'server.settimeout(5)' \
  'for _ in range(4):' \
  '    connection, _ = server.accept()' \
  '    connection.sendall(b"ET_TUNNEL_BOOTSTRAP\\n")' \
  '    received = b""' \
  '    while True:' \
  '        chunk = connection.recv(65536)' \
  '        if not chunk:' \
  '            break' \
  '        received += chunk' \
  '    if received.startswith(b"ET_TUNNEL_PAYLOAD:"):' \
  '        with open(output, "wb") as payload_file:' \
  '            payload_file.write(received)' \
  '        connection.close()' \
  '        break' \
  '    connection.close()' \
  'server.close()' \
  'PY' \
  'fi' \
  'exit "${ET_TUNNEL_TEST_EXIT:-0}"'
_write_stub "$bin/test-transport" \
  'printf "transport\n" >>"$ET_TUNNEL_TEST_LOG"' \
  'for arg in "$@"; do printf "<%s>\n" "$arg" >>"$ET_TUNNEL_TEST_LOG"; done' \
  'printf "%s\n" "$3" >"$ET_TUNNEL_TEST_REMOTE_COMMAND"' \
  'printf "%s\n" "--" >>"$ET_TUNNEL_TEST_LOG"'
_write_stub "$bin/blocking-transport" \
  'printf "%s\n" "$$" >"$ET_TUNNEL_TEST_TRANSPORT_PID"' \
  'sleep 300 &' \
  'child=$!' \
  'printf "%s\n" "$child" >"$ET_TUNNEL_TEST_TRANSPORT_CHILD_PID"' \
  'wait "$child"'
_write_stub "$bin/interactive-transport" \
  'printf "%s\n" "$$" >"$ET_TUNNEL_TEST_TRANSPORT_PID"' \
  'trap "" INT' \
  '[[ -z "${ET_TUNNEL_TEST_TRANSPORT_COUNT:-}" ]] || printf "1\n" >>"$ET_TUNNEL_TEST_TRANSPORT_COUNT"' \
  'ps -o pid=,pgid=,tpgid=,stat= -p "$$" >"$ET_TUNNEL_TEST_AUTH_STATE"' \
  'printf "Passcode: "' \
  'IFS= read -r answer' \
  'printf "%s\n" "$answer" >"$ET_TUNNEL_TEST_AUTH_RESULT"' \
  'exec sleep 300'
_write_stub "$bin/interactive-attached-transport" \
  'printf "%s\n" "$$" >"$ET_TUNNEL_TEST_TRANSPORT_PID"' \
  'printf "Passcode: "' \
  'if [[ -n "${ET_TUNNEL_TEST_PREAUTH_STOPPED:-}" ]]; then' \
  '  : >"$ET_TUNNEL_TEST_PREAUTH_STOPPED"' \
  '  kill -TTIN 0' \
  'fi' \
  'IFS= read -r answer' \
  'printf "%s\n" "$answer" >"$ET_TUNNEL_TEST_AUTH_RESULT"' \
  'mapping=$2' \
  'control_mapping=${mapping#*,}' \
  'control_port=${control_mapping%%:*}' \
  'token=${ET_TUNNEL_RETRY_MARKER#ET_TUNNEL_COLLISION:}' \
  'token=${token%%:*}' \
  'exec python3 - "$control_port" "$token" <<PY' \
  'import os' \
  'import signal' \
  'import socket' \
  'import sys' \
  'import time' \
  'resume_count = 0' \
  'def mark_resumed(_signum, _frame):' \
  '    global resume_count' \
  '    resume_count += 1' \
  '    with open(os.environ["ET_TUNNEL_TEST_CONTROL_RESUMED"], "w", encoding="utf-8") as output:' \
  '        output.write(str(resume_count))' \
  '    if resume_count <= 3 and os.environ.get("ET_TUNNEL_TEST_RESTOP_AFTER_CONT") == "1":' \
  '        os.killpg(os.getpgrp(), signal.SIGSTOP)' \
  'signal.signal(signal.SIGINT, lambda _signum, _frame: sys.exit(130))' \
  'signal.signal(signal.SIGCONT, signal.SIG_DFL)' \
  'signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGINT, signal.SIGCONT})' \
  'server = socket.socket()' \
  'server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)' \
  'server.bind(("127.0.0.1", int(sys.argv[1])))' \
  'server.listen(1)' \
  'open(os.environ["ET_TUNNEL_TEST_CONTROL_READY"], "wb").close()' \
  'connection, _ = server.accept()' \
  'connection.sendall(b"ET_TUNNEL_CONTROL\\n")' \
  'received = b""' \
  'with connection:' \
  '    while b"\\n" not in received:' \
  '        chunk = connection.recv(256)' \
  '        if not chunk:' \
  '            break' \
  '        received += chunk' \
  '    with open(os.environ["ET_TUNNEL_TEST_CONTROL_TOKEN"], "wb") as output:' \
  '        output.write(received)' \
  '    expected_token = f"{sys.argv[2]}\\n".encode()' \
  '    if received != expected_token:' \
  '        raise RuntimeError(f"unexpected token: {received!r}")' \
  '    time.sleep(float(os.environ.get("ET_TUNNEL_TEST_ACK_DELAY", "0")))' \
  '    connection.sendall(f"ET_TUNNEL_ATTACHED:{sys.argv[2]}\\n".encode())' \
  '    confirm = b""' \
  '    while b"\\n" not in confirm:' \
  '        chunk = connection.recv(256)' \
  '        if not chunk:' \
  '            break' \
  '        confirm += chunk' \
  '    expected = f"ET_TUNNEL_CONFIRM:{sys.argv[2]}\\n".encode()' \
  '    if confirm != expected:' \
  '        raise RuntimeError(f"unexpected confirmation: {confirm!r}")' \
  '    signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGCONT})' \
  '    signal.signal(signal.SIGCONT, mark_resumed)' \
  '    connection.sendall(f"ET_TUNNEL_CONFIRMED:{sys.argv[2]}\\n".encode())' \
  '    signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGCONT})' \
  '    resume_deadline = time.monotonic() + 20' \
  '    resumed = os.environ["ET_TUNNEL_TEST_CONTROL_RESUMED"]' \
  '    while not os.path.exists(resumed) and time.monotonic() < resume_deadline:' \
  '        time.sleep(0.01)' \
  '    if not os.path.exists(resumed):' \
  '        raise TimeoutError("transport did not resume after control handoff")' \
  '    connection.sendall(b"ET_TUNNEL_HELD\\n")' \
  '    open(os.environ["ET_TUNNEL_TEST_CONTROL_HELD"], "wb").close()' \
  '    try:' \
  '        while connection.recv(256):' \
  '            pass' \
  '    except ConnectionResetError:' \
  '        pass' \
  'open(os.environ["ET_TUNNEL_TEST_CONTROL_EOF"], "wb").close()' \
  'server.close()' \
  'PY'
_write_stub "$bin/worker-pgrp-transport" \
  'worker_pgid=$(ps -o pgid= -p "$PPID" | tr -d " ")' \
  'adapter_pgid=$(ps -o pgid= -p "$$" | tr -d " ")' \
  'printf "%s %s\n" "$worker_pgid" "$adapter_pgid" >"$ET_TUNNEL_TEST_WORKER_PGRPS"'
_write_stub "$bin/tstp-exit-transport" \
  'kill -TSTP 0' \
  'exit 127'
_write_stub "$bin/exit-127-transport" \
  'exit 127'
_write_stub "$bin/delayed-control-transport" \
  'printf "%s\n" "$$" >"$ET_TUNNEL_TEST_TRANSPORT_PID"' \
  'mapping=$2' \
  'control_mapping=${mapping#*,}' \
  'control_port=${control_mapping%%:*}' \
  'token=${ET_TUNNEL_RETRY_MARKER#ET_TUNNEL_COLLISION:}' \
  'token=${token%%:*}' \
  'sleep 1' \
  'python3 - "$control_port" "$ET_TUNNEL_TEST_CONTROL_TOKEN" "${ET_TUNNEL_TEST_CONTROL_READY:-}" "$token" "${ET_TUNNEL_TEST_CONTROL_ATTACHED:-}" "${ET_TUNNEL_TEST_CONTROL_EOF:-}" <<PY' \
  'import socket' \
  'import signal' \
  'import sys' \
  'signal.signal(signal.SIGINT, lambda _signum, _frame: sys.exit(130))' \
  'signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGINT})' \
  'server = socket.socket()' \
  'server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)' \
  'server.bind(("127.0.0.1", int(sys.argv[1])))' \
  'server.listen(1)' \
  'if sys.argv[3]:' \
  '    open(sys.argv[3], "wb").close()' \
  'connection, _ = server.accept()' \
  'connection.sendall(b"ET_TUNNEL_CONTROL\\n")' \
  'received = b""' \
  'with connection:' \
  '    while b"\n" not in received:' \
  '        chunk = connection.recv(256)' \
  '        if not chunk:' \
  '            break' \
  '        received += chunk' \
  '    with open(sys.argv[2], "wb") as output:' \
  '        output.write(received)' \
  '    expected_stop = f"ET_TUNNEL_STOP:{sys.argv[4]}\n".encode()' \
  '    expected_attach = f"{sys.argv[4]}\n".encode()' \
  '    if received == expected_stop:' \
  '        connection.sendall(f"ET_TUNNEL_STOPPED:{sys.argv[4]}\n".encode())' \
  '    elif received == expected_attach:' \
  '        connection.sendall(f"ET_TUNNEL_ATTACHED:{sys.argv[4]}\n".encode())' \
  '        confirm = b""' \
  '        while b"\n" not in confirm:' \
  '            chunk = connection.recv(256)' \
  '            if not chunk:' \
  '                break' \
  '            confirm += chunk' \
  '        expected_confirm = f"ET_TUNNEL_CONFIRM:{sys.argv[4]}\n".encode()' \
  '        if confirm == expected_confirm:' \
  '            connection.sendall(f"ET_TUNNEL_CONFIRMED:{sys.argv[4]}\n".encode())' \
  '            if sys.argv[5]:' \
  '                open(sys.argv[5], "wb").close()' \
  '    try:' \
  '        while connection.recv(256):' \
  '            pass' \
  '    except ConnectionResetError:' \
  '        pass' \
  'if sys.argv[6]:' \
  '    open(sys.argv[6], "wb").close()' \
  'server.close()' \
  'PY'
_write_stub "$bin/dropping-control-transport" \
  'printf "%s\n" "$$" >"$ET_TUNNEL_TEST_TRANSPORT_PID"' \
  'mapping=$2' \
  'control_mapping=${mapping#*,}' \
  'control_port=${control_mapping%%:*}' \
  'token=${ET_TUNNEL_RETRY_MARKER#ET_TUNNEL_COLLISION:}' \
  'token=${token%%:*}' \
  'python3 - "$control_port" "$token" <<PY' \
  'import os' \
  'import socket' \
  'import time' \
  'import sys' \
  'server = socket.socket()' \
  'server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)' \
  'server.bind(("127.0.0.1", int(sys.argv[1])))' \
  'server.listen(4)' \
  'open(os.environ["ET_TUNNEL_TEST_CONTROL_READY"], "wb").close()' \
  'while not os.path.exists(os.environ["ET_TUNNEL_TEST_CONTROL_GATE"]):' \
  '    time.sleep(0.05)' \
  'expected_stop = f"ET_TUNNEL_STOP:{sys.argv[2]}\n".encode()' \
  'dropped_stop = False' \
  'while True:' \
  '    connection, _ = server.accept()' \
  '    connection.sendall(b"ET_TUNNEL_CONTROL\\n")' \
  '    received = b""' \
  '    with connection:' \
  '        while b"\n" not in received:' \
  '            chunk = connection.recv(256)' \
  '            if not chunk:' \
  '                break' \
  '            received += chunk' \
  '        if received != expected_stop:' \
  '            continue' \
  '        if not dropped_stop:' \
  '            open(os.environ["ET_TUNNEL_TEST_CONTROL_DROPPED"], "wb").close()' \
  '            dropped_stop = True' \
  '            continue' \
  '        with open(os.environ["ET_TUNNEL_TEST_CONTROL_TOKEN"], "wb") as output:' \
  '            output.write(received)' \
  '        connection.sendall(f"ET_TUNNEL_STOPPED:{sys.argv[2]}\n".encode())' \
  '        while connection.recv(256):' \
  '            pass' \
  '        break' \
  'server.close()' \
  'PY'

_decode_remote_payload() {
  local wire="$1" magic token payload

  IFS=: read -r magic token payload <<<"$wire"
  [[ "$magic" == ET_TUNNEL_PAYLOAD && "$token" =~ ^[0-9a-f]{32}$ ]] || return 1
  if printf '%s' "$payload" | base64 --decode 2>/dev/null | gzip -dc 2>/dev/null; then
    return
  fi
  printf '%s' "$payload" | base64 -D 2>/dev/null | gzip -dc
}

_run_et_tunnel() {
  : >"$log"
  stdout="$tmp/stdout"
  stderr="$tmp/stderr"
  count="$tmp/count"
  remote_command_file="$tmp/remote-command"
  bootstrap_payload_file="$tmp/bootstrap-payload"
  run_exit=0
  : >"$count"
  : >"$remote_command_file"
  rm -f "$bootstrap_payload_file"
  PATH="${ET_TUNNEL_TEST_PATH:-$bin:/usr/bin:/bin}" \
    HOME="$test_home" \
    XDG_STATE_HOME="$test_home/state" \
    ET_TUNNEL_TEST_LOG="$log" \
    ET_TUNNEL_TEST_REMOTE_COMMAND="$remote_command_file" \
    ET_TUNNEL_TEST_BOOTSTRAP_PAYLOAD="$bootstrap_payload_file" \
    ET_TUNNEL_TEST_PYTHON="$test_python" \
    ET_TUNNEL_TEST_COUNT="$count" \
    ET_TUNNEL_TEST_COLLISIONS="${ET_TUNNEL_TEST_COLLISIONS:-0}" \
    ET_TUNNEL_TEST_EXIT="${ET_TUNNEL_TEST_EXIT:-0}" \
    ET_TUNNEL_TEST_FATAL_STATUS="${ET_TUNNEL_TEST_FATAL_STATUS:-}" \
    ET_TUNNEL_TEST_ECHO_ARGS="${ET_TUNNEL_TEST_ECHO_ARGS:-0}" \
    ET_TUNNEL_CLIENT_ID="${ET_TUNNEL_TEST_CLIENT_ID-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" \
    ET_TUNNEL_TEST_LSOF_EXIT="${ET_TUNNEL_TEST_LSOF_EXIT:-}" \
    ET_TUNNEL_TEST_LSOF_ESTABLISHED_PORT="${ET_TUNNEL_TEST_LSOF_ESTABLISHED_PORT:-}" \
    ET_TUNNEL_TEST_LSOF_REMOTE_PORT="${ET_TUNNEL_TEST_LSOF_REMOTE_PORT:-}" \
    ET_TUNNEL_TEST_SS_LISTENER_PORT="${ET_TUNNEL_TEST_SS_LISTENER_PORT:-}" \
    ET_TUNNEL_ET="${ET_TUNNEL_TEST_ET:-et}" \
    ET_TUNNEL_TRANSPORT="${ET_TUNNEL_TEST_TRANSPORT:-}" \
    bash "$SCRIPT" "$@" >"$stdout" 2>"$stderr" || run_exit=$?
}

_wait_for_file() {
  local path="$1"
  local _
  for _ in {1..80}; do
    [[ -s "$path" ]] && return
    sleep 0.1
  done
  return 1
}

_wait_for_marker() {
  local path="$1"
  local _
  for _ in {1..80}; do
    [[ -e "$path" ]] && return
    sleep 0.1
  done
  return 1
}

_process_has_stopped() {
  local pid="$1" state

  state=$(ps -o stat= -p "$pid" 2>/dev/null || true)
  [[ -z "$state" || "$state" == *Z* ]]
}

_wait_for_processes_stopped() {
  local _ pid all_stopped

  for _ in {1..80}; do
    all_stopped=1
    for pid in "$@"; do
      if ! _process_has_stopped "$pid"; then
        all_stopped=0
      fi
    done
    ((all_stopped == 1)) && return
    sleep 0.1
  done
  return 1
}
