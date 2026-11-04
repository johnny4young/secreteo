# Spike: FluidAudio upstream against Portavoz's fork

[D13](../DECISIONS.md#d13-fluidaudio-from-upstream-with-no-traits) moves Secreteo from Portavoz's fork to upstream, and a move needs paired evidence.

## Question

Does FluidAudio 0.18.2 with no traits behave like the fork at `16ff2398` for dictation?

## Thresholds, written before measuring

Per model, Parakeet v3 and Ultra:

1. No crash, failure or rejected buffer.
2. Aggregate word error rate at most the fork's plus 0.5 percentage points. Any differing clip is listed.
3. Median processing time, fed as fast as possible: at most 1.10 times the fork's.
4. Median time to first text, fed like a microphone: at most the fork's plus 200 ms.
5. Median peak memory: at most 1.10 times the fork's.
6. Silero gives the same result on every clip, and silence stays silent.

The first round of each build and model is warm-up, not scored.

## Method

`spikes/fluidaudio-pair/run.py` builds the same harness and the same engine sources twice in Release, against each version. It downloads the models once to a scratch store, then alternates the builds. The audio is 26 clips, about 155 seconds, rendered by synthetic macOS voices in English and Spanish, with no microphone. The run was on an M4 Max, and other processes used CPU during at least part of it.

## Result

| Check | v3 | Ultra |
|---|---|---|
| Failures, in 42 runs per model | 0 | 0 |
| Word error rate, fork and upstream | 12.73% and 12.73% | 14.55% and 14.55% |
| Clips with different text | 0 | 0 |
| Full stream of partials, finals and times, later rounds | Identical, 260 of 260 clips | Identical, 260 of 260 clips |
| Speed ratio, first pass of 4 scored rounds | **1.106, over the limit** | 0.942 |
| Speed ratio, 10 more rounds | 0.992 | 1.007 |
| First text, fork and upstream | 1.451 s and 1.432 s | 1.449 s and 1.435 s |
| Peak memory, fork and upstream | 560 MB and 560 MB | 703 MB and 703 MB |
| Silero | Identical, silence stays silent | |

The error rates count digits and spelled-out numbers as different words, so they compare the builds and do not grade the model.

The first pass exceeded the speed limit for v3, with one upstream round far from the others. The limit was kept, and 10 more alternating rounds were added. They put the ratio at 0.992, with the fastest rounds at 7.11 s for the fork and 7.19 s for upstream, so the first figure reads as noise from the other processes.

## Verdict

Pass. The outputs are identical, so the move changes no recognized text on this corpus. Synthetic voices are not real speech: a real voice has not run through either build here.

Diarization is out of scope, because Secreteo does not link it.
