# Spike: model path and Core ML specialization

The shared model path is permanent ([D9](../DECISIONS.md#d9-shared-model-folder)), and Core ML ties compiled output to the path. This has to be settled before the store layout ships.

## Questions

1. Does the `.noindex` suffix keep Spotlight out of a directory under Application Support?
2. Does Core ML load correctly, at normal speed, from a `.noindex` path with read-only `0444` files?
3. How long does specialization take at a new path, and is it paid again per app identity?
4. Does a Time Machine exclusion on the root cover everything below it?

## Method

Everything runs under a throwaway sibling of the real path, and the harness never writes to the source models.

- **Models:** Parakeet TDT 0.6B v3 and Silero VAD, cloned with `clonefile` and made `0444`. Compute units match the FluidAudio defaults: preprocessor and Silero on CPU, the other Parakeet parts on CPU and Neural Engine.
- **Spotlight:** the same random token goes in `.txt` and `.json` files under a control directory and under `v1.noindex/models/x/payload/`. Nothing forces an import. `mdfind` polls until the control is found, then for 5 more minutes.
- **Cold load:** a new process loads a fresh clone at a new path. 5 samples each for `.noindex` and plain paths, in alternating order.
- **Warm load:** a new process loads the same path again. 5 samples.
- **Second identity:** an identically built binary with another name loads a path the first has already warmed. 3 samples, each at a new path.
- **Time Machine:** set `isExcludedFromBackup` on the root and ask `tmutil isexcluded` about a nested file.

## Thresholds

Written before measuring.

| Question | Passes if |
|---|---|
| Spotlight | The control is found within 10 minutes, and no file under `.noindex` is found by the end of the window. A control that is never found makes the result inconclusive, not a pass |
| Core ML | Every load succeeds from `.noindex` with `0444` files. Cold p50 at `.noindex` is within 15% of plain |
| Time Machine | The nested file reports excluded |

## Onboarding message rule

Also written before measuring. The spike passes once this rule yields a defined message.

| Result | Onboarding behavior |
|---|---|
| Cold p95 for all of Parakeet is 3 s or less | No separate step |
| Cold p95 is above 3 s | An explicit warm-up step with an indeterminate indicator and no time estimate, because only one chip is measured |
| A second identity pays near-cold cost (above 50% of cold p50) | The step runs even when the model is already in the store. "Installed" never reads as "ready" |

## Results

Pending.
