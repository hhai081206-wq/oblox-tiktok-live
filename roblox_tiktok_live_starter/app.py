import logging
import os
import queue
import re
import threading
import time

from flask import Flask, jsonify, request
from TikTokLive import TikTokLiveClient
from TikTokLive.events import CommentEvent, ConnectEvent, DisconnectEvent

# Required Render environment variables:
# TIKTOK_USERNAME = broadcaster's TikTok username, with or without @
# BRIDGE_KEY = a long random secret; the same value goes into Roblox ServerStorage/BridgeKey

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
log = logging.getLogger("roblox-tiktok-bridge")

TIKTOK_USERNAME = os.getenv("TIKTOK_USERNAME", "").strip().lstrip("@")
BRIDGE_KEY = os.getenv("BRIDGE_KEY", "").strip()

if not TIKTOK_USERNAME:
    raise RuntimeError("Missing required environment variable: TIKTOK_USERNAME")
if not BRIDGE_KEY:
    raise RuntimeError("Missing required environment variable: BRIDGE_KEY")

app = Flask(__name__)
pending = queue.Queue(maxsize=50)
lock = threading.Lock()
recent_usernames = set()
client = TikTokLiveClient(unique_id=TIKTOK_USERNAME)
client_thread = None
client_thread_lock = threading.Lock()
client_status = {
    "state": "starting",
    "last_error": None,
    "connected_at": None,
    "last_comment_at": None,
}

JOIN_PATTERN = re.compile(r"!join\s+([A-Za-z0-9_]{3,20})", re.IGNORECASE)


@client.on(ConnectEvent)
async def on_connect(event: ConnectEvent):
    client_status["state"] = "connected"
    client_status["last_error"] = None
    client_status["connected_at"] = time.time()
    log.info("TIKTOK_CONNECTED username=@%s room_id=%s",
             TIKTOK_USERNAME, getattr(client, "room_id", None))


@client.on(DisconnectEvent)
async def on_disconnect(event: DisconnectEvent):
    client_status["state"] = "disconnected"
    log.warning("TIKTOK_DISCONNECTED username=@%s", TIKTOK_USERNAME)


@client.on(CommentEvent)
async def on_comment(event: CommentEvent):
    comment = (getattr(event, "comment", "") or "").strip()
    nickname = getattr(getattr(event, "user", None), "nickname", "unknown")
    client_status["last_comment_at"] = time.time()
    log.info("TIKTOK_COMMENT nickname=%r comment=%r", nickname, comment)

    match = JOIN_PATTERN.fullmatch(comment)
    if not match:
        return

    username = match.group(1)
    key = username.lower()

    with lock:
        if key in recent_usernames:
            log.info("JOIN_DUPLICATE username=%s", username)
            return
        if pending.full():
            log.warning("JOIN_QUEUE_FULL username=%s", username)
            return
        recent_usernames.add(key)
        pending.put(username)

    log.info("AVATAR_QUEUED username=%s", username)


def run_tiktok_client():
    client_status["state"] = "connecting"
    log.info("TIKTOK_CONNECTING username=@%s", TIKTOK_USERNAME)
    try:
        client.run()
        # run() normally blocks while the LIVE connection is active.
        client_status["state"] = "stopped"
        log.warning("TIKTOK_CLIENT_STOPPED")
    except Exception as exc:
        client_status["state"] = "error"
        client_status["last_error"] = repr(exc)
        log.exception("TIKTOK_CONNECTION_FAILED")


def start_tiktok_thread():
    global client_thread
    with client_thread_lock:
        if client_thread is not None and client_thread.is_alive():
            return
        client_thread = threading.Thread(
            target=run_tiktok_client,
            name="TikTokLiveClient",
            daemon=True,
        )
        client_thread.start()


@app.get("/")
def home():
    return (
        "TikTok-to-Roblox bridge is running. "
        "Open /health for status; do not share your bridge key.",
        200,
    )


@app.get("/health")
def health():
    # Never expose BRIDGE_KEY in responses.
    return jsonify({
        "status": "ok",
        "tiktok_username_configured": bool(TIKTOK_USERNAME),
        "tiktok_state": client_status["state"],
        "last_error": client_status["last_error"],
        "queue_size": pending.qsize(),
        "last_comment_received": client_status["last_comment_at"] is not None,
    })


@app.get("/next")
def next_avatar():
    supplied_key = request.headers.get("X-Bridge-Key", "")
    if not supplied_key or supplied_key != BRIDGE_KEY:
        return jsonify({"error": "unauthorized"}), 401

    try:
        username = pending.get_nowait()
    except queue.Empty:
        username = None

    if username:
        with lock:
            recent_usernames.discard(username.lower())
        log.info("AVATAR_DELIVERED username=%s", username)

    return jsonify({"username": username})


# Render starts this module with Gunicorn, so start the TikTok thread at import.
# Configure exactly one Gunicorn worker in render.yaml to avoid duplicate clients.
start_tiktok_thread()
