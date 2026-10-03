"""Regression tests: real temporary profiles, with system mutations mocked."""
import ast
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "install-chromium.sh"
SOURCE = SCRIPT.read_text()


def embedded(marker):
    return SOURCE.split("<<'" + marker + "'\n", 1)[1].split("\n" + marker + "\n", 1)[0]


def bash(code, stdin="", cwd=None):
    return subprocess.run(["bash", "-c", f"source {shlex.quote(str(SCRIPT))}\n" + code],
                          input=stdin, text=True, capture_output=True, cwd=cwd)


class ProfileCleanup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.user = self.root / "test-user"
        self.user.mkdir()
        namespace = {"__name__": "cleanup_test"}
        exec(compile(embedded("CLEANUP_PY"), "CLEANUP_PY", "exec"), namespace)
        self.clean = namespace["clean_user"]

    def write(self, relative, text="keep me"):
        path = self.user / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def cleanup(self, runtimes=()):
        with patch("shutil.which", return_value=None):
            self.clean(self.user, runtimes)

    def test_removes_snap_data_preserves_deb_and_other_apps(self):
        for p in ("snap/chromium/common/Bookmarks", "snap/chromium_test/99/cache"):
            self.write(p, "delete")
        keep = [self.write(p) for p in (".config/chromium/Default/Bookmarks",
                ".cache/chromium/Cache/data", "snap/firefox/common/bookmarks",
                "snap/chromium-not-a-snap-instance/file", "Documents/work.txt")]
        self.cleanup()
        self.assertFalse((self.user / "snap/chromium").exists())
        self.assertFalse((self.user / "snap/chromium_test").exists())
        for p in keep:
            self.assertEqual(p.read_text(), "keep me")
        self.cleanup()  # Rerunning has no effect on preserved profiles.
        for p in keep:
            self.assertEqual(p.read_text(), "keep me")

    def test_empty_snap_folder_removed(self):
        self.write("snap/chromium/common/file")
        self.cleanup()
        self.assertFalse((self.user / "snap").exists())

    def test_runtime_data_only_removed_when_explicitly_retired(self):
        runtime = self.write("snap/gnome-42-2204/common/file")
        self.cleanup()
        self.assertTrue(runtime.exists())
        self.cleanup(["gnome-42-2204"])
        self.assertFalse((self.user / "snap").exists())

    def test_symlinked_snap_folder_cannot_escape_profile(self):
        outside = self.root / "outside"
        (outside / "chromium").mkdir(parents=True)
        victim = outside / "chromium/important"
        victim.write_text("keep")
        (self.user / "snap").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            self.cleanup()
        self.assertEqual(victim.read_text(), "keep")

    def test_profile_symlink_unlinked_without_following_target(self):
        outside = self.root / "outside"
        outside.mkdir()
        victim = outside / "important"
        victim.write_text("keep")
        (self.user / "snap").mkdir()
        (self.user / "snap/chromium").symlink_to(outside, target_is_directory=True)
        self.cleanup()
        self.assertEqual(victim.read_text(), "keep")
        self.assertFalse((self.user / "snap").exists())

    def test_launchers_associations_and_icons(self):
        self.write(".local/share/applications/chromium_chromium.desktop", "[Desktop Entry]\n")
        native = self.write(".local/share/applications/chromium.desktop", "[Desktop Entry]\nExec=/usr/bin/chromium %U\n")
        self.write(".config/user-dirs.dirs", 'XDG_DESKTOP_DIR="$HOME/Bureaublad"\n')
        old_shortcut = self.write("Bureaublad/My-browser.desktop", "[Desktop Entry]\nExec=/snap/bin/chromium %U\n")
        self.write(".config/autostart/old-browser.desktop", "[Desktop Entry]\nX-SnapInstanceName=chromium\n")
        icon = self.write(".local/share/icons/hicolor/256x256/apps/chromium_chromium.png")
        native_icon = self.write(".local/share/icons/chromium.png")
        mime = self.write(".config/mimeapps.list", "[Default Applications]\nx-scheme-handler/https=chromium_chromium.desktop;firefox.desktop;\ntext/plain=org.gnome.TextEditor.desktop;\n")
        self.cleanup()
        self.assertFalse(old_shortcut.exists())
        self.assertFalse(icon.exists())
        self.assertFalse((self.user / ".config/autostart/old-browser.desktop").exists())
        self.assertTrue(native.exists())
        self.assertTrue(native_icon.exists())
        self.assertIn("https=chromium.desktop;firefox.desktop;", mime.read_text())
        self.assertIn("text/plain=org.gnome.TextEditor.desktop;", mime.read_text())

    def test_symlinked_application_folder_not_modified(self):
        outside = self.root / "outside"
        outside.mkdir()
        victim = outside / "chromium_chromium.desktop"
        victim.write_text("keep")
        (self.user / ".local/share").mkdir(parents=True)
        (self.user / ".local/share/applications").symlink_to(outside, target_is_directory=True)
        self.cleanup()
        self.assertEqual(victim.read_text(), "keep")

    def test_gnome_favourite_replaced_without_changing_other_apps(self):
        calls = []
        def fake_run(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, "['firefox.desktop', 'chromium_chromium.desktop', 'org.gnome.Terminal.desktop']\n", "")
        with patch("shutil.which", return_value="present"), patch("subprocess.run", side_effect=fake_run):
            self.clean(self.user, [])
        saved = ast.literal_eval(calls[-1][-1])
        self.assertEqual(saved, ["firefox.desktop", "chromium.desktop", "org.gnome.Terminal.desktop"])


