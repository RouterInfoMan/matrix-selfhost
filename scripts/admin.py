"""Synapse admin helper. Runs INSIDE the synapse container, piped in by matrix.sh:

    docker compose exec -T synapse python - ELEMENT_URL invite [USES] [DAYS] < scripts/admin.py

Talks to the admin API as an `admin-bot` account that it creates on first use
with the registration shared secret. Its password and access token are kept in
/data/.admin-bot.json (i.e. data/synapse/ on the host).
"""
import hashlib
import hmac
import json
import secrets
import sys
import time
import urllib.error
import urllib.request

import yaml

BASE = "http://localhost:8008"
STATE = "/data/.admin-bot.json"
BOT = "admin-bot"
CFG = yaml.safe_load(open("/config/homeserver.yaml"))


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def call(method, path, body=None, token=None):
    req = urllib.request.Request(
        BASE + path,
        data=None if body is None else json.dumps(body).encode(),
        method=method,
        headers={"Content-Type": "application/json"},
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, json.loads(raw) if raw else {}


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except FileNotFoundError:
        return None


def save_state(state):
    with open(STATE, "w") as f:
        json.dump(state, f)


def register_bot():
    """Create the admin bot via shared-secret registration (works with sign-up closed)."""
    password = secrets.token_hex(32)
    _, r = call("GET", "/_synapse/admin/v1/register")
    nonce = r["nonce"]
    mac = hmac.new(CFG["registration_shared_secret"].encode(), digestmod=hashlib.sha1)
    mac.update(b"\x00".join([nonce.encode(), BOT.encode(), password.encode(), b"admin"]))
    code, r = call("POST", "/_synapse/admin/v1/register", {
        "nonce": nonce, "username": BOT, "password": password,
        "admin": True, "mac": mac.hexdigest(),
    })
    if code == 400 and r.get("errcode") == "M_USER_IN_USE":
        die(f"@{BOT} already exists but its saved login ({STATE}) is missing. "
            f"Set BOT in scripts/admin.py to a new name and retry")
    if code != 200:
        die(f"could not create @{BOT}: {code} {r}")
    state = {"password": password, "access_token": r["access_token"]}
    save_state(state)
    return state


def login(state):
    code, r = call("POST", "/_matrix/client/v3/login", {
        "type": "m.login.password",
        "identifier": {"type": "m.id.user", "user": BOT},
        "password": state["password"],
        "initial_device_display_name": "matrix.sh",
    })
    if code != 200:
        die(f"@{BOT} could not log in: {code} {r}")
    state["access_token"] = r["access_token"]
    save_state(state)


def admin(method, path, body=None):
    """Admin API call as the bot, creating it / refreshing its login as needed."""
    state = load_state() or register_bot()
    code, r = call(method, "/_synapse/admin" + path, body, state["access_token"])
    if code == 401:
        login(state)
        code, r = call(method, "/_synapse/admin" + path, body, state["access_token"])
    if code != 200:
        die(f"{method} {path} failed: {code} {r}")
    return r


def fmt_expiry(ms):
    return "never" if ms is None else time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(ms / 1000))


def cmd_invite(uses="1", days="7"):
    body = {"uses_allowed": None if uses == "0" else int(uses)}
    if days != "0":
        body["expiry_time"] = int((time.time() + float(days) * 86400) * 1000)
    t = admin("POST", "/v1/registration_tokens/new", body)
    name = CFG["server_name"]
    uses_txt = "unlimited" if t["uses_allowed"] is None else t["uses_allowed"]
    print(f"""Invite token: {t['token']}
  uses: {uses_txt}, expires: {fmt_expiry(t['expiry_time'])}

Send this to the person you're inviting:
  Sign up at {ELEMENT_URL} -> "Create account"
  (or in any Matrix app, with server "{name}"),
  and enter this registration token when asked: {t['token']}""")


def cmd_invites():
    tokens = admin("GET", "/v1/registration_tokens")["registration_tokens"]
    if not tokens:
        print("No invite tokens.")
        return
    print(f"{'TOKEN':<20} {'USED':>5} {'ALLOWED':>8}  EXPIRES")
    for t in tokens:
        allowed = "inf" if t["uses_allowed"] is None else t["uses_allowed"]
        print(f"{t['token']:<20} {t['completed']:>5} {allowed:>8}  {fmt_expiry(t['expiry_time'])}")


def cmd_revoke(token):
    admin("DELETE", f"/v1/registration_tokens/{token}")
    print(f"Revoked {token}")


# argv: ["-", ELEMENT_URL, command, args...]
cmds = {"invite": cmd_invite, "invites": cmd_invites, "revoke": cmd_revoke}
if len(sys.argv) < 3 or sys.argv[2] not in cmds:
    die("unknown command")
ELEMENT_URL, command, args = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    cmds[command](*args)
except TypeError:
    die(f"wrong arguments for {command}")
