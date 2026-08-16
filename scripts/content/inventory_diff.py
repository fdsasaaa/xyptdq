#!/usr/bin/env python3
"""Read-only incremental inventory diff for article-factory -> website Draft intake.

Only formal website_public_release revisions on source main are considered. The
script never writes CMS data, Drafts, publish_at, Scheduled queues, Publisher
state or cron. It also enforces the website-side CF50 final-five release gate.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Set


def load_json(path: Path) -> Dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError("invalid JSON: %s: %s" % (path, exc)) from exc
    if not isinstance(data, dict):
        raise RuntimeError("JSON root must be object: %s" % path)
    return data


def git_output(repo: Path, *args: str) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(repo)] + list(args), text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception as exc:
        raise RuntimeError("git %s failed for %s" % (" ".join(args), repo)) from exc


def verify_source_main(repo: Path) -> str:
    head = git_output(repo, "rev-parse", "HEAD")
    branch = git_output(repo, "branch", "--show-current")
    try:
        origin_main = git_output(repo, "rev-parse", "refs/remotes/origin/main")
    except RuntimeError:
        origin_main = ""
    if branch == "main":
        if origin_main and origin_main != head:
            raise RuntimeError("source main checkout is not synchronized with origin/main")
        return head
    if origin_main and origin_main == head:
        return head
    raise RuntimeError("source checkout is not proven to be article repository main")


def scan_existing_ingress(root: Path) -> Dict[str, Dict[str, Any]]:
    found: Dict[str, Dict[str, Any]] = {}
    if not root.is_dir():
        return found
    for path in sorted(root.rglob("*.public-r*.json")):
        data = load_json(path)
        revision_id = str(data.get("revision_id") or "")
        if not revision_id:
            continue
        current = {
            "article_id": str(data.get("article_id") or ""),
            "revision_id": revision_id,
            "content_hash": str(data.get("content_hash") or ""),
            "fingerprint": str(data.get("fingerprint") or ""),
            "primary_keyword": str(data.get("primary_keyword") or ""),
            "slug": str(data.get("slug") or ""),
            "source_batch_id": str(data.get("source_batch_id") or ""),
            "site_category_key": str(data.get("site_category_key") or ""),
            "path": str(path),
        }
        if not current["content_hash"]:
            raise RuntimeError("website ingress revision lacks content_hash: %s" % revision_id)
        prior = found.get(revision_id)
        if prior and prior != current:
            raise RuntimeError("conflicting website ingress identity for revision %s" % revision_id)
        found[revision_id] = current
    return found


def load_ledger(path: Path) -> Dict[str, Dict[str, Any]]:
    if not path.exists():
        return {}
    data = load_json(path)
    records = data.get("records", {})
    if not isinstance(records, dict):
        raise RuntimeError("intake ledger records must be an object keyed by revision_id")
    clean: Dict[str, Dict[str, Any]] = {}
    for raw_key, value in records.items():
        revision_id = str(raw_key)
        if not isinstance(value, dict):
            raise RuntimeError("intake ledger record is not an object: %s" % revision_id)
        if str(value.get("revision_id") or revision_id) != revision_id:
            raise RuntimeError("intake ledger revision key/record mismatch: %s" % revision_id)
        if not str(value.get("content_hash") or ""):
            raise RuntimeError("intake ledger revision lacks content_hash: %s" % revision_id)
        clean[revision_id] = value
    return clean


def validate_entry(source: Path, entry: Dict[str, Any]) -> Dict[str, Any]:
    required = ["article_id", "revision_id", "content_hash", "fingerprint", "primary_keyword", "slug", "path"]
    missing = [key for key in required if not str(entry.get(key) or "")]
    if missing:
        raise RuntimeError("manifest entry missing fields %s: %s" % (missing, entry.get("article_id")))
    rel = Path(str(entry["path"]))
    if rel.is_absolute() or ".." in rel.parts or rel.suffix.lower() != ".json":
        raise RuntimeError("unsafe manifest path: %s" % rel)
    revision_path = (source / rel).resolve()
    source_real = source.resolve()
    if source_real not in revision_path.parents or not revision_path.is_file():
        raise RuntimeError("manifest revision path missing/escaped source repo: %s" % rel)
    revision = load_json(revision_path)
    if revision.get("revision_kind") != "website_public_release":
        raise RuntimeError("revision kind is not website_public_release: %s" % rel)
    for key in ["article_id", "revision_id", "content_hash", "fingerprint", "primary_keyword", "slug"]:
        if str(revision.get(key) or "") != str(entry.get(key) or ""):
            raise RuntimeError("manifest/revision mismatch for %s: %s" % (key, rel))
    if str(revision.get("site_category_key") or "") != "tzjq":
        raise RuntimeError("unexpected website category carrier: %s" % rel)
    review = revision.get("public_release_review") or {}
    if not isinstance(review, dict) or review.get("status") != "approved":
        raise RuntimeError("public-release review not approved: %s" % rel)
    return {
        "article_id": str(revision["article_id"]),
        "revision_id": str(revision["revision_id"]),
        "content_hash": str(revision["content_hash"]),
        "fingerprint": str(revision["fingerprint"]),
        "primary_keyword": str(revision["primary_keyword"]),
        "slug": str(revision["slug"]),
        "site_category_key": str(revision["site_category_key"]),
        "source_batch_id": str(revision.get("source_batch_id") or ""),
        "source_path": str(rel).replace("\\", "/"),
    }


def manifest_count(manifest: Dict[str, Any], articles: List[Any]) -> int:
    for key in ("approved_public_release_count", "website_ready_count", "public_release_count", "article_count"):
        raw = manifest.get(key)
        if raw is not None:
            return int(raw)
    return len(articles)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-repo", required=True)
    parser.add_argument("--website-repo", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--ledger", default="/var/lib/xyptdq-content/intake/state.json")
    parser.add_argument("--output", default="-")
    args = parser.parse_args()

    source = Path(args.source_repo)
    website = Path(args.website_repo)
    policy = load_json(website / "config/content_inventory_policy.json")
    sync = load_json(website / "config/content_source_sync_policy.json")
    if sync.get("source_repository") != policy.get("source_repository") or sync.get("source_ref") != "main":
        raise RuntimeError("inventory and source-sync policies disagree on source repository/ref")
    if not (source / ".git").exists():
        raise RuntimeError("source repository checkout missing")
    source_commit = verify_source_main(source)

    cf50 = policy.get("cf50_terminal_baseline") or {}
    frozen: Set[str] = set(cf50.get("final5_frozen_pending_issue_264") or [])
    final5_authorized = cf50.get("release_authorized") is True
    if not final5_authorized:
        required = str(cf50.get("required_exact_machine_conclusion") or "")
        if len(frozen) != 5 or required != "CF50_FINAL_5_RELEASE=AUTHORIZED":
            raise RuntimeError("CF50 final-five freeze policy is incomplete or inconsistent")

    official: Dict[str, Dict[str, Any]] = {}
    manifest_rows: List[Dict[str, Any]] = []
    manifest_root = source / str(policy["source_manifest_root"])
    if not manifest_root.is_dir():
        raise RuntimeError("source public-release manifest root missing")

    for manifest_path in sorted(manifest_root.glob("*.json")):
        manifest = load_json(manifest_path)
        batch_id = str(manifest.get("source_batch_id") or manifest.get("batch_id") or "")
        articles = manifest.get("articles")
        if not isinstance(articles, list):
            raise RuntimeError("manifest articles must be list: %s" % manifest_path.name)
        count = manifest_count(manifest, articles)
        if count != len(articles):
            raise RuntimeError("manifest count mismatch: %s" % manifest_path.name)

        manifest_ids = {str(row.get("article_id") or "") for row in articles if isinstance(row, dict)}
        frozen_seen = sorted(x for x in manifest_ids if x in frozen)
        if frozen_seen and not final5_authorized:
            raise RuntimeError(
                "Issue #264 has not authorized frozen CF50 final-five public inventory: " + ",".join(frozen_seen)
            )

        terminal_cf50 = batch_id == str(cf50.get("source_batch_id") or "")
        if terminal_cf50:
            baseline = int(cf50.get("website_ready_public_r1_count") or 0)
            full = int(cf50.get("immutable_approved_parent_count") or 0)
            if count == baseline:
                eligible = True
                reason = "cf50_valid_45_waiting_state"
            elif final5_authorized and count == full:
                eligible = manifest.get("status") == "complete" and manifest.get("website_batch_ingestion_allowed") is True
                reason = "cf50_authorized_full_inventory" if eligible else "cf50_authorized_but_manifest_not_formal"
            else:
                eligible = False
                reason = "cf50_count_not_allowed_by_current_issue_264_gate"
        else:
            eligible = (
                manifest.get("status") == "complete"
                and manifest.get("website_batch_ingestion_allowed") is True
                and count >= int((policy.get("upstream_contract") or {}).get("daily_minimum_formal_batch_count") or 10)
            )
            reason = "formal_complete_manifest" if eligible else "not_formal_inventory"

        manifest_rows.append({
            "manifest": manifest_path.name,
            "batch_id": batch_id,
            "count": count,
            "eligible": eligible,
            "reason": reason,
            "frozen_final5_present": frozen_seen,
        })
        if not eligible:
            continue
        for raw in articles:
            if not isinstance(raw, dict):
                raise RuntimeError("non-object manifest article: %s" % manifest_path.name)
            record = validate_entry(source, raw)
            revision_id = record["revision_id"]
            prior = official.get(revision_id)
            if prior and prior != record:
                raise RuntimeError("same revision_id has conflicting official identity: %s" % revision_id)
            official[revision_id] = record

    slug_owner: Dict[str, str] = {}
    keyword_owner: Dict[str, str] = {}
    article_owner: Dict[str, str] = {}
    for revision_id, record in official.items():
        slug = record["slug"]
        keyword = record["primary_keyword"]
        article_id = record["article_id"]
        if slug in slug_owner and slug_owner[slug] != revision_id:
            raise RuntimeError("duplicate slug across official inventory: %s" % slug)
        if keyword in keyword_owner and keyword_owner[keyword] != revision_id:
            raise RuntimeError("duplicate Primary Keyword across official inventory: %s" % keyword)
        if article_id in article_owner and article_owner[article_id] != revision_id:
            raise RuntimeError("multiple active formal revisions for one article_id: %s" % article_id)
        slug_owner[slug] = revision_id
        keyword_owner[keyword] = revision_id
        article_owner[article_id] = revision_id

    ingress = scan_existing_ingress(website / "content/ingress/public-release")
    ledger = load_ledger(Path(args.ledger))
    known: Set[str] = set(ingress) | set(ledger)
    drift: List[str] = []
    for revision_id, record in official.items():
        for existing in (ingress.get(revision_id), ledger.get(revision_id)):
            if not existing:
                continue
            if str(existing.get("content_hash") or "") != record["content_hash"]:
                drift.append(revision_id)
    if drift:
        raise RuntimeError("content-hash drift for known revision(s): " + ",".join(sorted(set(drift))))

    candidates = [official[r] for r in sorted(official) if r not in known]
    result = {
        "schema_version": 1,
        "task": "inventory_diff",
        "status": "PASS",
        "read_only": True,
        "source_repository": policy["source_repository"],
        "source_ref": "main",
        "source_commit": source_commit,
        "A_upstream_official_ready": len(official),
        "website_ingress_known": len(set(official) & set(ingress)),
        "ledger_known": len(set(official) & set(ledger)),
        "new_draft_candidates": len(candidates),
        "cf50_final5_release_authorized": final5_authorized,
        "cf50_frozen_final5_count": len(frozen),
        "cf50_frozen_final5_article_ids": sorted(frozen),
        "eligible_manifests": [row for row in manifest_rows if row["eligible"]],
        "ignored_manifests": [row for row in manifest_rows if not row["eligible"]],
        "candidate_revision_ids": [row["revision_id"] for row in candidates],
        "candidate_records": candidates,
        "cms_write_attempted": False,
        "draft_write_attempted": False,
        "publish_at_created": False,
        "publisher_invoked": False,
    }
    encoded = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output == "-":
        sys.stdout.write(encoded)
    else:
        Path(args.output).write_text(encoded, encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write("[inventory-diff] ERROR: %s\n" % exc)
        raise SystemExit(2)
