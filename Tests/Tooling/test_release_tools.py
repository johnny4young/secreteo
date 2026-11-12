import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


verify_release = load("verify_release")
verify_appcast = load("verify_appcast")
check_release = load("check_release")

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
    "CFBundleIconName": "AppIcon",
    "SecreteoGlobalDictation": "YES",
    "DictationOwnershipProtocol": 1,
}
GOOD_PATHS = ["Contents/Frameworks/Sparkle.framework", "Contents/Frameworks/Sparkle.framework/Sparkle",
              "Contents/MacOS/Secreteo", "Contents/Resources/THIRD-PARTY-NOTICES.md",
              "Contents/Resources/AppIcon.icns", "Contents/Resources/Assets.car"]
GOOD_SIGNATURE = (f"Authority=Developer ID Application: Someone\nTeamIdentifier={verify_release.TEAM_ID}\n"
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
                 "SUFeedURL": "http://example.test/appcast.xml", "SUEnableAutomaticChecks": False,
                 "CFBundleIconName": None, "SecreteoGlobalDictation": "NO", "DictationOwnershipProtocol": None}
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

    def test_a_missing_icon_fails(self):
        for icon in ("AppIcon.icns", "Assets.car"):
            problems = self.problems([p for p in GOOD_PATHS if not p.endswith(icon)])
            self.assertTrue(any(icon in problem for problem in problems), icon)

    def test_a_drifted_sparkle_fails(self):
        self.assertTrue(self.problems(GOOD_PATHS, sparkle="2.10.0"))


class SignatureTests(unittest.TestCase):
    def test_production_needs_runtime_developer_id_and_timestamp(self):
        check = verify_release.signature_problems
        self.assertEqual(check("x", GOOD_SIGNATURE, "", "production"), [])
        self.assertTrue(check("x", GOOD_SIGNATURE.replace("(runtime)", "(none)"), "", "production"))
        self.assertTrue(check("x", GOOD_SIGNATURE.replace("Developer ID Application", "Apple Development"), "", "production"))
        self.assertTrue(check("x", GOOD_SIGNATURE.replace("Timestamp=", "Signed Time="), "", "production"))
        self.assertTrue(check("x", GOOD_SIGNATURE.replace(verify_release.TEAM_ID, "OTHERTEAM1"), "", "production"))
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

    def test_a_newer_item_in_the_feed_fails(self):
        newer = re.search(r"<item>.*</item>", feed(short="1.10.0", build="1.10.0", url=""), re.DOTALL).group(0)
        self.assertTrue(feed_problems(feed().replace("</channel>", f"{newer}</channel>")))

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


PROJECT = 'settings:\n  base:\n    MARKETING_VERSION: "1.2.3"\n    SPARKLE_PUBLIC_ED_KEY: "abc="\n'
CHANGELOG = "# Changelog\n\n## Unreleased\n\n- Soon.\n\n## 1.2.3\n\n- Added this.\n- And that.\n\n## 1.2.2\n\n- Older.\n"


def release_problems(tag="v1.2.3", project=PROJECT, changelog=CHANGELOG, on_main=True, arms=False, cleared=""):
    return check_release.problems(tag, project, changelog, on_main, arms, cleared)


