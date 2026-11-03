import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


verify_release = load("verify_release")
verify_appcast = load("verify_appcast")

VERSION = "1.2.3"
KEY = "A" * 43 + "="
GOOD_INFO = {
    "CFBundleIdentifier": verify_release.BUNDLE_ID,
    "CFBundleShortVersionString": VERSION,
    "CFBundleVersion": VERSION,
    "LSMinimumSystemVersion": "26.0",
    "LSUIElement": True,
    "SUFeedURL": verify_release.FEED,
    "SUEnableAutomaticChecks": True,
    "SUPublicEDKey": KEY,
}
GOOD_PATHS = ["Contents/Frameworks/Sparkle.framework", "Contents/Frameworks/Sparkle.framework/Sparkle",
              "Contents/MacOS/Secreteo", "Contents/Resources/THIRD-PARTY-NOTICES.md"]
GOOD_SIGNATURE = ("Authority=Developer ID Application: Someone (TEAM)\n"
                  "Timestamp=Nov 2, 2026\nCodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1\n")
PREFIX = "https://example.test/download/v1.2.3/"
DMG = "Secreteo-1.2.3.dmg"


def feed(short=VERSION, build=VERSION, minimum="26.0", hardware="arm64", notes="<p>Notes</p>",
         url=PREFIX + DMG, length="42", signature="c2ln"):
    enclosure = f'<enclosure url="{url}" length="{length}" sparkle:edSignature="{signature}"/>' if url else ""
    return f"""<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>{hardware}</sparkle:hardwareRequirements>
      <description><![CDATA[{notes}]]></description>{enclosure}
    </item></channel></rss>"""


def feed_problems(xml: str) -> list[str]:
    return verify_appcast.feed_problems(xml, VERSION, PREFIX, DMG, 42)


class InfoTests(unittest.TestCase):
    def test_a_correct_bundle_passes(self):
        self.assertEqual(verify_release.info_problems(GOOD_INFO, VERSION), [])

    def test_each_wrong_value_fails(self):
        wrong = {"CFBundleIdentifier": "com.johnny4young.secreteo.dev", "CFBundleShortVersionString": "1.2.2",
                 "CFBundleVersion": "1", "LSMinimumSystemVersion": "15.0", "LSUIElement": False,
                 "SUFeedURL": "http://example.test/appcast.xml", "SUEnableAutomaticChecks": False}
        for key, value in wrong.items():
            self.assertTrue(verify_release.info_problems(GOOD_INFO | {key: value}, VERSION), key)

    def test_an_empty_or_malformed_key_fails(self):
        for key in ("", "not base64!", "c2hvcnQ="):
            self.assertTrue(verify_release.info_problems(GOOD_INFO | {"SUPublicEDKey": key}, VERSION), key)


class PayloadTests(unittest.TestCase):
    def problems(self, paths, sparkle="2.10.1"):
        return verify_release.payload_problems(paths, sparkle, "2.10.1")

    def test_a_clean_payload_passes(self):
        self.assertEqual(self.problems(GOOD_PATHS), [])

    def test_debug_and_tool_files_fail(self):
        for extra in ("Contents/MacOS/Secreteo.debug.dylib", "Contents/MacOS/__preview.dylib",
                      "Contents/Resources/Secreteo.dSYM", "Contents/PlugIns/Tests.xctest",
                      "Contents/Resources/generate_appcast"):
            self.assertTrue(self.problems(GOOD_PATHS + [extra]), extra)

    def test_an_unexpected_framework_fails(self):
        self.assertTrue(self.problems(GOOD_PATHS + ["Contents/Frameworks/Other.framework"]))

    def test_missing_notices_fail(self):
        self.assertTrue(self.problems([p for p in GOOD_PATHS if "NOTICES" not in p]))

    def test_a_drifted_sparkle_fails(self):
        self.assertTrue(self.problems(GOOD_PATHS, sparkle="2.10.0"))


class SignatureTests(unittest.TestCase):
    def test_production_needs_runtime_developer_id_and_timestamp(self):
        check = verify_release.signature_problems
        self.assertEqual(check("x", GOOD_SIGNATURE, "", "production"), [])
        self.assertTrue(check("x", GOOD_SIGNATURE.replace("(runtime)", "(none)"), "", "production"))
        self.assertTrue(check("x", GOOD_SIGNATURE.replace("Developer ID Application", "Apple Development"), "", "production"))
        self.assertTrue(check("x", GOOD_SIGNATURE.replace("Timestamp=", "Signed Time="), "", "production"))
        self.assertTrue(check("x", "Signature=adhoc\n", "", "production"))

    def test_get_task_allow_fails_in_every_mode(self):
        entitlements = "<key>com.apple.security.get-task-allow</key>"
        self.assertTrue(verify_release.signature_problems("x", GOOD_SIGNATURE, entitlements, "production"))
        self.assertTrue(verify_release.signature_problems("x", "Signature=adhoc\n", entitlements, "dryrun"))

    def test_dry_run_is_ad_hoc(self):
        self.assertEqual(verify_release.signature_problems("x", "Signature=adhoc\n", "", "dryrun"), [])
        self.assertTrue(verify_release.signature_problems("x", GOOD_SIGNATURE, "", "dryrun"))


class AppcastTests(unittest.TestCase):
    def test_a_correct_item_passes(self):
        self.assertEqual(feed_problems(feed()), [])

    def test_older_items_are_ignored(self):
        older = re.search(r"<item>.*</item>", feed(short="1.2.2", build="1.2.2", url=""), re.DOTALL).group(0)
        two = feed().replace("</channel>", f"{older}</channel>")
        self.assertEqual(feed_problems(two), [])

    def test_each_wrong_value_fails(self):
        cases = {"short": {"short": "1.2.2"}, "build": {"build": "7"}, "os": {"minimum": "15.0"},
                 "intel": {"hardware": ""}, "notes": {"notes": ""}, "floating": {"url": "https://example.test/latest/x.dmg"},
                 "no enclosure": {"url": ""}, "length": {"length": "41"}, "unsigned": {"signature": ""}}
        for name, values in cases.items():
            self.assertTrue(feed_problems(feed(**values)), name)


class ContractTests(unittest.TestCase):
    def test_packaging_never_ignores_a_failure(self):
        for name in ("package-release.sh", "generate-appcast.sh"):
            text = (ROOT / "scripts" / name).read_text()
            self.assertIn("set -euo pipefail", text)
            self.assertNotRegex(text, r"\|\|\s*true")

    def test_every_sparkle_helper_is_signed_before_the_app(self):
        text = (ROOT / "scripts/package-release.sh").read_text()
        order = [text.index(f'sign {marker}') for marker in (
            '"$current/XPCServices/Installer.xpc"', '--preserve-metadata=entitlements "$current/XPCServices/Downloader.xpc"',
            '"$current/Autoupdate"', '"$current/Updater.app"', '"$sparkle"', '--entitlements')]
        self.assertEqual(order, sorted(order))

    def test_build_number_follows_the_version(self):
        self.assertRegex((ROOT / "project.yml").read_text(), r"CURRENT_PROJECT_VERSION: \$\(MARKETING_VERSION\)")

    def test_the_real_update_refuses_to_run_off_a_hosted_runner(self):
        text = (ROOT / "scripts/release-dryrun.sh").read_text()
        update = re.search(r"^update\(\) \{(.*?)^\}", text, re.MULTILINE | re.DOTALL).group(1)
        self.assertLess(update.index("github-hosted"), update.index('rm -rf "$installed"'))


if __name__ == "__main__":
    unittest.main()
