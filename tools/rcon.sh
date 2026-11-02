#!/bin/bash
# rcon.sh - run a console command on the server, over rcon, from inside its
# own container.
#
#   tools/rcon.sh status
#   tools/rcon.sh changelevel pl_upward
#
# UP TO v1 THE README SAID `docker compose exec tf2-server rcon status`. The
# image it pinned had no rcon program in it, so that command could only answer
# "executable file not found". This one is tested against the real server in
# CI: `status` must come back with the server's hostname line, and a wrong
# password must be refused.
#
# FROM INSIDE THE CONTAINER, so the address and port are the server itself
# whatever the network looks like outside: published on the host, behind a
# relay, or on a bridge nobody has mapped. srcds binds the address of its
# interface, not 0.0.0.0, so that address is tried before loopback. python3 is
# in the image (LinuxGSM depends on it).
#
# THE PASSWORD TRAVELS ON STDIN, never in argv, where `ps` on the host would
# show it to every user. It is read from .env, the file the server got it from.
#
# Read whole before it runs: one brace group, ending in exit
# (tools/steam-uptodate.sh, "READ WHOLE BEFORE IT RUNS", says why).
{
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

[ "$#" -gt 0 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
COMPOSE_FILE=${TF2_COMPOSE_FILE:-tf2-server-docker-compose.yml}
PROJECT=${COMPOSE_PROJECT_NAME:-tf2}
PORT=$(sed -n 's/^TF2_SERVER_PORT=\([0-9]*\).*/\1/p' .env 2>/dev/null | tail -1)
PORT=${PORT:-27015}
pw=$(sed -n 's/^TF2_SERVER_RCON_PASSWORD=//p' .env 2>/dev/null | tail -1)
pw=${pw%\"}; pw=${pw#\"}; pw=${pw%\'}; pw=${pw#\'}
[ -n "$pw" ] || { echo "TF2_SERVER_RCON_PASSWORD is not set in .env" >&2; exit 1; }

printf '%s\n' "$pw" | docker compose -f "$COMPOSE_FILE" -p "$PROJECT" exec -T tf2-server python3 -c '
import socket, struct, sys
port, cmd = int(sys.argv[1]), " ".join(sys.argv[2:])
pw = sys.stdin.readline().rstrip("\n")
def packet(i, kind, body):
    b = struct.pack("<ii", i, kind) + body.encode() + b"\x00\x00"
    return struct.pack("<i", len(b)) + b
def take(s, n):
    d = b""
    while len(d) < n:
        c = s.recv(n - len(d))
        if not c:
            raise EOFError("the server closed the connection")
        d += c
    return d
def read(s):
    n = struct.unpack("<i", take(s, 4))[0]
    d = take(s, n)
    i, kind = struct.unpack("<ii", d[:8])
    return i, kind, d[8:-2]
ips = []
try:
    ips.append(socket.gethostbyname(socket.gethostname()))
except OSError:
    pass
ips.append("127.0.0.1")
s = None
for ip in dict.fromkeys(ips):
    try:
        s = socket.create_connection((ip, port), timeout=10)
        break
    except OSError:
        continue
if s is None:
    sys.exit("rcon: nothing accepted a connection on port %d" % port)
s.sendall(packet(1, 3, pw))                   # SERVERDATA_AUTH
while True:
    i, kind, _ = read(s)
    if kind == 2:                             # SERVERDATA_AUTH_RESPONSE
        break
if i == -1:
    print("rcon: the server refused the password", file=sys.stderr)
    sys.exit(2)
s.sendall(packet(2, 2, cmd))                  # SERVERDATA_EXECCOMMAND
# An empty response packet after the command comes back after all of its
# output, however many packets that takes: the end marker.
s.sendall(packet(3, 0, ""))
out = b""
while True:
    i, kind, body = read(s)
    if i == 3:
        break
    out += body
sys.stdout.write(out.decode("utf-8", "replace"))
' "$PORT" "$@"
exit
}
