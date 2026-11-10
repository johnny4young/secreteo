"""Exercise the real matrix producer with explicit speech doubles and bounded subprocesses."""

from array import array
import copy
import functools
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
import wave

ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(ROOT / "scripts"))
import dictation_audio as audio  # noqa: E402
import dictation_corpus as corpus  # noqa: E402
import materialize_dictation_corpus as producer  # noqa: E402

NAMES = {"tuning": {"en": "tune-en", "es": "tune-es"}, "holdout": {"en": "held-en", "es": "held-es"}}


class SpeechDouble:
    def __init__(self, *, fail_at=None, malformed=False):
        self.calls = []
        self.fail_at = fail_at
        self.malformed = malformed

    def identity(self, name, language):
        corpus.require(type(name) is str and name in {value for group in NAMES.values() for value in group.values()},
                       "unavailable test voice")
        return {"name": name, "language": language, "source": "explicit-test-double"}

    def metadata(self):
        return {"kind": "explicit-test-double"}

    def synthesize(self, text, voice, rate, destination, timeout):
        self.calls.append((text, voice, rate, timeout))
        if self.fail_at == len(self.calls):
            raise corpus.CorpusError("injected synthesis failure")
        if self.malformed:
            destination.write_bytes(b"not PCM")
            return
        values = hashlib.sha256(json.dumps([text, voice, rate]).encode()).digest()
        samples = array("h", ((value - 128) * 128 for value in values)) * 5
        write_pcm(destination, samples)


def write_pcm(path, samples):
    block = array("h", samples)
    if sys.byteorder != "little":
        block.byteswap()
    with path.open("xb") as stream, wave.open(stream, "wb") as target:
        target.setparams((1, 2, 16_000, len(block), "NONE", "not compressed"))
        target.writeframes(block.tobytes())


@functools.cache
def _synthetic_audio_template():
    temporary = tempfile.TemporaryDirectory()
    try:
        producer.materialize(Path(temporary.name) / "audio", NAMES, SpeechDouble())
    except BaseException:
        temporary.cleanup()
        raise
    return temporary


def copy_synthetic_audio(destination):
    """Reuse generation, never mutable files: each test owns a full independent copy."""
    source = Path(_synthetic_audio_template().name) / "audio"
    shutil.copytree(source, destination)


class SyntheticAudioFixtureTests(unittest.TestCase):
    def setUp(self):
        _synthetic_audio_template.cache_clear()
        self.addCleanup(_synthetic_audio_template.cache_clear)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    @staticmethod
    def inventory(root):
        return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in root.rglob("*") if path.is_file()}

    def test_copies_materialize_once_and_keep_the_full_admitted_corpus(self):
        with mock.patch.object(producer, "materialize", wraps=producer.materialize) as render:
            for name in ("first", "second"):
                destination = self.root / name
                copy_synthetic_audio(destination)
                manifest, _ = corpus.read_json(destination / "manifest.json")
                _, cells = corpus.read_public_corpus()
                corpus.validate_audio_manifest(manifest, cells, destination)
                self.assertEqual(len(manifest["entries"]), 480)
                self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o700)
                for path in destination.iterdir():
                    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(render.call_count, 1)
        self.assertEqual(self.inventory(self.root / "first"), self.inventory(self.root / "second"))

    def test_mutation_and_deletion_cannot_reach_another_copy_or_the_template(self):
        first, second, third = (self.root / name for name in ("first", "second", "third"))
        copy_synthetic_audio(first)
        copy_synthetic_audio(second)
        expected = self.inventory(second)
        wav = next(first.glob("*.wav"))
        self.assertNotEqual(wav.stat().st_ino, (second / wav.name).stat().st_ino)
        wav.write_bytes(b"changed synthetic bytes")
        (first / "manifest.json").write_bytes(b"changed manifest")
        (first / "recipe.json").unlink()
        self.assertEqual(self.inventory(second), expected)
        copy_synthetic_audio(third)
        self.assertEqual(self.inventory(third), expected)

    def test_an_existing_destination_is_not_overwritten(self):
        destination = self.root / "keep"
        destination.mkdir()
        sentinel = destination / "sentinel"
        sentinel.write_bytes(b"keep")
        with self.assertRaises(FileExistsError):
            copy_synthetic_audio(destination)
        self.assertEqual(list(destination.iterdir()), [sentinel])
        self.assertEqual(sentinel.read_bytes(), b"keep")

    def test_failed_generation_cleans_up_and_can_retry(self):
        attempted = []

        def fail(destination, *_):
            attempted.append(destination.parent)
            destination.mkdir()
            (destination / "partial").write_bytes(b"incomplete")
            raise RuntimeError("synthetic generation failed")

        with mock.patch.object(producer, "materialize", side_effect=fail):
            with self.assertRaisesRegex(RuntimeError, "synthetic generation failed"):
                copy_synthetic_audio(self.root / "failed")
        self.assertFalse(attempted[0].exists())
        self.assertFalse((self.root / "failed").exists())
        copy_synthetic_audio(self.root / "retry")
        manifest, _ = corpus.read_json(self.root / "retry/manifest.json")
        self.assertEqual(len(manifest["entries"]), 480)


