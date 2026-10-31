#!/usr/bin/env python3
"""Behavioral regressions for publication recovery and unattended promotion."""
import copy
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import reconcile_publication_ledger as ledger

REPO = Path(__file__).resolve().parents[2]


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.queue = self.root / "scheduled"
        self.receipts = self.root / "receipts"
        self.queue.mkdir(); self.receipts.mkdir()
        self.q = {"schema_version": 1, "article_key": "lcm-test-article", "publication_state": "scheduled",
                  "source_article_id": "LCM-TEST-ARTICLE", "source_revision_id": "LCM-TEST-ARTICLE:public-r1",
                  "source_batch_id": "DAILY-20260901", "source_fingerprint": "a" * 64,
                  "content": "历史规则核对。" * 50, "title": "用于验证完整发布流程的文章标题", "catid": 3,
                  "publish_at": "2026-09-03T10:00:00+08:00", "promoted_at": "2026-09-02T10:00:00+08:00"}
        self.q["source_content_hash"] = hashlib.sha256(self.q["content"].encode()).hexdigest()
        self.row = {"article_id": self.q["source_article_id"], "revision_id": self.q["source_revision_id"],
                    "source_batch_id": self.q["source_batch_id"], "fingerprint": self.q["source_fingerprint"],
                    "content_hash": self.q["source_content_hash"], "lifecycle_state": "draft",
                    "cms_id": None, "scheduled_at": None, "published_at": None, "untouched_metadata": "preserved"}
        self.input = {"schema_version": 1, "records": {self.row["revision_id"]: self.row}}
        self.entry = {"status": "published", "cms_id": 104, "published_at": "2026-09-03T02:07:03+00:00",
                      "content_hash": ledger.publisher_hash(self.q)}
        self.state = {"articles": {self.q["article_key"]: self.entry}}
        self.file = self.queue / "lcm-test-article.json"
        self.write(self.file, self.q)
        self.rec = {"schema_version": 1, "receipt_type": "publication_receipt", "article_id": self.row["article_id"],
                    "article_key": self.q["article_key"], "fingerprint": self.row["fingerprint"],
                    "content_hash": self.row["content_hash"], "cms_id": 104,
                    "published_url": "https://www.laocaimi.org/index.php?c=show&id=104",
                    "published_at": self.entry["published_at"], "publisher_article_hash": self.entry["content_hash"],
                    "source_file": self.file.name}
        fields = ["article_id", "article_key", "fingerprint", "content_hash", "cms_id", "published_url",
                  "published_at", "publisher_article_hash", "source_file"]
        self.rec["receipt_id"] = hashlib.sha256("|".join(["v1"] + [str(self.rec[k]) for k in fields]).encode()).hexdigest()
        self.write(self.receipts / "lcm-test-article.104.json", self.rec)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, data):
        path.write_text(json.dumps(data, ensure_ascii=False))

    def run_plan(self, state=None, source=None):
        return ledger.plan(self.queue, self.state if state is None else state,
                           self.input if source is None else source, self.receipts)

    def test_backfills_published_canary_without_mutating_source(self):
        before = self.file.read_bytes()
        result, changed = self.run_plan()
        r = result["records"][self.row["revision_id"]]
        self.assertEqual((r["lifecycle_state"], r["cms_id"]), ("published", 104))
        self.assertEqual(r["published_at"], self.rec["published_at"])
        self.assertEqual(r["untouched_metadata"], "preserved")
        self.assertEqual(changed, [self.row["revision_id"]])
        self.assertEqual(self.file.read_bytes(), before)
        self.assertEqual(self.input["records"][self.row["revision_id"]]["lifecycle_state"], "draft")
        self.assertEqual(self.run_plan(source=result)[1], [])

    def test_recovers_scheduled_transition_before_first_publisher_poll(self):
        result, changed = self.run_plan(state={"articles": {}})
        self.assertEqual(result["records"][self.row["revision_id"]]["lifecycle_state"], "scheduled")
        self.assertIsNone(result["records"][self.row["revision_id"]]["cms_id"])

    def test_wrong_receipt_or_cross_article_proof_is_rejected(self):
        for field, value in (("article_id", "OTHER"), ("cms_id", 999), ("receipt_id", "f"*64),
                             ("content_hash", "f"*64), ("published_at", "2026-09-04T00:00:00+00:00")):
            with self.subTest(field=field):
                bad = dict(self.rec); bad[field] = value
                self.write(self.receipts / "lcm-test-article.104.json", bad)
                with self.assertRaises(ValueError): self.run_plan()

    def test_published_lifecycle_cannot_downgrade(self):
        self.row["lifecycle_state"] = "published"
        with self.assertRaisesRegex(ValueError, "downgrade"):
            self.run_plan(state={"articles": {}})

    def test_other_cms_id_cannot_be_overwritten(self):
        self.row["cms_id"] = 999
        with self.assertRaisesRegex(ValueError, "another CMS"):
            self.run_plan()

    def test_cf50_cannot_enter_ordinary_reconciliation(self):
        self.q["source_batch_id"] = "CF50-20260813"
        self.write(self.file, self.q)
        with self.assertRaisesRegex(ValueError, "non-DAILY/CF50"):
            self.run_plan()

    def test_atomic_commit_is_idempotent_and_conflict_does_not_write(self):
        sp, lp = self.root/"state.json", self.root/"ledger.json"
        self.write(sp, self.state); self.write(lp, self.input)
        args = (self.queue, sp, lp, self.receipts, self.root/"intake.lock")
        self.assertEqual(ledger.reconcile(*args, commit=False)["changed_count"], 1)
        self.assertEqual(ledger.read_json(lp), self.input)
        ledger.reconcile(*args, commit=True)
        before = lp.read_bytes()
        self.assertEqual(ledger.reconcile(*args, commit=True)["changed_count"], 0)
        self.assertEqual(lp.read_bytes(), before)
        self.entry["content_hash"] = "f"*64; self.write(sp, self.state)
        with self.assertRaises(ValueError): ledger.reconcile(*args, commit=True)
        self.assertEqual(lp.read_bytes(), before)

    @unittest.skipUnless(shutil.which("php"), "PHP compatibility exercised in repository CI")
    def test_python_hash_and_receipt_validation_match_real_php_export(self):
        sp, rp = self.root/"state.json", self.root/"real-receipt.json"
        self.write(sp, self.state)
        subprocess.run(["php", str(REPO/"scripts/content/export_publication_receipt.php"),
                        "--article="+str(self.file), "--state="+str(sp), "--output="+str(rp)], check=True, capture_output=True)
        self.assertEqual(ledger.read_json(rp)["receipt_id"], self.rec["receipt_id"])

    @unittest.skipUnless(shutil.which("php"), "PHP cron integration exercised in repository CI")
    def test_cron_without_bridge_environment_schedules_once_and_records_lifecycle(self):
        repo, content, pub = self.root/"repo", self.root/"content", self.root/"publisher"
        (repo/".git").mkdir(parents=True)
        for rel in ("scripts/content/promote_draft.php", "scripts/content/reconcile_publication_ledger.py",
                    "config/content_publication_policy.json", "config/content_inventory_policy.json"):
            target=repo/rel; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy(REPO/rel,target)
        drafts=content/"intake/drafts"; drafts.mkdir(parents=True)
        d=dict(self.q); d["publication_state"]="draft"; d.pop("publish_at"); d.pop("promoted_at")
        self.write(drafts/"fixture.draft.json",d)
        self.write(content/"intake/state.json",self.input)
        bin_dir=self.root/"bin"; bin_dir.mkdir()
        (bin_dir/"git").write_text("#!/bin/sh\nexit 0\n"); (bin_dir/"git").chmod(0o700)
        env=dict(os.environ); env.pop("XYPTDQ_AGENT_RESULT_FILE",None)
        env.update({"XYPTDQ_REPO_DIR":str(repo),"XYPTDQ_CONTENT_ROOT":str(content),
                    "XYPTDQ_PUBLISHER_STATE_ROOT":str(pub),"PATH":str(bin_dir)+":"+env["PATH"]})
        runner=REPO/"scripts/ops/agent_tasks/promote_ordinary_seo_v1.sh"
        def run():
            r=subprocess.run(["bash",str(runner)],env=env,capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        run()
        queue=content/"ordinary-seo/scheduled"
        self.assertEqual(len(list(queue.glob("*.json"))),1)
        self.assertEqual(ledger.read_json(content/"intake/state.json")["records"][self.row["revision_id"]]["lifecycle_state"],"scheduled")
        self.assertEqual(ledger.read_json(content/"ordinary-seo/promotion-last-run.json")["status"],"PASS")
        run()
        self.assertEqual(len(list(queue.glob("*.json"))),1)
        # A due but unfinished queue also fills the horizon, even with another Draft available.
        qfile=next(queue.glob("*.json")); q=ledger.read_json(qfile)
        q["publish_at"]="2020-01-01T10:00:00+08:00"; self.write(qfile,q)
        other=dict(d); other.update({"article_key":"other-article","source_revision_id":"OTHER:public-r1","source_article_id":"OTHER"})
        self.write(drafts/"other.draft.json",other)
        il=ledger.read_json(content/"intake/state.json"); row=copy.deepcopy(self.row)
        row.update({"article_id":"OTHER","revision_id":"OTHER:public-r1"}); il["records"]["OTHER:public-r1"]=row
        self.write(content/"intake/state.json",il)
        run()
        self.assertEqual(len(list(queue.glob("*.json"))),1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