class CheckReleaseTests(unittest.TestCase):
    def test_the_command_reports_problems_instead_of_crashing(self):
        script = Path(__file__).resolve().parents[2] / "scripts/check_release.py"

        result = subprocess.run(
            [sys.executable, str(script), "check", "v0.0.0-test"], capture_output=True, text=True, check=False)

        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("::error::", result.stdout)

    def test_a_release_build_arms_dictation_unless_the_project_says_no(self):
        self.assertFalse(check_release.arms_global_dictation("        SECRETEO_GLOBAL_DICTATION: NO\n"))
        self.assertTrue(check_release.arms_global_dictation("        SECRETEO_GLOBAL_DICTATION: YES\n"))
        self.assertTrue(check_release.arms_global_dictation("        OTHER: NO\n"))
        repository = Path(__file__).resolve().parents[2]
        # D28: release builds dictate, so every release needs GLOBAL_DICTATION_CLEARED.
        self.assertTrue(check_release.arms_global_dictation((repository / "project.yml").read_text()))

    def test_only_a_debug_config_may_turn_dictation_on(self):
        base = "settings:\n  base:\n    SECRETEO_GLOBAL_DICTATION: NO\n  configs:\n"
        self.assertFalse(check_release.arms_global_dictation(base + "    Debug:\n      SECRETEO_GLOBAL_DICTATION: YES\n"))
        self.assertTrue(check_release.arms_global_dictation(base + "    Release:\n      SECRETEO_GLOBAL_DICTATION: YES\n"))
        self.assertTrue(check_release.arms_global_dictation(
            base + "    Debug:\n      SECRETEO_GLOBAL_DICTATION: YES\n    Release:\n      SECRETEO_GLOBAL_DICTATION: YES\n"))

    def test_only_a_release_build_carries_the_update_key(self):
        project = (ROOT / "project.yml").read_text()
        self.assertRegex(check_release.project_setting(project, "SPARKLE_PUBLIC_ED_KEY"), r"^[A-Za-z0-9+/]{43}=$")
        debug = project.split("        Debug:\n", 1)[1].split("    info:", 1)[0]
        self.assertIn('SPARKLE_PUBLIC_ED_KEY: ""', debug)
        install = (ROOT / "Makefile").read_text().split("\ninstall:", 1)[1].split("\n\n", 1)[0]
        self.assertIn("SPARKLE_PUBLIC_ED_KEY= ", install)

    def test_the_dev_install_renames_only_the_app(self):
        install = (ROOT / "Makefile").read_text().split("\ninstall:", 1)[1].split("\n\n", 1)[0]
        # A command-line PRODUCT_NAME reaches every target, and they all collide on one module.
        self.assertNotRegex(install, r"(?<![A-Z_])PRODUCT_(NAME|BUNDLE_IDENTIFIER)=")
        self.assertIn('APP_PRODUCT_NAME="Secreteo Dev"', install)
        project = (ROOT / "project.yml").read_text()
        self.assertIn("PRODUCT_NAME: $(APP_PRODUCT_NAME)", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: $(APP_BUNDLE_IDENTIFIER)", project)

    def test_a_correct_tag_passes(self):
        self.assertEqual(release_problems(), [])

    def test_notes_stop_at_the_next_section(self):
        self.assertEqual(check_release.release_notes(CHANGELOG, "1.2.3"), "- Added this.\n- And that.")
        self.assertEqual(check_release.release_notes(CHANGELOG, "1.2.2"), "- Older.")
        self.assertEqual(check_release.release_notes(CHANGELOG, "1.2"), "")

    def test_each_refusal(self):
        cases = {"format": {"tag": "v1.2.3-beta.1"}, "no v": {"tag": "1.2.3"}, "version": {"tag": "v1.2.4"},
                 "key": {"project": PROJECT.replace('"abc="', '""')}, "off main": {"on_main": False},
                 "notes": {"changelog": CHANGELOG.replace("- Added this.\n- And that.\n", "")}}
        for name, values in cases.items():
            self.assertTrue(release_problems(**values), name)

    def test_an_armed_release_needs_its_own_clearance(self):
        self.assertTrue(release_problems(arms=True))
        self.assertEqual(release_problems(arms=True, cleared="1.2.3"), [])
        for stale in ("true", "1.2.2", "v1.2.3", "1.2.3.0"):
            self.assertTrue(release_problems(arms=True, cleared=stale), stale)
        self.assertEqual(release_problems(arms=False, cleared="1.2.2"), [])


class CaskTests(unittest.TestCase):
    sha = "a" * 64

    def render(self, version, sha256):
        return subprocess.run([str(ROOT / "scripts/render-cask.sh"), version, sha256], capture_output=True, text=True,
                              check=False)

    def test_the_render_fills_the_template(self):
        rendered = self.render("1.2.3", self.sha)
        self.assertEqual(rendered.returncode, 0, rendered.stderr)
        self.assertTrue(rendered.stdout.startswith('cask "secreteo" do'))
        self.assertIn('version "1.2.3"', rendered.stdout)
        self.assertIn(f'sha256 "{self.sha}"', rendered.stdout)
        self.assertNotIn("__", rendered.stdout)

    def test_the_render_refuses_bad_values(self):
        for version, sha256 in (("1.2", self.sha), ("1.2.3; rm", self.sha), ("1.2.3", "abc"), ("1.2.3", "A" * 64)):
            self.assertNotEqual(self.render(version, sha256).returncode, 0, (version, sha256))

    def test_the_cask_contract(self):
        text = (ROOT / "packaging/Casks/secreteo.rb").read_text()
        self.assertIn("depends_on arch: :arm64", text)
        self.assertIn("releases/download/v#{version}/Secreteo-#{version}.dmg", text)
        self.assertIn("auto_updates true", text)
        self.assertNotIn("conflicts_with", text)
        self.assertNotIn("local-models", text.split("zap trash:")[1])


class WorkflowContractTests(unittest.TestCase):
    def workflow_names(self):
        return sorted(path.name for path in (ROOT / ".github/workflows").glob("*.yml"))

    def workflow(self, name):
        return (ROOT / ".github/workflows" / name).read_text()

    def test_only_the_package_job_reads_signing_secrets(self):
        text = self.workflow("release.yml")
        package = re.search(r"^  package:\n(.*?)^  draft:", text, re.MULTILINE | re.DOTALL).group(1)
        outside = text.replace(package, "")
        self.assertIn("environment: release", package)
        self.assertNotIn("contents: write", package)
        self.assertNotRegex(outside, r"secrets\.[A-Z]")

    def test_each_workflow_reads_only_its_own_secrets(self):
        expected = {"update-cask.yml": {"TAP_DEPLOY_KEY"},
                    "pages.yml": {"CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"}}
        for name in self.workflow_names():
            if name == "release.yml":
                continue
            found = set(re.findall(r"secrets\.([A-Z0-9_]+)", self.workflow(name)))
            self.assertEqual(found, expected.get(name, set()), name)
        self.assertIn("environment: homebrew", self.workflow("update-cask.yml"))
        self.assertIn("environment: site", self.workflow("pages.yml"))

    def test_the_cask_serves_only_final_releases(self):
        self.assertIn(".isDraft or .isPrerelease", self.workflow("update-cask.yml"))

    def test_signing_turns_gatekeeper_on_first(self):
        text = (ROOT / "scripts/setup-release-signing.sh").read_text()
        self.assertLess(text.index("enable-gatekeeper.sh"), text.index("security import"))

    def test_a_tag_only_creates_a_draft(self):
        text = self.workflow("release.yml")
        self.assertIn("--draft", text)
        self.assertEqual(text.count("gh release create"), 1)

    def test_the_default_token_is_read_only(self):
        for name in self.workflow_names():
            self.assertRegex(self.workflow(name), r"(?m)^permissions:\n  contents: read$", name)

    def test_nothing_privileged_runs_on_untrusted_input(self):
        for name in ("release.yml", "update-cask.yml", "pages.yml"):
            text = self.workflow(name)
            self.assertNotIn("pull_request", text, name)
            for line in text.splitlines():
                if "${{" in line:
                    self.assertRegex(line, r"^\s*(?!run\b)[A-Za-z_][\w-]*: ", name)

    def test_node_follows_the_version_file(self):
        text = self.workflow("pages.yml")
        self.assertIn("node-version-file: .nvmrc", text)
        self.assertIn("check-latest: true", text)


class AssessmentTests(unittest.TestCase):
    def test_a_real_acceptance_passes(self):
        output = "x: accepted\nsource=Notarized Developer ID\n"
        self.assertEqual(verify_release.assessment_problem("spctl", 0, output), "")

    def test_a_rejection_fails(self):
        self.assertTrue(verify_release.assessment_problem("spctl", 3, "x: rejected\n"))

    def test_an_acceptance_with_gatekeeper_off_fails(self):
        output = "x: accepted\noverride=security disabled\n"
        self.assertTrue(verify_release.assessment_problem("spctl", 0, output))


class TapTests(unittest.TestCase):
    sha = "b" * 64

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.bare = self.root / "tap.git"
        self.git("init", "-q", "--bare", "-b", "main", str(self.bare))
        self.seed = self.root / "seed"
        self.git("clone", "-q", str(self.bare), str(self.seed))
        (self.seed / "Casks").mkdir()
        (self.seed / "Casks/other.rb").write_text("# another app\n")
        self.push_seed("seed")

    def git(self, *arguments, cwd=None):
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.test", *arguments], cwd=cwd,
                       check=True, capture_output=True)

    def push_seed(self, message):
        self.git("add", "-A", cwd=self.seed)
        self.git("commit", "-q", "-m", message, cwd=self.seed)
        self.git("push", "-q", "origin", "HEAD:main", cwd=self.seed)

    def publish(self, version):
        environment = os.environ | {"TAP_DEPLOY_KEY": "test", "TAP_URL": str(self.bare)}
        return subprocess.run([str(ROOT / "scripts/update-homebrew-tap.sh"), version, self.sha], env=environment,
                              capture_output=True, text=True, check=False)

    def served(self):
        self.git("pull", "-q", "origin", "main", cwd=self.seed)
        path = self.seed / "Casks/secreteo.rb"
        return path.read_text() if path.exists() else ""

    def test_it_publishes_and_keeps_other_casks(self):
        result = self.publish("1.2.3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('version "1.2.3"', self.served())
        self.assertTrue((self.seed / "Casks/other.rb").exists())

    def test_a_rerun_changes_nothing(self):
        self.publish("1.2.3")
        self.assertIn("already serves", self.publish("1.2.3").stdout)

    def test_a_delayed_run_cannot_go_back(self):
        self.publish("1.10.0")
        result = self.publish("1.9.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('version "1.10.0"', self.served())

    def test_a_rejected_push_retries_from_a_fresh_clone(self):
        hook = self.bare / "hooks/pre-receive"
        marker = self.root / "rejected-once"
        hook.write_text(f'#!/bin/sh\n[ -e "{marker}" ] && exit 0\ntouch "{marker}"\nexit 1\n')
        hook.chmod(0o755)
        result = self.publish("1.2.3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("rejected", result.stdout)
        self.assertIn('version "1.2.3"', self.served())

    def test_it_refuses_to_run_without_a_key(self):
        environment = {key: value for key, value in os.environ.items() if key != "TAP_DEPLOY_KEY"}
        result = subprocess.run([str(ROOT / "scripts/update-homebrew-tap.sh"), "1.2.3", self.sha], env=environment,
                                capture_output=True, text=True, check=False)
        self.assertNotEqual(result.returncode, 0)


class ContractTests(unittest.TestCase):
    def test_packaging_never_ignores_a_failure(self):
        for name in ("package-release.sh", "sign-app.sh", "generate-appcast.sh"):
            text = (ROOT / "scripts" / name).read_text()
            self.assertIn("set -euo pipefail", text)
            self.assertNotRegex(text, r"\|\|\s*true")

    def test_every_sparkle_helper_is_signed_before_the_app(self):
        text = (ROOT / "scripts/sign-app.sh").read_text()
        order = [text.index(f'sign {marker}') for marker in (
            '"$current/XPCServices/Installer.xpc"', '--preserve-metadata=entitlements "$current/XPCServices/Downloader.xpc"',
            '"$current/Autoupdate"', '"$current/Updater.app"', '"$sparkle"', '--entitlements')]
        self.assertEqual(order, sorted(order))

    def test_every_signed_build_goes_through_one_recipe(self):
        self.assertIn("scripts/sign-app.sh", (ROOT / "scripts/package-release.sh").read_text())
        makefile = (ROOT / "Makefile").read_text()
        self.assertIn("scripts/sign-app.sh", makefile)
        self.assertNotIn("codesign --force", makefile)

    def test_a_bad_version_is_refused_before_anything_is_deleted(self):
        text = (ROOT / "scripts/package-release.sh").read_text()
        self.assertLess(text.index("is not x.y.z"), text.index("rm -rf"))

    def test_build_number_follows_the_version(self):
        self.assertRegex((ROOT / "project.yml").read_text(), r"CURRENT_PROJECT_VERSION: \$\(MARKETING_VERSION\)")

    def test_the_real_update_refuses_to_run_off_a_hosted_runner(self):
        text = (ROOT / "scripts/release-dryrun.sh").read_text()
        update = re.search(r"^update\(\) \{(.*?)^\}", text, re.MULTILINE | re.DOTALL).group(1)
        self.assertLess(update.index("github-hosted"), update.index('rm -rf "$installed"'))


if __name__ == "__main__":
    unittest.main()
