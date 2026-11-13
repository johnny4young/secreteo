"""Spike 1 harness: plan, measures, scoring and a simulated run. Doubles never measure an app."""

import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(ROOT / "scripts"))

import spike_two_apps as spike


def case(words=8, speech=3.0):
    return {"caseID": "en-test.clean", "expectedWords": words, "seconds": speech + 0.25,
            "speechSeconds": speech, "path": None}


def cell_named(cells, identifier):
    return next(cell for cell in cells if cell["id"] == identifier)


def row(cell, **values):
    base = {"cell": cell, "trial": 0, "timeToFirstText": 0.5, "captionLatency": 0.3, "captionCensored": False,
            "lostFrames": 0, "missingDelivery": False, "doubleDelivery": False, "deliveredAfterCancel": False,
            "crashed": False, "resources": {}}
    return {**base, **values}


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.cells = spike.build_cells()

    def test_every_automated_cell_has_thirty_trials_and_a_matching_control(self):
        automated = [cell for cell in self.cells if not cell["manual"]]
        self.assertEqual(len(automated), 48)
        self.assertEqual(len({cell["id"] for cell in self.cells}), len(self.cells))
        self.assertTrue(all(cell["trials"] >= 30 for cell in automated))
        for cell in self.cells:
            if cell["control"] is None:
                self.assertFalse(cell["companion"])
                continue
            control = cell_named(self.cells, cell["control"])
            for axis in ("dictating", "modelState", "model", "ending"):
                self.assertEqual(cell[axis], control[axis], cell["id"])
            self.assertFalse(control["companion"])
            self.assertEqual(control["background"], "idle")

    def test_fewer_manual_runs_than_the_owner_chose_need_the_dry_run(self):
        with tempfile.TemporaryDirectory() as folder:
            code = spike.main(["run", "--manual-trials", "3", "--output", folder + "/out", "--corpus", folder])
        self.assertEqual(code, 2)

    def test_manual_cells_are_the_owner_run_events_only(self):
        manual = [cell for cell in self.cells if cell["manual"]]
        self.assertEqual(sorted({cell["event"] for cell in manual}), ["bluetooth", "sleep"])
        self.assertTrue(all(cell["trials"] == 5 and cell["companion"] for cell in manual))

    def test_meeting_cells_only_put_secreteo_beside_a_portavoz_meeting(self):
        meetings = [cell for cell in self.cells if cell["background"] == "meeting"]
        self.assertEqual(len(meetings), 16)
        self.assertTrue(all(cell["dictating"] == "secreteo" and cell["microphone"] for cell in meetings))

    def test_schedule_covers_each_trial_once_grouped_by_owner_in_alternating_order(self):
        blocks = spike.schedule(self.cells, block=10)
        seen = [(block["cell"], trial) for block in blocks for trial in block["trials"]]
        expected = [(cell["id"], trial) for cell in self.cells for trial in range(cell["trials"])]
        self.assertEqual(sorted(seen), sorted(expected))
        automated = [block for block in blocks if not cell_named(self.cells, block["cell"])["manual"]]
        owners = [cell_named(self.cells, block["cell"])["dictating"] for block in automated]
        self.assertEqual(owners, sorted(owners, key=spike.APPS.index), "one ownership change in the run")
        group = [block["cell"] for block in automated if block["cell"].startswith("secreteo")]
        width = 32
        self.assertEqual(group[width:2 * width], list(reversed(group[:width])))
        self.assertNotEqual(automated[0]["launchOrder"], automated[1]["launchOrder"])

    def test_the_thresholds_are_the_ones_the_spike_wrote_down(self):
        document = (ROOT / "docs/spikes/two-apps-at-once.md").read_text()
        self.assertIn("at least 30 launches", document)
        self.assertIn("Rises less than 500 ms", document)
        self.assertIn("At most 1.5 times the control, and never above 2.5 s", document)
        self.assertEqual((spike.MINIMUM_TRIALS, spike.CAPTION_RISE_LIMIT), (30, 0.5))
        self.assertEqual((spike.FIRST_TEXT_RATIO_LIMIT, spike.FIRST_TEXT_CEILING), (1.5, 2.5))

    def test_fewer_than_thirty_trials_need_the_dry_run(self):
        with tempfile.TemporaryDirectory() as folder:
            code = spike.main(["run", "--trials", "5", "--output", folder + "/out", "--corpus", folder])
        self.assertEqual(code, 2)


