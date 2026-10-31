#!/usr/bin/env python3
"""Recover ordinary publication lifecycle from exact queue/state/receipt evidence.

Never invokes the Publisher or writes CMS/source files. The intake lock prevents
lost updates against incremental intake; every row is validated before one atomic
ledger replacement. Repeated runs preserve the original publication identity.
"""
import argparse
import copy
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile


def read_json(path):
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("JSON object required: " + str(path))
    return value


def atomic_json(path, value):
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".tmp.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o640)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def timestamp(value):
    parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp requires timezone")
    return parsed


def publisher_hash(article):
    # Match PHP JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES, including
    # its default escaping of Unicode line/paragraph separators.
    raw = json.dumps(article, ensure_ascii=False, separators=(",", ":"))
    raw = raw.replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    return hashlib.sha256(raw.encode()).hexdigest()


def plan(queue, state, ledger, receipts):
    result = copy.deepcopy(ledger)
    records = result.get("records")
    if not isinstance(records, dict):
        raise ValueError("intake ledger records missing")
    states = state.get("articles", {})
    if not isinstance(states, dict):
        raise ValueError("publisher articles map invalid")
    seen = set()
    keys_seen = set()
    changed = []
    for file in sorted(queue.glob("*.json")):
        q = read_json(file)
        rev = q.get("source_revision_id")
        key = q.get("article_key", "")
        batch = str(q.get("source_batch_id", ""))
        if not batch.startswith("DAILY-") or "cf50" in str(q.get("source_article_id", "")).lower():
            raise ValueError("ordinary queue contains non-DAILY/CF50 content")
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{2,79}", key) or rev in seen or key in keys_seen:
            raise ValueError("duplicate or invalid queue identity")
        seen.add(rev)
        keys_seen.add(key)
        if q.get("publication_state") != "scheduled":
            raise ValueError("immutable queue must remain scheduled")
        timestamp(q.get("publish_at"))
        row = records.get(rev)
        if not isinstance(row, dict):
            raise ValueError("queue revision absent from intake ledger: " + str(rev))
        for dest, source in (("revision_id", "source_revision_id"), ("article_id", "source_article_id"),
                             ("content_hash", "source_content_hash"), ("fingerprint", "source_fingerprint"),
                             ("source_batch_id", "source_batch_id")):
            if not q.get(source) or row.get(dest) != q.get(source):
                raise ValueError("queue/ledger identity mismatch: " + dest)
        if hashlib.sha256(str(q.get("content", "")).encode()).hexdigest() != q["source_content_hash"]:
            raise ValueError("queue body hash mismatch")
        entry = states.get(key, {})
        published = entry.get("status") == "published"
        if not published and row.get("lifecycle_state") == "published":
            raise ValueError("refusing published ledger downgrade")
        if not published and (row.get("cms_id") is not None or row.get("published_at")):
            raise ValueError("unpublished state conflicts with ledger publication identity")
        updated = copy.deepcopy(row)
        scheduled_at = q.get("promoted_at") or q["publish_at"]
        timestamp(scheduled_at)
        if not updated.get("scheduled_at"):
            updated["scheduled_at"] = scheduled_at
        updated["lifecycle_state"] = "published" if published else "scheduled"
        if published:
            cms = entry.get("cms_id")
            if not isinstance(cms, int) or isinstance(cms, bool) or cms <= 0:
                raise ValueError("published state CMS ID missing")
            if entry.get("content_hash") != publisher_hash(q):
                raise ValueError("published state hash mismatch")
            receipt = read_json(receipts / (key + "." + str(cms) + ".json"))
            expected = {"schema_version": 1, "receipt_type": "publication_receipt",
                        "article_id": q["source_article_id"], "article_key": key,
                        "fingerprint": q["source_fingerprint"], "content_hash": q["source_content_hash"],
                        "cms_id": cms, "published_url": "https://www.laocaimi.org/index.php?c=show&id=" + str(cms),
                        "publisher_article_hash": entry["content_hash"], "source_file": file.name}
            for field, value in expected.items():
                if receipt.get(field) != value:
                    raise ValueError("publication receipt mismatch: " + field)
            published_at = receipt.get("published_at")
            if timestamp(published_at) != timestamp(entry.get("published_at")):
                raise ValueError("publication time mismatch")
            if timestamp(published_at) < timestamp(q["publish_at"]):
                raise ValueError("publication precedes scheduled time")
            fields = ["article_id", "article_key", "fingerprint", "content_hash", "cms_id", "published_url",
                      "published_at", "publisher_article_hash", "source_file"]
            rid = hashlib.sha256("|".join(["v1"] + [str(receipt[k]) for k in fields]).encode()).hexdigest()
            if receipt.get("receipt_id") != rid:
                raise ValueError("publication receipt ID mismatch")
            if row.get("cms_id") not in (None, cms):
                raise ValueError("ledger already references another CMS ID")
            if row.get("published_at") and timestamp(row["published_at"]) != timestamp(published_at):
                raise ValueError("ledger publication time conflict")
            updated.update({"cms_id": cms, "published_at": published_at,
                            "published_url": receipt["published_url"], "publication_receipt_id": rid})
        if updated != row:
            records[rev] = updated
            changed.append(rev)
    return result, changed


def reconcile(queue, state_path, ledger_path, receipts, lock_path, commit=False):
    lock_path.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
    with lock_path.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        ledger = read_json(ledger_path)
        state = read_json(state_path) if state_path.is_file() else {"articles": {}}
        result, changed = plan(queue, state, ledger, receipts)
        if changed and commit:
            result["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
            atomic_json(ledger_path, result)
        return {"status": "PASS", "mode": "commit" if commit else "dry-run",
                "changed_count": len(changed), "changed_revision_ids": changed,
                "cms_write": False, "publisher_invoked": False}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--queue", type=Path, required=True)
    p.add_argument("--state", type=Path, required=True)
    p.add_argument("--ledger", type=Path, default=Path("/var/lib/xyptdq-content/intake/state.json"))
    p.add_argument("--receipts", type=Path, required=True)
    p.add_argument("--lock", type=Path, default=Path("/var/lib/xyptdq-content/intake/intake.lock"))
    p.add_argument("--commit", action="store_true")
    a = p.parse_args()
    if not a.queue.is_dir():
        raise ValueError("ordinary queue missing")
    print(json.dumps(reconcile(a.queue, a.state, a.ledger, a.receipts, a.lock, a.commit), sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("[publication-ledger] ERROR: " + str(exc), file=sys.stderr)
        sys.exit(1)
