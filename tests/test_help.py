"""The help path must not require root or initialize hardware/logging."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
SCRIPT = Path(os.environ.get("SMARTWATCH_SOURCE", REPO / "SmartWatch/ugreen-smart-report.sh"))


class HelpTests(unittest.TestCase):
    def test_help_without_privileged_initialization(self):
        for language in ("de", "en"):
            for option in ("--help", "-h", "--"):
                with self.subTest(language=language, option=option), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    audit = root / "privilege-check"
                    env = dict(os.environ, ENV_FILE="/dev/null", LANGUAGE=language, LOG_DIR=str(root / "logs"),
                               AUDIT_FILE=str(audit))
                    # If initialization is reached, stop at the privilege check.
                    # This protects the test host even when testing an older script.
                    code = '''
id() { printf called > "$AUDIT_FILE"; printf '65534\\n'; }
export -f id
exec bash "$1" "$2"
'''
                    result = subprocess.run(["bash", "-c", code, "test", str(SCRIPT), option],
                                            env=env, capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                    self.assertIn("UGREEN SMART Report", result.stdout)
                    self.assertFalse(audit.exists())
                    self.assertFalse((root / "logs").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
