"""Field-recording admission, with generated audio only."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import dictation_corpus as corpus
import dictation_field_corpus as field

DOCUMENT, _ = corpus.read_public_corpus()
SPEECH = sorted(field.field_cells(DOCUMENT))


def write_wav(path, frames=1_600, value=0):
    with wave.open(str(path), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(16_000)
        audio.writeframes(int(value).to_bytes(2, 'little', signed=True) * frames)


class FieldCorpusTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for index, case in enumerate(SPEECH):
            write_wav(self.root / f'{case}.wav', value=index)

    def test_every_speech_family_is_recorded_once_and_non_speech_never(self):
        self.assertEqual(len(SPEECH), 56)
        self.assertFalse(any(case.startswith('non-speech') for case in SPEECH))
        manifest, missing = field.build(self.root, 'built-in', DOCUMENT)
        self.assertEqual(missing, [])
        self.assertEqual(field.validate(manifest, self.root, DOCUMENT),
                         {'fieldCellCount': 56, 'microphone': 'built-in'})

    def test_missing_recordings_are_named_instead_of_admitted(self):
        (self.root / 'en-accent.field.wav').unlink()
        manifest, missing = field.build(self.root, 'external', DOCUMENT)
        self.assertEqual(missing, ['en-accent'])
        with self.assertRaises(corpus.CorpusError):
            field.validate(manifest, self.root, DOCUMENT)

    def test_mutated_audio_and_foreign_provenance_are_rejected(self):
        manifest, _ = field.build(self.root, 'built-in', DOCUMENT)
        for change in ({'microphone': 'studio'}, {'kind': 'dictation-audio-manifest'},
                       {'corpusSHA256': '0' * 64}, {'recipeSHA256': 'a' * 64}):
            with self.subTest(change=change), self.assertRaises(corpus.CorpusError):
                field.validate({**manifest, **change}, self.root, DOCUMENT)
        with self.assertRaises(corpus.CorpusError):
            field.build(self.root, 'studio', DOCUMENT)
        write_wav(self.root / 'en-accent.field.wav', frames=1_601)
        with self.assertRaises(corpus.CorpusError):
            field.validate(manifest, self.root, DOCUMENT)

    def test_cli_publishes_an_owner_only_manifest_and_refuses_gaps(self):
        script = ROOT / 'scripts' / 'dictation_field_corpus.py'
        (self.root / 'es-accent.field.wav').unlink()
        gap = subprocess.run([sys.executable, '-I', str(script), 'build', '--audio-root', str(self.root)],
                             capture_output=True, text=True, check=False)
        self.assertEqual(gap.returncode, 2)
        self.assertEqual(json.loads(gap.stderr), {'missing': ['es-accent']})
        self.assertFalse((self.root / 'manifest.json').exists())
        write_wav(self.root / 'es-accent.field.wav', value=99)
        built = subprocess.run([sys.executable, '-I', str(script), 'build', '--audio-root', str(self.root)],
                               capture_output=True, text=True, check=False)
        self.assertEqual(built.returncode, 0, built.stderr)
        self.assertEqual(os.stat(self.root / 'manifest.json').st_mode & 0o777, 0o600)

    @unittest.skipUnless(shutil.which('xcrun'), 'needs the Swift toolchain')
    def test_recorder_writes_the_admitted_profile_and_format(self):
        recorder = ROOT / 'scripts' / 'record-dictation-field-corpus.swift'
        source = recorder.read_text(encoding='utf-8')
        self.assertIn(f'.{field.PROFILE}.wav', source)
        self.assertIn('AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1', source)
        self.assertIn('AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false', source)
        checked = subprocess.run(['xcrun', 'swiftc', '-typecheck', str(recorder)],
                                 capture_output=True, text=True, check=False)
        self.assertEqual(checked.returncode, 0, checked.stderr)


if __name__ == '__main__':
    unittest.main()
