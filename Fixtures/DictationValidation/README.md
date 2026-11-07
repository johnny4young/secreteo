# Public dictation corpus

`public-synthetic-v1.json` contains original Portavoz test text under the root
MIT license. No private meeting, external dataset, downloaded voice, model or
audio recording is included. `textLicense` applies to the text, not to audio
that a separately authorized synthesizer might produce.

## Inventory and ground truth

The matrix is 60 phrase families × 8 explicitly declared acoustic/rate profiles:
160 English cells, 160 Spanish cells, 80 synthetic language-switching cells and
80 adversarial cells. Paired translations and related adversarial phrases share
one of 37 phrase groups. Variants are **not independent speakers or independent
phrases**. Report family, phrase-group, profile and cell counts separately.

Spoken segments declare their language; `acceptedTexts` records literal targets
and any reviewed alternatives. It is not an invitation to add the current model's
mistake as an acceptable answer. Numbers, negation, names, code, URLs, email,
typographic apostrophes, accented text, repetition, minimal utterances and quoted
hostile instructions are represented. Non-speech families have empty references.
`critical` flags exact-text review cases; a formatting mismatch is not, by itself,
a demonstrated factual error. ASR word/character error scoring and final output
fidelity must remain separate.

Eight profiles declare gain, optional noise floor, speaking rate, tail length
and background duration. These are recipes, not measurements of already rendered
clips. Language-switching segments are intended for explicitly attributed local
voices; this is not a natural bilingual speaker sample. Synthetic noise, tones
and impulses do not stand in for real coughs, music, accents or Bluetooth capture.

Families and related phrase groups cannot cross the tuning/holdout split.
Case/whitespace/NFC-equivalent references cannot disguise exact split leakage.
A rendered manifest must also assign disjoint voice identities to the two splits,
including cross-language reuse. This checks declared identities, not independent
human-speaker generalization; semantic paraphrase leakage still needs review.

## Validate the reviewed source

```sh
python3 -I scripts/dictation_corpus.py verify-public
python3 -I -m unittest discover -s Tests/Tooling -p 'test_dictation_corpus.py'
```

The public generation is SHA-256 pinned in the validator. A structurally valid
but edited/relabelled source does not become reviewed public data. Schema changes,
new references or acoustic recipes require an explicit generation/hash review;
do not update the pin just to match an unexplained mutation.

The inventory output contains counts and the public digest, not text. It says
`audioChecked: false`, `qualityMeasured: false` and
`verifiedDeliveryMeasured: false`. A zero exit validates the corpus contract;
it is **not** a quality score or an accepted performance baseline.

## Admit local audio bytes

```sh
python3 -I scripts/dictation_corpus.py validate-audio \
  --manifest /absolute/scratch/audio-manifest.json \
  --audio-root /absolute/scratch/audio
```

The manifest has exactly these fields:

- `schemaVersion: 1`, `kind: "dictation-audio-manifest"`.
- `corpusSHA256`: the reviewed source digest; `recipeSHA256`: the exact producer
  recipe digest. The latter is recorded identity, not a producer attestation.
- `voices`: `tuning` and `holdout`, each with `en` and `es` SHA-256 voice identity
  digests. Names, filesystem paths and raw voice metadata are not in the receipt.
- `entries`: exactly one entry for every `<family-id>.<profile-id>` cell.
  Each entry has `caseID`, `audioSHA256`, `frames`, `sampleRate: 16000`,
  `channels: 1`, `sampleWidth: 2` and the sorted unique `voiceSHA256` list for its
  declared spoken segments (empty for non-speech).

Files are always `<caseID>.wav` directly under the explicitly selected root;
the manifest cannot provide paths. Admission rejects missing/duplicate cases,
unknown fields, cross-split voices, mismatched attribution, cross-family audio
reuse, symlinks, nonregular files, truncated PCM, wrong formats/hashes and files
that change during inspection. JSON is bounded to 2 MB; each mono PCM16 file to
120 seconds and 4,000,128 bytes. Files are hashed in bounded chunks. Success
checks bytes/format/declared attribution; it does **not** prove that a synthesizer
actually used the declared voice, rate or gain, or that the speech matches the
reference. The generation/consumption owner must provide that separate evidence.

The filesystem tests use tiny artificial PCM buffers and identify their scope as
parser/digest validation. Even a fully admitted matrix retains
`qualityMeasured: false` and `verifiedDeliveryMeasured: false`. No ASR hypothesis,
transcript, local path or raw error becomes inventory output.


## Render locally with installed macOS voices