class ShellDecisions(unittest.TestCase):
    def test_platform_matrix(self):
        for arch in ("amd64", "arm64"):
            self.assertEqual(bash(f"assert_platform ubuntu 26.04 {arch}").returncode, 0)
        for args in ("ubuntu 24.04 amd64", "debian 13 arm64", "ubuntu 26.04 armhf", "ubuntu 26.04 i386"):
            self.assertNotEqual(bash(f"assert_platform {args}").returncode, 0)

    def test_confirmation_rejects_empty_no_and_eof(self):
        for reply in ("", "\n", "n\n", "no\n", "maybe\n"):
            self.assertNotEqual(bash("confirm_install", reply).returncode, 0)
        for reply in ("y\n", "yes\n", "YES\n"):
            self.assertEqual(bash("confirm_install", reply).returncode, 0)

    def test_snap_snapshot_deletion_is_scoped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "snap-names").write_text("chromium\nchromium_test\nfirefox\n")
            (root / "snap-saved").write_text("Set Snap Age\n7 chromium now\n7 firefox now\n8 chromium_test now\n")
            result = bash('''
WORK_DIR=$PWD
SNAP_AVAILABLE=1
snap() { printf '%s\\n' "$*" >>"$WORK_DIR/actions"; }
read_snap_list() { printf 'firefox\\n' >"$WORK_DIR/snap-names"; }
remove_chromium_snaps
''', cwd=tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / "actions").read_text().splitlines(), [
                "remove --purge chromium", "remove --purge chromium_test",
                "forget 7 chromium", "forget 8 chromium_test"])

    def test_remove_failure_stops_before_snapshot_deletion(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "snap-names").write_text("chromium\n")
            (root / "snap-saved").write_text("Set Snap Age\n7 chromium now\n")
            result = bash('''
WORK_DIR=$PWD
SNAP_AVAILABLE=1
snap() { printf '%s\\n' "$*" >>"$WORK_DIR/actions"; return 1; }
remove_chromium_snaps
''', cwd=tmp)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((root / "actions").read_text().splitlines(), ["remove --purge chromium"])

    def test_snapd_kept_for_other_or_unknown_apps(self):
        for app in ("firefox", "snap-store", "some-new-app"):
            with tempfile.TemporaryDirectory() as tmp:
                result = bash(f'''
WORK_DIR=$PWD
SNAP_AVAILABLE=1
read_snap_list() {{ printf '%s\\n' core22 gnome-42-2204 {app} >"$WORK_DIR/snap-names"; }}
snap() {{ exit 99; }}
apt_run() {{ exit 99; }}
remove_unused_snapd
''', cwd=tmp)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(app, result.stdout)

    def test_other_snapshots_keep_snapd(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = bash('''
WORK_DIR=$PWD
SNAP_AVAILABLE=1
read_snap_list() { printf 'core22\\n' >"$WORK_DIR/snap-names"; }
snap() { [[ $1 == saved ]] || exit 99; printf 'Set Snap Age\\n7 firefox now\\n'; }
apt_run() { exit 99; }
remove_unused_snapd
''', cwd=tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("saved data", result.stdout)

    def test_unused_snapd_removal_order_and_pin(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = bash('''
WORK_DIR=$PWD
SNAP_AVAILABLE=1
count=0
read_snap_list() {
    count=$((count+1))
    if [[ $count == 1 ]]; then printf '%s\\n' bare core22 gnome-42-2204 gtk-common-themes snapd; fi >"$WORK_DIR/snap-names"
}
snap() { if [[ $1 != saved ]]; then printf 'snap %s\\n' "$*" >>"$WORK_DIR/actions"; fi; }
package_present() { return 1; }
apt_run() { printf 'apt %s\\n' "$*" >>"$WORK_DIR/actions"; }
install() { cp -- "$3" "$WORK_DIR/final-pin"; }
remove_unused_snapd
[[ $SNAPD_REMOVED == 1 ]]
''', cwd=tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            actions = (root / "actions").read_text().splitlines()
            self.assertLess(actions.index("snap remove --purge gnome-42-2204"), actions.index("snap remove --purge core22"))
            self.assertLess(actions.index("snap remove --purge core22"), actions.index("apt purge -y snapd"))
            self.assertIn("Pin-Priority: -1", (root / "final-pin").read_text())

    def test_unexpected_apt_removal_aborts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "plan").write_text("Purg chromium-browser [1:snap]\nRemv ubuntu-desktop [1.0]\n")
            result = bash('check_removals "$PWD/plan" chromium-browser', cwd=tmp)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ubuntu-desktop", result.stderr)

    def test_snapd_service_failure_not_treated_as_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = bash('WORK_DIR=$PWD\nsnap() { printf "cannot contact snapd\\n" >&2; return 1; }\nread_snap_list', cwd=tmp)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Cannot inspect Snap", result.stderr)

    def test_removed_snapd_config_does_not_require_daemon(self):
        result = bash('dpkg-query() { printf "config-files"; }\ninspect_snap\n[[ $SNAP_AVAILABLE == 0 ]]')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_main_cancel_has_no_mutations(self):
        result = bash('''
check_platform() { :; }
ensure_root() { :; }
write_chromium_pin() { exit 99; }
apt_run() { exit 99; }
close_chromium() { exit 99; }
main
''', stdin="n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No changes made", result.stdout)

    def test_failed_candidate_or_download_keeps_old_browser(self):
        for failure in ("candidate", "download"):
            with tempfile.TemporaryDirectory() as tmp:
                log = Path(tmp) / "actions"
                result = bash(f'''
TEST_LOG={shlex.quote(str(log))}
FAILURE={failure}
check_platform() {{ :; }}
ensure_root() {{ :; }}
dpkg() {{ :; }}
inspect_snap() {{ :; }}
write_chromium_pin() {{ printf 'pin\\n' >>"$TEST_LOG"; }}
apt_run() {{
    printf 'apt %s\\n' "$*" >>"$TEST_LOG"
    if [[ $FAILURE == download && $* == *--download-only* ]]; then return 1; fi
}}
add-apt-repository() {{ :; }}
check_candidate() {{ if [[ $FAILURE == candidate ]]; then return 1; fi; }}
package_present() {{ return 1; }}
close_chromium() {{ printf 'CLOSE\\n' >>"$TEST_LOG"; }}
remove_chromium_snaps() {{ printf 'DELETE\\n' >>"$TEST_LOG"; }}
main
''', stdin="yes\n")
                self.assertNotEqual(result.returncode, 0)
                actions = log.read_text()
                self.assertNotIn("CLOSE", actions)
                self.assertNotIn("DELETE", actions)


if __name__ == "__main__":
    unittest.main()
