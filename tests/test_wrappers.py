"""The two executables, run the way the panel and the timer run them.

These are the only files that execute inside the installed plugin folder, and
the folder is watched: Omarchy's shell reloads a plugin -- unloading its
panel, and killing whatever that panel started -- when any file under it
changes. So what these must not do is write there.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SYNC_DIR = Path(__file__).resolve().parent.parent / "sync"


class BytecodeTests(unittest.TestCase):
    """Importing the package must leave no .pyc in the plugin folder.

    Python's default is to write the cache next to the source, which here is
    inside the watched folder: running the connect helper from the settings
    page reloaded the plugin out from under the connect helper, and the
    account came back as "not connected" with no events behind it.
    """

    def run_wrapper(self, name, args=(), stdin=""):
        """Run one wrapper from a throwaway copy, with a throwaway cache."""
        workspace = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, workspace, ignore_errors=True)

        plugin = workspace / "sync"
        shutil.copytree(
            SYNC_DIR, plugin,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )

        env = dict(os.environ)
        env["XDG_CACHE_HOME"] = str(workspace / "cache")
        env.pop("PYTHONDONTWRITEBYTECODE", None)
        subprocess.run(
            [sys.executable, str(plugin / name), *args],
            input=stdin, capture_output=True, text=True, env=env, timeout=60,
        )
        return plugin, workspace / "cache"

    def test_the_sync_writes_no_bytecode_into_the_plugin_folder(self):
        plugin, cache = self.run_wrapper("omarchy-calendar-sync", ["--help"])
        self.assertEqual(list(plugin.rglob("*.pyc")), [])
        self.assertEqual(list(plugin.rglob("__pycache__")), [])
        # Not merely disabled: the cache still exists, somewhere unwatched.
        self.assertTrue(list(cache.rglob("*.pyc")))

    def test_the_connect_writes_no_bytecode_into_the_plugin_folder(self):
        # An empty request is refused, which is fine: the imports have already
        # happened by then, and the imports are what writes.
        plugin, cache = self.run_wrapper(
            "omarchy-calendar-connect", stdin='{"action":"status"}\n')
        self.assertEqual(list(plugin.rglob("*.pyc")), [])
        self.assertEqual(list(plugin.rglob("__pycache__")), [])
        self.assertTrue(list(cache.rglob("*.pyc")))


if __name__ == "__main__":
    unittest.main()
