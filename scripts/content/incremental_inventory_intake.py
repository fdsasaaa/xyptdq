#!/usr/bin/env python3
"""Incremental formal public-r1 -> isolated Draft intake.

The runner is Draft-only. It never creates publish_at, Scheduled entries, CMS
content, Publisher state, or cron. It is idempotent through a durable ledger and
uses a lock so unattended runs cannot overlap.

Modes:
  dry-run  - read-only inventory/conflict plan (default)
  canary   - commit exactly one candidate while automatic intake remains disabled
  auto     - commit up to --limit candidates; requires both inventory and source
             sync policies to explicitly enable automatic intake
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any, Dict, Iterable, List, Tuple


def fail(message: str) -> None:
    raise RuntimeError(message)


def read_json(path: Path) -> Dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"invalid JSON {path}: {exc}") from exc
    if not isinstance(data, dict):
        fail(f"JSON root must be object: {path}")
    return data


def int_field(data: Dict[str, Any], key: str, default: int = -1) -> int:
    """Read an integer field without treating the valid value 0 as missing."""
    value = data.get(key, default)
    if value is None:
        return int(default)
    return int(value)


def atomic_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
    encoded = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".tmp.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp_name, 0o640)
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def normalize_keyword(value: str) -> str:
    return "".join(str(value).lower().split())


def normalize_slug(value: str) -> str:
    return str(value).strip().lower()


def owner_from_row(row: Dict[str, Any], path: Path) -> str:
    return str(
        row.get("article_id")
        or row.get("source_article_id")
        or row.get("article_key")
        or ("file:" + str(path))
    )


def iter_json_files(paths: Iterable[Path]) -> Iterable[Tuple[Path, Dict[str, Any]]]:
    seen: set[str] = set()
    for root in paths:
        if not root.exists():
            continue
        candidates = root.rglob("*.json") if root.is_dir() else [root]
        for path in candidates:
            key = str(path.resolve())
            if key in seen:
                continue
            seen.add(key)
            try:
                yield path, read_json(path)
            except RuntimeError:
                # Managed portfolio inputs are expected to be valid JSON. A bad
                # file is a hard gate, not something to silently skip.
                raise


def build_existing_owners(website: Path, draft_dir: Path, ledger: Dict[str, Any]) -> Tuple[Dict[str, str], Dict[str, str]]:
    keyword_owner: Dict[str, str] = {}
    slug_owner: Dict[str, str] = {}
    roots = [
        website / "content" / "ingress" / "public-release",
        website / "content" / "drafts",
        website / "content" / "scheduled",
        draft_dir,
    ]
    for path, row in iter_json_files(roots):
        owner = owner_from_row(row, path)
        keyword = normalize_keyword(str(row.get("primary_keyword") or ""))
        slug = normalize_slug(str(row.get("slug") or ""))
        if keyword:
            prior = keyword_owner.get(keyword)
            if prior and prior != owner:
                fail(f"existing portfolio primary_keyword conflict: {keyword} -> {prior} / {owner}")
            keyword_owner[keyword] = owner
        if slug:
            prior = slug_owner.get(slug)
            if prior and prior != owner:
                fail(f"existing portfolio slug conflict: {slug} -> {prior} / {owner}")
            slug_owner[slug] = owner

    records = ledger.get("records") or {}
    if not isinstance(records, dict):
        fail("ledger records must be object")
    for revision_id, row in records.items():
        if not isinstance(row, dict):
            fail(f"ledger record is not object: {revision_id}")
        owner = str(row.get("article_id") or revision_id)
        keyword = normalize_keyword(str(row.get("primary_keyword") or ""))
        slug = normalize_slug(str(row.get("slug") or ""))
        if keyword:
            prior = keyword_owner.get(keyword)
            if prior and prior != owner:
                fail(f"ledger primary_keyword conflicts with active portfolio: {keyword} -> {prior} / {owner}")
            keyword_owner[keyword] = owner
        if slug:
            prior = slug_owner.get(slug)
            if prior and prior != owner:
                fail(f"ledger slug conflicts with active portfolio: {slug} -> {prior} / {owner}")
            slug_owner[slug] = owner
    return keyword_owner, slug_owner


def assert_candidate_conflicts(candidates: List[Dict[str, Any]], keyword_owner: Dict[str, str], slug_owner: Dict[str, str]) -> None:
    for row in candidates:
        owner = str(row.get("article_id") or "")
        if not owner:
            fail("candidate article_id missing")
        keyword = normalize_keyword(str(row.get("primary_keyword") or ""))
        slug = normalize_slug(str(row.get("slug") or ""))
        if not keyword or not slug:
            fail(f"candidate SEO identity incomplete: {owner}")
        prior_keyword = keyword_owner.get(keyword)
        if prior_keyword and prior_keyword != owner:
            fail(f"candidate primary_keyword owned by different article: {owner} vs {prior_keyword}")
        prior_slug = slug_owner.get(slug)
        if prior_slug and prior_slug != owner:
            fail(f"candidate slug owned by different article: {owner} vs {prior_slug}")
        keyword_owner[keyword] = owner
        slug_owner[slug] = owner


def run_inventory_diff(website: Path, source: Path, ledger: Path, output: Path) -> Dict[str, Any]:
    cmd = [
        sys.executable,
        str(website / "scripts" / "content" / "inventory_diff.py"),
        f"--source-repo={source}",
        f"--website-repo={website}",
        f"--ledger={ledger}",
        f"--output={output}",
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        fail("inventory_diff failed: " + proc.stderr.strip())
    data = read_json(output)
    if data.get("status") != "PASS":
        fail("inventory_diff did not return PASS")
    return data


def load_ledger(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {
            "schema_version": 1,
            "source_repository": "fdsasaaa/caipiaowenzhang",
            "source_ref": "main",
            "updated_at": None,
            "records": {},
        }
    ledger = read_json(path)
    if ledger.get("schema_version") != 1:
        fail("unsupported ledger schema")
    if ledger.get("source_repository") != "fdsasaaa/caipiaowenzhang" or ledger.get("source_ref") != "main":
        fail("ledger source repository/ref mismatch")
    if not isinstance(ledger.get("records"), dict):
        fail("ledger records must be object")
    return ledger


def manifest_for_batch(source: Path, batch_id: str) -> Path:
    path = source / "articles" / "public_release" / "manifests" / f"{batch_id}.json"
    if not path.is_file():
        fail(f"formal manifest missing for batch {batch_id}")
    return path


def intake_mode(policy: Dict[str, Any], batch_id: str, article_id: str, manifest: Dict[str, Any]) -> str:
    cf50 = policy.get("cf50_terminal_baseline") or {}
    if batch_id == str(cf50.get("source_batch_id") or ""):
        if cf50.get("release_authorized") is not False:
            fail("CF50 terminal exception cannot run after release_authorized changes")
        frozen = set(cf50.get("final5_frozen_pending_issue_264") or [])
        if article_id in frozen:
            fail(f"frozen CF50 article reached intake runner: {article_id}")
        articles = manifest.get("articles") or []
        if not isinstance(articles, list) or len(articles) != int(cf50.get("website_ready_public_r1_count") or 0):
            fail("CF50 terminal manifest is not the explicit 45-public-r1 waiting state")
        if manifest.get("canary_ingestion_allowed") is not True:
            fail("CF50 terminal manifest does not allow guarded intake")
        return "terminal_cf50"
    return "batch"


def validate_existing_draft(draft_path: Path, record: Dict[str, Any]) -> Dict[str, Any]:
    draft = read_json(draft_path)
    checks = {
        "publication_state": draft.get("publication_state") == "draft",
        "no_publish_at": "publish_at" not in draft,
        "article_id": str(draft.get("source_article_id") or "") == str(record.get("article_id") or ""),
        "revision_id": str(draft.get("source_revision_id") or "") == str(record.get("revision_id") or ""),
        "content_hash": str(draft.get("source_content_hash") or "") == str(record.get("content_hash") or ""),
        "fingerprint": str(draft.get("source_fingerprint") or "") == str(record.get("fingerprint") or ""),
        "primary_keyword": str(draft.get("primary_keyword") or "") == str(record.get("primary_keyword") or ""),
        "slug": str(draft.get("slug") or "") == str(record.get("slug") or ""),
    }
    bad = [name for name, ok in checks.items() if not ok]
    if bad:
        fail(f"existing Draft identity mismatch for {record.get('revision_id')}: {','.join(bad)}")
    return draft


def create_draft(website: Path, source: Path, policy_path: Path, editorial_map: Path, record: Dict[str, Any], draft_path: Path) -> Tuple[Dict[str, Any], str]:
    article_id = str(record["article_id"])
    batch_id = str(record["source_batch_id"])
    revision_path = source / str(record["source_path"])
    parent_path = source / "articles" / "approved" / f"{article_id}.json"
    manifest_path = manifest_for_batch(source, batch_id)
    manifest = read_json(manifest_path)
    policy = read_json(policy_path)
    mode = intake_mode(policy, batch_id, article_id, manifest)
    if not revision_path.is_file() or not parent_path.is_file():
        fail(f"source package missing for {article_id}")

    cmd = [
        "php", str(website / "scripts" / "content" / "ingest_public_release_draft.php"),
        f"--revision={revision_path}", f"--parent={parent_path}", f"--manifest={manifest_path}",
        f"--inventory-policy={policy_path}", f"--editorial-cluster-map={editorial_map}",
        f"--output={draft_path}", f"--mode={mode}",
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        fail(f"Draft intake failed for {article_id}: {proc.stderr.strip() or proc.stdout.strip()}")
    return validate_existing_draft(draft_path, record), mode


def ledger_record(record: Dict[str, Any], source_commit: str, draft_path: Path) -> Dict[str, Any]:
    return {
        "article_id": str(record["article_id"]),
        "revision_id": str(record["revision_id"]),
        "content_hash": str(record["content_hash"]),
        "fingerprint": str(record["fingerprint"]),
        "primary_keyword": str(record["primary_keyword"]),
        "slug": str(record["slug"]),
        "site_category_key": str(record["site_category_key"]),
        "source_batch_id": str(record["source_batch_id"]),
        "source_commit": source_commit,
        "lifecycle_state": "draft",
        "cms_id": None,
        "scheduled_at": None,
        "published_at": None,
        "draft_path": str(draft_path),
        "ingested_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-repo", required=True)
    parser.add_argument("--website-repo", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--ledger", default="/var/lib/xyptdq-content/intake/state.json")
    parser.add_argument("--draft-dir", default="/var/lib/xyptdq-content/intake/drafts")
    parser.add_argument("--lock", default="/var/lib/xyptdq-content/intake/intake.lock")
    parser.add_argument("--mode", choices=["dry-run", "canary", "auto"], default="dry-run")
    parser.add_argument("--limit", type=int, default=25)
    args = parser.parse_args()

    if not 1 <= args.limit <= 25:
        fail("limit must be 1..25")
    if args.mode == "canary" and args.limit != 1:
        fail("canary mode requires --limit=1")

    website = Path(args.website_repo).resolve()
    source = Path(args.source_repo).resolve()
    ledger_path = Path(args.ledger)
    draft_dir = Path(args.draft_dir)
    lock_path = Path(args.lock)
    policy_path = website / "config" / "content_inventory_policy.json"
    sync_path = website / "config" / "content_source_sync_policy.json"
    editorial_map = website / "content" / "seo_editorial_cluster_map_cf50.json"
    for required in [policy_path, sync_path, editorial_map, website / "scripts" / "content" / "inventory_diff.py", website / "scripts" / "content" / "ingest_public_release_draft.php"]:
        if not required.is_file():
            fail(f"required website file missing: {required}")
    if not (source / ".git").exists():
        fail("source repository checkout missing")

    policy = read_json(policy_path)
    sync = read_json(sync_path)
    if policy.get("source_repository") != "fdsasaaa/caipiaowenzhang" or policy.get("source_ref") != "main":
        fail("inventory policy source mismatch")
    if sync.get("source_repository") != "fdsasaaa/caipiaowenzhang" or sync.get("source_ref") != "main":
        fail("source sync policy mismatch")
    if args.mode == "canary":
        if (policy.get("activation") or {}).get("automatic_intake_enabled") is not False or sync.get("sync_enabled") is not False:
            fail("canary mode requires automatic intake to remain disabled")
    if args.mode == "auto":
        if (policy.get("activation") or {}).get("automatic_intake_enabled") is not True or sync.get("sync_enabled") is not True:
            fail("auto mode requires both inventory and source-sync policies enabled")

    source_head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    source_origin = subprocess.check_output(["git", "-C", str(source), "rev-parse", "refs/remotes/origin/main"], text=True).strip()
    if source_head != source_origin or len(source_head) != 40:
        fail("source checkout is not synchronized with origin/main")

    lock_path.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
    with open(lock_path, "a+", encoding="utf-8") as lock_handle:
        try:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("another intake process is already running") from exc
        os.chmod(lock_path, 0o640)

        ledger = load_ledger(ledger_path)
        with tempfile.TemporaryDirectory(prefix="xyptdq-inventory-intake-") as tmpdir:
            before = run_inventory_diff(website, source, ledger_path, Path(tmpdir) / "before.json")
            candidates = list(before.get("candidate_records") or [])
            if not all(isinstance(row, dict) for row in candidates):
                fail("inventory candidate_records malformed")

            keyword_owner, slug_owner = build_existing_owners(website, draft_dir, ledger)
            assert_candidate_conflicts(candidates, keyword_owner, slug_owner)
            selected = candidates[: args.limit]

            plan = {
                "status": "PASS",
                "mode": args.mode,
                "source_commit": source_head,
                "A_upstream_official_ready": before.get("A_upstream_official_ready"),
                "known_before": len(set(before.get("candidate_revision_ids") or [])) - len(candidates) if False else (before.get("website_ingress_known", 0) + before.get("ledger_known", 0)),
                "website_ingress_known": before.get("website_ingress_known"),
                "ledger_known_before": before.get("ledger_known"),
                "candidate_count_before": before.get("new_draft_candidates"),
                "selected_revision_ids": [str(row.get("revision_id")) for row in selected],
                "limit": args.limit,
                "writes_planned": args.mode in {"canary", "auto"},
            }
            if args.mode == "dry-run" or not selected:
                print(json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True))
                return 0

            records = ledger["records"]
            created: List[str] = []
            recovered: List[str] = []
            modes: Dict[str, str] = {}
            for row in selected:
                revision_id = str(row["revision_id"])
                article_id = str(row["article_id"])
                safe_name = revision_id.replace(":", "_").replace("/", "_")
                draft_path = draft_dir / f"{safe_name}.draft.json"

                if draft_path.exists():
                    validate_existing_draft(draft_path, row)
                    recovered.append(revision_id)
                    mode = "recovered_existing_draft"
                else:
                    _, mode = create_draft(website, source, policy_path, editorial_map, row, draft_path)
                    created.append(revision_id)
                modes[revision_id] = mode

                if revision_id in records:
                    existing = records[revision_id]
                    if not isinstance(existing, dict) or str(existing.get("content_hash") or "") != str(row["content_hash"]):
                        fail(f"ledger collision for {revision_id}")
                else:
                    records[revision_id] = ledger_record(row, source_head, draft_path)
                    ledger["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
                    atomic_json(ledger_path, ledger)

            after = run_inventory_diff(website, source, ledger_path, Path(tmpdir) / "after.json")
            expected_after = int_field(before, "new_draft_candidates", 0) - len(selected)
            if int_field(after, "new_draft_candidates") != expected_after:
                fail(f"post-intake candidate count mismatch expected={expected_after} actual={after.get('new_draft_candidates')}")
            if int_field(after, "ledger_known") != int_field(before, "ledger_known", 0) + len(selected):
                fail("post-intake ledger_known mismatch")
            after_ids = set(after.get("candidate_revision_ids") or [])
            leaked = [rev for rev in plan["selected_revision_ids"] if rev in after_ids]
            if leaked:
                fail("selected revisions remain candidates after ledger commit: " + ",".join(leaked))

            result = dict(plan)
            result.update({
                "created_revision_ids": created,
                "recovered_revision_ids": recovered,
                "intake_modes": modes,
                "ledger_known_after": after.get("ledger_known"),
                "candidate_count_after": after.get("new_draft_candidates"),
                "idempotent_reconciliation": "PASS",
                "draft_only": True,
                "publish_at_created": False,
                "publisher_invoked": False,
            })
            print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
            return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write("[incremental-intake] ERROR: %s\n" % exc)
        raise SystemExit(2)