class DictationMaterializationTests(unittest.TestCase):
    def test_complete_matrix_caches_only_identical_speech_and_publishes_admitted_manifest_last(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "audio"
            speech = SpeechDouble()
            report = producer.materialize(output, NAMES, speech)
            self.assertEqual(report["audioCellCount"], 480)
            self.assertEqual(report["synthesisCount"], 198)
            self.assertEqual(report["cacheHitCount"], 330)
            self.assertEqual(len(speech.calls), 198)
            self.assertEqual(report["producerKind"], "explicit-test-double")
            self.assertFalse(report["qualityMeasured"])
            self.assertFalse(report["verifiedDeliveryMeasured"])
            self.assertFalse((output / "incomplete.json").exists())
            self.assertFalse(list(output.glob(".speech-*")))
            manifest, _ = corpus.read_json(output / "manifest.json")
            recipe, _ = corpus.read_json(output / "recipe.json")
            _, cells = corpus.read_public_corpus()
            corpus.validate_audio_manifest(manifest, cells, output)
            self.assertEqual(manifest["recipeSHA256"], producer.fingerprint(recipe))
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
            for path in output.iterdir():
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600, path.name)
            self.assertTrue(all(0 < call[3] <= producer.PROCESS_SECONDS for call in speech.calls))

    def test_failure_keeps_partial_cells_but_never_a_success_manifest_or_cached_text(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "audio"
            with self.assertRaisesRegex(corpus.CorpusError, "injected synthesis failure"):
                producer.materialize(output, NAMES, SpeechDouble(fail_at=2))
            receipt, _ = corpus.read_json(output / "incomplete.json")
            self.assertEqual(receipt["completedCells"], 6)
            self.assertFalse((output / "manifest.json").exists())
            self.assertFalse((output / "materialization.json").exists())
            self.assertFalse(list(output.glob(".speech-*")))
            self.assertFalse(list(output.rglob("*.txt")))

    def test_malformed_synthesis_never_becomes_an_admitted_clip(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "audio"
            with self.assertRaises(corpus.CorpusError):
                producer.materialize(output, NAMES, SpeechDouble(malformed=True))
            receipt, _ = corpus.read_json(output / "incomplete.json")
            self.assertEqual(receipt["completedCells"], 0)
            self.assertFalse((output / "manifest.json").exists())

    def test_existing_output_and_receipt_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            sentinel = output / "keep.json"
            sentinel.write_text("keep this")
            speech = SpeechDouble()
            with self.assertRaises(FileExistsError):
                producer.materialize(output, NAMES, speech)
            self.assertFalse(speech.calls)
            with self.assertRaises(FileExistsError):
                producer.publish_json(sentinel, {"replacement": True})
            self.assertEqual(sentinel.read_text(), "keep this")
            self.assertEqual(list(output.iterdir()), [sentinel])

    def test_deadline_prevents_any_synthesis_and_marks_only_owned_output_incomplete(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "audio"
            clock = iter([0, producer.RUN_SECONDS + 1])
            speech = SpeechDouble()
            with self.assertRaisesRegex(corpus.CorpusError, "deadline"):
                producer.materialize(output, NAMES, speech, clock=lambda: next(clock))
            self.assertFalse(speech.calls)
            self.assertFalse((output / "manifest.json").exists())
            self.assertTrue((output / "incomplete.json").exists())

    def test_voice_identity_overlap_is_rejected_before_creating_output(self):
        names = copy.deepcopy(NAMES)
        names["holdout"]["en"] = names["tuning"]["en"]
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "audio"
            with self.assertRaisesRegex(corpus.CorpusError, "voice leaks"):
                producer.materialize(output, names, SpeechDouble())
            self.assertFalse(output.exists())

    def test_noop_gain_preserves_every_sample_including_integer_extremes(self):
        document, _ = corpus.read_public_corpus()
        family = document["families"][0]
        profile = next(value for value in document["profiles"] if value["id"] == "short-tail")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.wav"
            expected = array("h", [-32_768, -1, 0, 1, 32_767])
            write_pcm(source, expected)
            output = root / "output.wav"
            _, clipped = audio.render_cell("synthetic-case", family, profile, [source], output)
            self.assertEqual(audio.read_samples(output), expected)
            self.assertEqual(clipped, 0)
            self.assertEqual(audio.read_samples(source), expected, "rendering must not mutate its source")

    def test_profile_noise_is_repeatable_and_changes_with_the_case_identity(self):
        document, _ = corpus.read_public_corpus()
        family = next(value for value in document["families"] if value["audioKind"] == "silence")
        profile = next(value for value in document["profiles"] if value["id"] == "noise-floor")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            results = [audio.render_cell(case, family, profile, [], root / f'{index}.wav')[0]
                       for index, case in enumerate(["case-a", "case-a", "case-b"])]
            self.assertEqual(results[0]["audioSHA256"], results[1]["audioSHA256"])
            self.assertNotEqual(results[0]["audioSHA256"], results[2]["audioSHA256"])
            self.assertEqual(results[0]["frames"], 29_600)

    def test_padding_is_additional_and_does_not_infer_or_crop_speech_end(self):
        document, _ = corpus.read_public_corpus()
        family = document["families"][0]
        profile = document["profiles"][0]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.wav"
            expected = array("h", [0, 120, -140, 0, 0])
            write_pcm(source, expected)
            output = root / "output.wav"
            info, _ = audio.render_cell("case-a", family, profile, [source], output)
            rendered = audio.read_samples(output)
            self.assertEqual(info["frames"], len(expected) + 4_000)
            self.assertEqual(rendered[:len(expected)], expected)
            self.assertTrue(all(sample == 0 for sample in rendered[len(expected):]))

    def test_real_subprocess_timeout_is_typed_and_never_echoes_child_content(self):
        speech = producer.SystemSpeech.__new__(producer.SystemSpeech)
        speech.command_runner = subprocess.run
        start = time.monotonic()
        with self.assertRaisesRegex(corpus.CorpusError, "timed out") as failure:
            speech.run([sys.executable, "-c", "import time; print('PRIVATE-SENTINEL'); time.sleep(15)"], timeout=0.05)
        self.assertLess(time.monotonic() - start, 3)
        self.assertNotIn("PRIVATE-SENTINEL", str(failure.exception))

    def test_system_adapter_uses_a_private_input_file_without_shell_interpolation(self):
        speech = producer.SystemSpeech.__new__(producer.SystemSpeech)
        calls = []
        text = '$(touch unwanted) [[slnc 1000]] PRIVATE-SENTINEL'

        def run(arguments, **options):
            calls.append(arguments)
            source = Path(arguments[arguments.index("-f") + 1])
            output = Path(arguments[arguments.index("-o") + 1])
            self.assertEqual(source.read_text(), text)
            self.assertEqual(stat.S_IMODE(source.stat().st_mode), 0o600)
            self.assertNotIn(text, arguments)
            self.assertEqual(options["timeout"], 5)
            self.assertEqual(options["stderr"], subprocess.DEVNULL)
            write_pcm(output, [17, 20])
            return subprocess.CompletedProcess(arguments, 0, stdout=b"")

        speech.command_runner = run
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "clip.wav"
            speech.synthesize(text, "Mónica", 175, path, timeout=5)
            self.assertFalse(path.with_suffix(".txt").exists())
            self.assertEqual(calls[0][0], "/usr/bin/say")
            self.assertIn("--data-format=LEI16@16000", calls[0])


if __name__ == "__main__":
    unittest.main()