`materialize_dictation_corpus.py` is an explicit developer operation, not an app
startup task. Supply a local JSON selection with `tuning` and `holdout`, each
mapping `en` and `es` to an already available voice name. The two partitions
must not share a selected voice identity. For example, when installed:

```json
{
  "tuning": {"en": "Samantha", "es": "Mónica"},
  "holdout": {"en": "Daniel", "es": "Paulina"}
}
```

```sh
python3 -I scripts/materialize_dictation_corpus.py \
  --voices /absolute/scratch/voices.json \
  --output /absolute/scratch/new-dictation-audio
```

The output directory must not exist. The producer uses only the reviewed public
text, enumerates available macOS voices, invokes `/usr/bin/say` with an explicit
input file and PCM16 output, and never plays audio or invokes a voice/model
installer. It is not a general-purpose arbitrary-text synthesis service. Each
subprocess has a 45-second deadline; the matrix checks a one-hour deadline at
work boundaries. A blocked filesystem call is not a hard real-time guarantee.

Identical voice/text/rate synthesis is cached only inside an owned temporary
directory. Every cell still applies its declared profile: fixed gain, seeded
uniform noise, bounded PCM clipping (counted), and **additional** silence. The
producer does not crop existing silence, infer speech-end timestamps or modify
recordings. No-op gain/noise preserves source samples exactly. Background
waveforms are synthetic silence, uniform noise, a 440 Hz tone or impulses,
not recordings of environmental sound.

`recipe.json` binds the reviewed source, producer script digests, Python version,
macOS build, system speech executable digest and selected voice names/locales.
A voice identity digest describes that selection and OS build, not a checksum
of every installed voice asset. Exact rendered WAV hashes remain authoritative
for a comparison; regenerating on another host is not assumed bit-identical.
`materialization.json` reports actual file counts, cache use, clipping and elapsed
rendering time without the source text. `manifest.json` is published last, only
after all 480 files pass admission. The directory is private and output files
are owner-only; JSON publication never replaces an existing file. Failure keeps
explicitly incomplete output, not a successful manifest; cached text and source
speech files are removed. Do not resume by overwriting that directory.

The producer's filesystem/transaction tests use an explicitly identified speech
double. Actual macOS synthesis is a separate lane. Neither a speech-double run
nor real synthesis measures ASR quality, product memory usage or verified text
insertion. Model and end-to-end baselines need their own receipts and deadlines.

## Model and controller lanes

The installed-model, controller and controller-matrix launchers, and the Parakeet
v3 against Ultra comparison, are not here yet
([G16](../../docs/GAPS.md#g16-model-and-controller-lanes)). The corpus, its
admission, local rendering, field recordings and the speech-gate lane below do
not depend on them.

## Observe the speech gate over every cell

`DictationSpeechGateCorpusTests` runs the production speech-gate rule
(`DictationSpeechGate.heardSpeech`, Silero on CPU) over all 480 admitted cells.
The model comes only from an explicit scratch store; `SECRETEO_SPEECH_GATE_INSTALL=1`
lets it download the pinned bundle there, never into the app's store:

```sh
SECRETEO_SPEECH_GATE_AUDIO=/absolute/scratch/new-dictation-audio \
SECRETEO_SPEECH_GATE_MODELS=/absolute/scratch/models \
SECRETEO_SPEECH_GATE_INSTALL=1 \
SECRETEO_SPEECH_GATE_OUTPUT=/absolute/scratch/speech-gate.json \
swift test -c release --filter DictationSpeechGateCorpusTests
```

Without `SECRETEO_SPEECH_GATE_AUDIO` the test skips, so the ordinary test run
never loads a model.

Each cell records whether the gate heard speech, the first speech frame, the peak
probability, process CPU time and the slowest chunk. Chunks are fed unpaced, so
the receipt measures the decision and its cost, not live timing.

## Record the speech families with a real microphone

The synthetic voices cannot show how a model handles a person and a microphone.
A field recording is one person reading each of the 56 speech families once,
as they would dictate it. Recordings and the manifest stay in a private local
directory; never commit them:

```sh
xcrun swift scripts/record-dictation-field-corpus.swift --output /absolute/scratch/field-audio
python3 -I scripts/dictation_field_corpus.py build --audio-root /absolute/scratch/field-audio \
  --microphone built-in
```

The recorder asks for microphone access for the terminal, shows one sentence at a
time and saves `<family>.field.wav` as 16 kHz mono PCM16. Rerunning it skips
families already recorded; `--redo <family>` records one again. `build` names any
family still missing instead of publishing a partial manifest. The resulting
`dictation-field-audio-manifest` has no synthesis recipe and declares the
microphone as `built-in` or `external`.