class MeasureTests(unittest.TestCase):
    def setUp(self):
        cells = spike.build_cells()
        self.stop = cell_named(cells, "secreteo-both-warm-parakeet-idle-stop")
        self.cancel = cell_named(cells, "secreteo-both-warm-parakeet-idle-cancel")
        self.portavoz = cell_named(cells, "portavoz-alone-warm-parakeet-idle-stop")

    def observation(self, **values):
        base = {"triggerAt": 100.0, "playbackStartedAt": 100.5, "stopAt": 106.0, "settled": True,
                "panel": [{"t": 100.1, "words": 0, "revision": 0, "panel": True},
                          {"t": 100.9, "words": 2, "revision": 1, "panel": True},
                          {"t": 103.8, "words": 8, "revision": 2, "panel": True}],
                "insertions": [{"t": 106.6, "characters": 40, "words": 8}],
                "timing": [{"startedAt": 100.02, "engine": "parakeet", "audio": {
                    "paddingFrames": 0, "rejectedFrames": 0, "relayDroppedFrames": 0},
                    "session": {"elapsedSeconds": {"firstCaptionHandled": 0.8}, "outcome": "dispatchReported"}}],
                "alive": {"secreteo": True, "portavoz": True}}
        return {**base, **values}

    def test_first_text_and_caption_latency_come_from_the_panel(self):
        measured = spike.measure(self.observation(), self.stop, case())
        self.assertAlmostEqual(measured["timeToFirstText"], 0.9)
        self.assertAlmostEqual(measured["captionLatency"], 0.3)
        self.assertAlmostEqual(measured["appFirstCaption"], 0.82)
        self.assertEqual((measured["deliveries"], measured["deliveredWords"]), (1, 8))
        self.assertEqual(measured["lostFrames"], 0)
        self.assertFalse(measured["doubleDelivery"] or measured["missingDelivery"] or measured["crashed"])

    def test_captions_that_settle_before_speech_ends_count_as_no_lag(self):
        early = self.observation(panel=[{"t": 100.9, "words": 8, "revision": 1, "panel": True}])
        self.assertEqual(spike.measure(early, self.stop, case())["captionLatency"], 0.0)

    def test_a_revision_that_keeps_the_word_count_still_moves_the_last_change(self):
        panel = self.observation()["panel"] + [{"t": 104.4, "words": 8, "revision": 3, "panel": True}]
        self.assertAlmostEqual(spike.measure(self.observation(panel=panel), self.stop, case())["captionLatency"], 0.9)

    def test_trials_that_measured_nothing_become_errors(self):
        quiet = spike.measure(self.observation(panel=[], insertions=[]), self.stop, case())
        self.assertIn("panel never appeared", spike.trial_problem(quiet, self.stop))
        unlogged = spike.measure(self.observation(timing=[]), self.stop, case())
        self.assertIn("timing log", spike.trial_problem(unlogged, self.stop))
        timing = self.observation()["timing"]
        timing[0]["engine"] = "parakeet"
        ultra = spike.build_cells()
        ultra = cell_named(ultra, "secreteo-both-warm-parakeetUltra-idle-stop")
        fallback = spike.measure(self.observation(timing=timing), ultra, case())
        self.assertIn("instead of parakeetUltra", spike.trial_problem(fallback, ultra))
        self.assertIsNone(spike.trial_problem(spike.measure(self.observation(), self.stop, case()), self.stop))

    def test_two_separate_pastes_are_a_double_delivery_and_one_split_paste_is_not(self):
        split = [{"t": 106.60, "characters": 20, "words": 4}, {"t": 106.63, "characters": 20, "words": 4}]
        self.assertFalse(spike.measure(self.observation(insertions=split), self.stop, case())["doubleDelivery"])
        twice = [{"t": 106.6, "characters": 40, "words": 8}, {"t": 107.4, "characters": 40, "words": 8}]
        measured = spike.measure(self.observation(insertions=twice), self.stop, case())
        self.assertTrue(measured["doubleDelivery"])
        self.assertEqual(measured["deliveries"], 2)

    def test_cancel_that_still_types_is_flagged(self):
        observation = self.observation(stopAt=None, cancelAt=101.4)
        measured = spike.measure(observation, self.cancel, case())
        self.assertTrue(measured["deliveredAfterCancel"])
        self.assertIsNone(measured["captionLatency"])

    def test_lost_frames_add_padding_rejects_and_relay_drops(self):
        timing = self.observation()["timing"]
        timing[0]["audio"] = {"paddingFrames": 1_600, "rejectedFrames": 0, "relayDroppedFrames": 320}
        self.assertEqual(spike.measure(self.observation(timing=timing), self.stop, case())["lostFrames"], 1_920)
        timing[0]["audio"]["paddingFrames"] = None
        self.assertIsNone(spike.measure(self.observation(timing=timing), self.stop, case())["lostFrames"])
        stale = [{**timing[0], "startedAt": 80.0}]
        self.assertIsNone(spike.measure(self.observation(timing=stale), self.stop, case())["appOutcome"])

    def test_portavoz_reports_no_frames_and_a_dead_process_is_a_crash(self):
        observation = self.observation(alive={"portavoz": False})
        measured = spike.measure(observation, self.portavoz, case())
        self.assertIsNone(measured["lostFrames"])
        self.assertTrue(measured["crashed"])
        between = self.observation(aliveAtStart={"secreteo": False}, alive={"secreteo": True})
        self.assertTrue(spike.measure(between, self.stop, case())["crashed"], "it died between trials")


