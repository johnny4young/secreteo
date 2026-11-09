# Public dictation search corpus

`public-synthetic-v1.json` holds 160 synthetic dictations in English and Spanish and
80 questions about them: exact wording, English and Spanish paraphrases, questions in
the other language, code-switched questions, and questions nothing answers.
`scripts/dictation_search_quality.py verify-public` checks it against its generator.

## Observe search over the corpus

`DictationSearchQualityTests` seeds the corpus into an in-memory store and asks every
question two ways: the history window's word search, and a cosine scan over Apple's
on-device sentence model (`NLContextualEmbedding`, Latin script). It also times both
over the corpus replicated to each scale. The observations hold identities and
numbers, never text. Build in Release, since a Debug scan is several times slower
than the app's would be:

```sh
swift build -c release --build-tests -Xswiftc -enable-testing
SECRETEO_SEARCH_OBSERVATIONS=/absolute/scratch/search-observations.json \
SECRETEO_SEARCH_COMMIT="$(git rev-parse HEAD)" \
SECRETEO_SEARCH_BUILD=release-local \
"$(xcrun --find xctest)" -XCTest DictationStoreTests.DictationSearchQualityTests/testPublicSearchObservations \
  .build/release/DictationStoreTests.xctest
python3 -I scripts/dictation_search_quality.py evaluate \
  --observations /absolute/scratch/search-observations.json \
  --output /absolute/scratch/search-scorecard.json
```

`SECRETEO_SEARCH_SCALES` sets the replicated sizes (default `1000,10000`). The sentence
model is never downloaded unless `SECRETEO_SEARCH_ASSET_DOWNLOAD=1`; without its assets
the lane fails instead of measuring something else. Without `SECRETEO_SEARCH_OBSERVATIONS`
the test skips. The scorecard derives the hybrid ranking, sweeps the similarity
threshold, and says whether a semantic lane clears the recall, false-positive and
latency gates. Secreteo has no query rewriting, so that lane always reads unavailable.
