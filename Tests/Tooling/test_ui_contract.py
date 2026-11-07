import json
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCES = REPO / "Sources"
UI_TESTS = REPO / "Tests/SecreteoUITests"
CATALOG = REPO / "Apps/Secreteo/Localizable.xcstrings"

LITERAL = re.compile(
    r'(?:\bText|\bButton|\bToggle|\bLabel|\bLabeledContent|\bSection|\bPicker|\bTextField|\bProgressView)\(\s*"([^"\\]+)"'
    r'|String\(localized:\s*"([^"\\]+)"'
    r'|MenuRow\(title:\s*"([^"\\]+)"'
    r'|L10n\.(?:text|format)\(\s*(?://[^\n]*\n\s*)*"([^"\\]+)"'
    r'|LocalizedStringResource(?:\(|\s*=)\s*"([^"\\]+)"'
    r'|IntentDescription\(\s*(?://[^\n]*\n\s*)*"([^"\\]+)"'
    r'|@Parameter\(title:\s*"([^"\\]+)"'
)
# A placeholder, ignoring a positional index such as `%1$@`.
PLACEHOLDER = re.compile(r"%(?:\d+\$)?((?:\.\d+)?(?:ll|l)?[@dfsiu])")
# Brand names and words Spanish shares with English. Anything else left in English is untranslated.
SAME_IN_SPANISH = {
    "%d min", "App", "Apple Intelligence", "Apple Speech", "Fn (🌐)", "Formal", "Literal", "Ollama",
    "Parakeet", "Parakeet Ultra",
}
# A locale also takes `identifier:`, and it names no control. A label may end in `Identifier:`.
IDENTIFIER = re.compile(r'accessibilityIdentifier\("([^"]+)"\)|(?<!Locale\()(?:\bidentifier|[a-z]Identifier):\s*"([a-z][a-z-]+)"')


def swift_files(root: Path):
    return list(root.rglob("*.swift")) if root.exists() else []


class UIContractTests(unittest.TestCase):
    def test_a_locale_is_not_a_control_identifier(self):
        self.assertIsNone(IDENTIFIER.search('Locale(identifier: "en")'))
        self.assertEqual(IDENTIFIER.search('MenuRow(identifier: "menu-quit")').group(2), "menu-quit")
        self.assertEqual(IDENTIFIER.search('.accessibilityIdentifier("x")').group(1), "x")
        self.assertEqual(IDENTIFIER.search('Ids(fieldIdentifier: "practice-field")').group(2), "practice-field")

    def test_intent_strings_are_read_as_visible_strings(self):
        for source in ['static let title: LocalizedStringResource = "Dictate"',
                       'LocalizedStringResource("Dictate")', 'IntentDescription(\n        "Dictate")',
                       'IntentDescription(\n        // swiftlint:disable:next line_length\n        "Dictate")',
                       '@Parameter(title: "Dictate")']:
            match = LITERAL.search(source)
            self.assertEqual(next(group for group in match.groups() if group), "Dictate", source)

    def test_every_identifier_has_an_assertion(self):
        tests = "\n".join(path.read_text() for path in swift_files(UI_TESTS))
        for path in swift_files(SOURCES):
            for match in IDENTIFIER.finditer(path.read_text()):
                identifier = match.group(1) or match.group(2)
                self.assertIn(f'"{identifier}"', tests, f"{identifier} in {path.name} has no UI test assertion")

    def test_every_visible_string_is_in_the_catalog_with_spanish(self):
        catalog = json.loads(CATALOG.read_text())["strings"]
        for path in swift_files(SOURCES):
            for match in LITERAL.finditer(path.read_text()):
                key = next(group for group in match.groups() if group)
                self.assertIn(key, catalog, f"{key} in {path.name} is not in the catalog")

        for key, entry in catalog.items():
            spanish = entry.get("localizations", {}).get("es", {}).get("stringUnit", {})
            self.assertEqual(spanish.get("state"), "translated", f"{key} has no Spanish")
            self.assertTrue(spanish.get("value"), f"{key} has no Spanish")

    def test_catalog_keys_are_unique_on_disk(self):
        def refuse_duplicates(pairs):
            keys = [key for key, _ in pairs]
            duplicates = {key for key in keys if keys.count(key) > 1}
            self.assertEqual(duplicates, set(), "duplicate keys in the catalog")
            return dict(pairs)

        json.loads(CATALOG.read_text(), object_pairs_hook=refuse_duplicates)

    def test_spanish_keeps_every_placeholder(self):
        for key, entry in json.loads(CATALOG.read_text())["strings"].items():
            spanish = entry["localizations"]["es"]["stringUnit"]["value"]
            self.assertEqual(
                sorted(PLACEHOLDER.findall(spanish)), sorted(PLACEHOLDER.findall(key)), f"{key} -> {spanish}")

    def test_spanish_matches_english_only_for_shared_terms(self):
        catalog = json.loads(CATALOG.read_text())["strings"]
        same = {key for key, entry in catalog.items() if entry["localizations"]["es"]["stringUnit"]["value"] == key}
        self.assertLessEqual(same, SAME_IN_SPANISH, "left in English")

    def test_the_catalog_has_no_stale_keys(self):
        used = set()
        for path in swift_files(SOURCES):
            for match in LITERAL.finditer(path.read_text()):
                used.add(next(group for group in match.groups() if group))
        stale = set(json.loads(CATALOG.read_text())["strings"]) - used
        self.assertEqual(stale, set())

    def test_the_smoke_plan_stays_small_and_names_real_tests(self):
        tests = "\n".join(path.read_text() for path in swift_files(UI_TESTS))
        plan = [line for line in (REPO / "Tests/Plans/Smoke.txt").read_text().splitlines() if line]
        self.assertLessEqual(len(plan), 10)
        for entry in plan:
            self.assertIn(f"func {entry.rsplit('/', 1)[1]}(", tests)


if __name__ == "__main__":
    unittest.main()
