"""
Usage Tracker Service
=====================
Lightweight FastAPI service that proxies and logs all API calls to Open WebUI,
tracking token consumption per API key for billing purposes.
"""

import json
import os
import sqlite3
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

# ─── Config ──────────────────────────────────────────────────────────────────
OPENWEBUI_URL  = os.getenv("OPENWEBUI_URL", "http://open-webui:8080")
TRACKER_API_KEY = os.getenv("TRACKER_API_KEY", "tracker-secret")
DATA_DIR       = Path("/app/data")
DATA_DIR.mkdir(exist_ok=True)
DB_PATH        = DATA_DIR / "usage.db"

# ─── DB Init ─────────────────────────────────────────────────────────────────
def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS usage_logs (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            api_key      TEXT NOT NULL,
            model        TEXT,
            prompt_tokens   INTEGER DEFAULT 0,
            completion_tokens INTEGER DEFAULT 0,
            total_tokens INTEGER DEFAULT 0,
            cost_usd     REAL DEFAULT 0.0,
            endpoint     TEXT,
            status_code  INTEGER,
            latency_ms   INTEGER,
            created_at   TEXT DEFAULT (datetime('now'))
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS api_keys (
            key_hash     TEXT PRIMARY KEY,
            label        TEXT,
            quota_tokens INTEGER DEFAULT 1000000,
            used_tokens  INTEGER DEFAULT 0,
            is_active    INTEGER DEFAULT 1,
            created_at   TEXT DEFAULT (datetime('now'))
        )
    """)
    conn.commit()
    conn.close()

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield

app = FastAPI(title="LLM Usage Tracker", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Auth ─────────────────────────────────────────────────────────────────────
def require_tracker_key(x_tracker_key: str = Header(...)):
    if x_tracker_key != TRACKER_API_KEY:
        raise HTTPException(status_code=403, detail="Invalid tracker key")
    return x_tracker_key

# ─── Helpers ──────────────────────────────────────────────────────────────────
def log_usage(api_key: str, model: str, prompt_tokens: int,
              completion_tokens: int, endpoint: str, status_code: int,
              latency_ms: int):
    total = prompt_tokens + completion_tokens
    # Rough cost estimate: $0.002 per 1K tokens (adjust per model)
    cost  = total / 1000 * 0.002

    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        INSERT INTO usage_logs
            (api_key, model, prompt_tokens, completion_tokens,
             total_tokens, cost_usd, endpoint, status_code, latency_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (api_key, model, prompt_tokens, completion_tokens,
          total, cost, endpoint, status_code, latency_ms))
    conn.execute("""
        UPDATE api_keys SET used_tokens = used_tokens + ?
        WHERE key_hash = ?
    """, (total, hash(api_key)))
    conn.commit()
    conn.close()

# ─── Dashboard endpoints ───────────────────────────────────────────────────────
@app.get("/stats/summary")
def get_summary(_: str = Depends(require_tracker_key)):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    total   = conn.execute("SELECT COUNT(*) as c, SUM(total_tokens) as t, SUM(cost_usd) as cost FROM usage_logs").fetchone()
    per_key = conn.execute("""
        SELECT api_key, COUNT(*) as calls, SUM(total_tokens) as tokens, SUM(cost_usd) as cost
        FROM usage_logs GROUP BY api_key ORDER BY tokens DESC LIMIT 20
    """).fetchall()
    per_model = conn.execute("""
        SELECT model, COUNT(*) as calls, SUM(total_tokens) as tokens
        FROM usage_logs GROUP BY model ORDER BY tokens DESC
    """).fetchall()
    conn.close()

    return {
        "total_calls":  total["c"]    or 0,
        "total_tokens": total["t"]    or 0,
        "total_cost_usd": round(total["cost"] or 0, 4),
        "by_api_key": [dict(r) for r in per_key],
        "by_model":   [dict(r) for r in per_model],
    }

@app.get("/stats/timeseries")
def get_timeseries(days: int = 7, _: str = Depends(require_tracker_key)):
    since = (datetime.utcnow() - timedelta(days=days)).isoformat()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("""
        SELECT date(created_at) as day, SUM(total_tokens) as tokens,
               COUNT(*) as calls, SUM(cost_usd) as cost
        FROM usage_logs WHERE created_at >= ?
        GROUP BY day ORDER BY day
    """, (since,)).fetchall()
    conn.close()
    return [dict(r) for r in rows]

@app.get("/health")
def health():
    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}
