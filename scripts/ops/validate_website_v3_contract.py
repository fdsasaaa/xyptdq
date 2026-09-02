#!/usr/bin/env python3
"""Machine invariant validator: website V3 contract + Issue-264 scope (regression for #474).
Exit 0 on PASS, exit 1 listing every violated invariant.
Invoke: python3 scripts/ops/validate_website_v3_contract.py [repo_root]
"""
import json
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
PUB = ROOT / "config" / "content_publication_policy.json"
INV = ROOT / "config" / "content_inventory_policy.json"


def load(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover
        print(f"INVARIANT FAIL: cannot load {path}: {exc}")
        sys.exit(1)


def main() -> int:
    pub = load(PUB)
    inv = load(INV)
    o = pub.get("ordinary_seo_promotion", {})
    up = inv.get("upstream_contract", {})
    failures: list[str] = []

    # --- V3 website upstream contract ---
    if up.get("production_system_status") != "v3_consolidated":
        failures.append(f"upstream production_system_status must be v3_consolidated, got {up.get('production_system_status')!r}")
    if up.get("daily_minimum_formal_batch_count") == 10:
        failures.append("formal minimum must NOT be 10 (regression: #474)")
    if up.get("daily_minimum_formal_batch_count") != 1:
        failures.append(f"formal minimum must be 1, got {up.get('daily_minimum_formal_batch_count')!r}")
    if up.get("daily_operational_minimum_count") != 10:
        failures.append(f"operational minimum must be 10, got {up.get('daily_operational_minimum_count')!r}")
    if up.get("daily_quality_first_range") != [1, 25]:
        failures.append(f"quality_first_range must be [1, 25], got {up.get('daily_quality_first_range')!r}")
    if up.get("below_minimum_1_to_19_means_official_new_inventory_when_manifest_complete") is not True:
        failures.append("below_minimum_1_to_19_means_official_new_inventory_when_manifest_complete must be true")

    # --- Issue-264 scope: ordinary DAILY-* publication is independent ---
    if o.get("enabled") is not True:
        failures.append("ordinary_seo_promotion.enabled must be true")
    ov = o.get("batch_eligibility_overrides", {})
    if ov.get("DAILY-20260901") != "eligible":
        failures.append(f"DAILY-20260901 must be 'eligible', got {ov.get('DAILY-20260901')!r}")
    if ov.get("DAILY-20260817") != "pending_title_seo_review":
        failures.append(f"DAILY-20260817 must be 'pending_title_seo_review', got {ov.get('DAILY-20260817')!r}")
    if str(o.get("status", "")).startswith("HOLD_UNTIL_ISSUE_264"):
        failures.append("ordinary_seo_promotion must not inherit HOLD_UNTIL_ISSUE_264")

    # --- CF50 Final Five stays frozen; Issue #264 stays open ---
    cf = inv.get("cf50_terminal_baseline", {})
    if cf.get("release_authorized") is not False:
        failures.append("cf50_terminal_baseline.release_authorized must remain false")
    frozen = set(cf.get("final5_frozen_pending_issue_264", []))
    required = {
        "LCM-CREATOR-cf50-20260813-020",
        "LCM-CREATOR-cf50-20260813-029",
        "LCM-CREATOR-cf50-20260813-038",
        "LCM-CREATOR-cf50-20260813-039",
        "LCM-CREATOR-cf50-20260813-040",
    }
    if not required <= frozen:
        failures.append(f"Final Five must stay frozen, missing {sorted(required - frozen)}")

    if failures:
        print("WEBSITE_V3_CONTRACT=FAIL")
        for f in failures:
            print("  -", f)
        return 1
    print("WEBSITE_V3_CONTRACT=PASS (V3 upstream + Issue-264 scope invariants hold)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