class EvaluateTests(unittest.TestCase):
    def setUp(self):
        all_cells = spike.build_cells()
        self.treatment = cell_named(all_cells, "secreteo-both-warm-parakeet-idle-stop")
        self.control = cell_named(all_cells, self.treatment["control"])
        self.cells = [self.control, self.treatment]

    def score(self, control=None, treatment=None, trials=30):
        rows = [row(self.control["id"], **(control or {})) for _ in range(trials)]
        rows += [row(self.treatment["id"], **(treatment or {})) for _ in range(trials)]
        return spike.evaluate(self.cells, rows)

    def failing(self, result):
        return {(item["cell"], item["check"]) for item in result["checks"] if item["result"] == "fail"}

    def test_equal_cells_pass(self):
        self.assertEqual(self.score()["verdict"], "pass")

    def test_caption_rise_must_stay_under_half_a_second(self):
        self.assertEqual(self.score(treatment={"captionLatency": 0.79})["verdict"], "pass")
        result = self.score(treatment={"captionLatency": 0.8})
        self.assertIn((self.treatment["id"], "captionLatencyRise"), self.failing(result))

    def test_first_text_may_reach_one_and_a_half_times_the_control(self):
        self.assertEqual(self.score(control={"timeToFirstText": 1.0}, treatment={"timeToFirstText": 1.5})["verdict"],
                         "pass")
        result = self.score(control={"timeToFirstText": 1.0}, treatment={"timeToFirstText": 1.51})
        self.assertIn((self.treatment["id"], "timeToFirstTextRatio"), self.failing(result))

    def test_first_text_never_above_two_and_a_half_seconds_even_alone(self):
        result = self.score(control={"timeToFirstText": 2.51}, treatment={"timeToFirstText": 2.51})
        self.assertIn((self.control["id"], "timeToFirstTextCeiling"), self.failing(result))

    def test_p95_uses_the_nearest_rank(self):
        rows = [row(self.control["id"], timeToFirstText=0.5) for _ in range(28)]
        rows += [row(self.control["id"], timeToFirstText=3.0) for _ in range(2)]
        self.assertEqual(spike.summarize(rows, self.control)["timeToFirstTextP95"], 3.0)
        self.assertEqual(spike.nearest_rank([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]), 19)
        self.assertIsNone(spike.nearest_rank([]))

    def test_any_lost_frame_double_delivery_or_crash_fails(self):
        for values in ({"lostFrames": 1}, {"doubleDelivery": True}, {"crashed": True}):
            self.assertEqual(self.score(treatment=values)["verdict"], "fail", values)

    def test_too_few_trials_or_unknown_frames_leave_it_incomplete(self):
        self.assertEqual(self.score(trials=29)["verdict"], "incomplete")
        self.assertEqual(self.score(treatment={"lostFrames": None})["verdict"], "incomplete")

    def test_a_crash_fails_even_before_thirty_trials(self):
        self.assertEqual(self.score(treatment={"crashed": True}, trials=3)["verdict"], "fail")

    def test_dictations_that_never_showed_text_count_as_slower_than_any(self):
        rows = [row(self.control["id"]) for _ in range(30)]
        rows += [row(self.treatment["id"]) for _ in range(28)]
        rows += [row(self.treatment["id"], timeToFirstText=None, captionLatency=None) for _ in range(2)]
        result = spike.evaluate(self.cells, rows)
        self.assertEqual(result["cells"][self.treatment["id"]]["timeToFirstTextP95"], "never")
        failing = self.failing(result)
        for name in ("timeToFirstTextCeiling", "timeToFirstTextRatio", "captionLatencyRise"):
            self.assertIn((self.treatment["id"], name), failing)
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        report = Path(folder.name)
        spike.write_report(report, self.cells, rows, {})
        self.assertIn("| never |", (report / "report.md").read_text())

    def test_a_stop_that_typed_nothing_fails_secreteo(self):
        self.assertIn((self.treatment["id"], "delivery"), self.failing(self.score(treatment={"missingDelivery": True})))

    def test_a_crash_report_found_after_the_block_counts(self):
        rows = [row(self.control["id"]) for _ in range(30)] + [row(self.treatment["id"]) for _ in range(30)]
        rows.append({"cell": self.treatment["id"], "trial": None, "lateCrash": True, "crashes": ["Secreteo Dev.ips"]})
        summary = spike.evaluate(self.cells, rows)["cells"][self.treatment["id"]]
        self.assertEqual((summary["trials"], summary["crashes"]), (30, 1))

    def test_manual_cells_need_the_five_runs_the_owner_chose(self):
        cells = spike.build_cells()
        sleep = cell_named(cells, "secreteo-both-warm-parakeetUltra-idle-stop-sleep")
        rows = [row(sleep["id"], captionLatency=None) for _ in range(4)]
        self.assertEqual(spike.evaluate([sleep], rows)["verdict"], "incomplete")
        rows.append(row(sleep["id"], captionLatency=None))
        self.assertEqual(spike.evaluate([sleep], rows)["verdict"], "pass")

    def test_errors_and_warmups_never_count_as_trials(self):
        rows = [row(self.control["id"], warmup=True), row(self.control["id"], error="boom")]
        summary = spike.summarize(rows, self.control)
        self.assertEqual((summary["trials"], summary["errors"]), (0, 1))

    def test_portavoz_lost_audio_is_judged_indirectly(self):
        cells = spike.build_cells()
        control = cell_named(cells, "portavoz-alone-warm-parakeet-idle-stop")
        rows = [row(control["id"], lostFrames=None) for _ in range(30)]
        lost = next(item for item in spike.evaluate([control], rows)["checks"] if item["check"] == "lostAudio")
        self.assertEqual(lost["result"], "pass")
        self.assertTrue(lost["indirect"])
        rows[0]["missingDelivery"] = True
        self.assertEqual(spike.evaluate([control], rows)["verdict"], "fail")


class RunTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.output = Path(self.folder.name) / "bundle"

    def test_a_simulated_run_scores_every_cell_and_resumes_without_repeating(self):
        code = spike.main(["run", "--dry-run", "--output", str(self.output)])
        self.assertEqual(code, 0)
        rows = spike.read_rows(self.output / "rows.jsonl")
        report = json.loads((self.output / "report.json").read_text())
        self.assertTrue(report["dryRun"])
        self.assertEqual(report["verdict"], "pass")
        counted = [item for item in rows if not item["warmup"]]
        self.assertEqual(len(counted), 1_460)
        self.assertTrue((self.output / "report.md").read_text().startswith("# Spike 1 result (dry run, not evidence)"))
        self.assertEqual((self.output / "rows.jsonl").stat().st_mode & 0o777, 0o600)
        self.assertEqual(spike.main(["run", "--dry-run", "--output", str(self.output)]), 0)
        self.assertEqual(len(spike.read_rows(self.output / "rows.jsonl")), len(rows))
        self.assertEqual(spike.main(["report", "--output", str(self.output)]), 0)

    def test_rows_hold_no_words(self):
        spike.main(["run", "--dry-run", "--automated-only", "--output", str(self.output)])
        text = (self.output / "rows.jsonl").read_text()
        for family_text in ("authorize the payment", "Do not"):
            self.assertNotIn(family_text, text)

    def test_skipping_the_manual_cells_leaves_the_result_incomplete(self):
        code = spike.main(["run", "--dry-run", "--automated-only", "--output", str(self.output)])
        self.assertEqual(code, 1)
        self.assertEqual(json.loads((self.output / "report.json").read_text())["verdict"], "incomplete")

    def test_a_folder_with_another_plan_is_refused(self):
        spike.main(["run", "--dry-run", "--automated-only", "--output", str(self.output)])
        self.assertEqual(spike.main(["run", "--dry-run", "--block", "5", "--output", str(self.output)]), 2)

    def test_a_dry_run_folder_never_takes_real_rows(self):
        class OtherBuild(spike.SimulatedDriver):
            def identity(self):
                return {"apps": {"secreteo": {"version": "0.1.0"}}}
        cells = spike.build_cells()
        blocks = spike.schedule(cells)
        self.output.mkdir()
        spike.execute(self.output, cells, blocks, [case()], spike.SimulatedDriver(), dry_run=True, log=lambda _: None)
        with self.assertRaises(spike.SpikeError):
            spike.execute(self.output, cells, blocks, [case()], spike.SimulatedDriver(), dry_run=False, log=lambda _: None)
        with self.assertRaises(spike.SpikeError):
            spike.execute(self.output, cells, blocks, [case()], OtherBuild(), dry_run=True, log=lambda _: None)

    def test_results_stay_outside_the_repository_and_need_an_absolute_path(self):
        with self.assertRaises(spike.SpikeError):
            spike.prepare_output("relative/folder")
        with self.assertRaises(spike.SpikeError):
            spike.prepare_output(str(ROOT / "spike-results"))
        self.assertFalse((ROOT / "spike-results").exists())

    def test_a_trial_that_keeps_failing_stops_the_run(self):
        class Broken(spike.SimulatedDriver):
            def trial(self, cell, case):
                raise NameError("an unexpected bug is recorded, not fatal at once")
        cells = spike.build_cells()
        self.output.mkdir()
        with self.assertRaises(spike.SpikeError):
            spike.execute(self.output, cells, spike.schedule(cells), [case()], Broken(), log=lambda _: None)
        self.assertEqual(len(spike.read_rows(self.output / "rows.jsonl")), 3)

    def test_the_real_driver_reads_identities_from_the_bundles(self):
        app = Path(self.folder.name) / "Fake.app/Contents"
        app.mkdir(parents=True)
        with (app / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "com.example.fake", "CFBundleExecutable": "Fake",
                           "CFBundleShortVersionString": "1.5.1"}, stream)
        identity = spike.RealDriver.identity_of(str(app.parent))
        self.assertEqual((identity["bundleID"], identity["executable"], identity["version"]),
                         ("com.example.fake", "Fake", "1.5.1"))
        with self.assertRaises(spike.SpikeError):
            spike.RealDriver.identity_of(self.folder.name + "/Missing.app")


if __name__ == "__main__":
    unittest.main()
