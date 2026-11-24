"""Check every embedded mail transport without running hardware commands."""

import ast
import os
from pathlib import Path
import re
import smtplib
import socket
import ssl
import unittest
from unittest.mock import MagicMock, patch


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get("SMARTWATCH_SOURCE", ROOT / "SmartWatch/ugreen-smart-report.sh"))


def delivery_blocks():
    blocks = []
    for source in re.findall(r"<<'PYEOF'\n(.*?)\nPYEOF", SOURCE.read_text(), re.S):
        tree = ast.parse(source)
        imports = [node for node in tree.body if isinstance(node, (ast.Import, ast.ImportFrom))]
        for node in ast.walk(tree):
            if (isinstance(node, ast.If) and isinstance(node.test, ast.Name)
                    and node.test.id == "SMTP_USE_SSL"):
                blocks.append(compile(ast.Module(body=imports + [node], type_ignores=[]),
                                      str(SOURCE), "exec"))
    return blocks


class SmtpTlsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blocks = delivery_blocks()

    def setUp(self):
        network = patch.object(socket, "create_connection", side_effect=AssertionError("No network in tests"))
        network.start()
        self.addCleanup(network.stop)

    def run_delivery(self, block, *, implicit=False, tls=True, user="test-user", failure=None):
        server = MagicMock()
        server.__enter__.return_value = server
        if failure and not implicit:
            server.starttls.side_effect = failure
        with patch.object(smtplib, "SMTP", return_value=server) as plain, \
             patch.object(smtplib, "SMTP_SSL", return_value=server) as secure:
            if failure and implicit:
                secure.side_effect = failure
            scope = {
                "SMTP_USE_SSL": implicit, "SMTP_USE_TLS": tls,
                "SMTP_SERVER": "smtp.example.test", "SMTP_PORT": 465 if implicit else 587,
                "SMTP_USER": user, "SMTP_PASS": "test-password", "DEBUG_SMTP": False,
                "msg": object(),
            }
            if failure:
                with self.assertRaises(type(failure)):
                    exec(block, scope)
            else:
                exec(block, scope)
            return server, plain, secure

    def assert_verified_context(self, context):
        self.assertIsInstance(context, ssl.SSLContext)
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(context.check_hostname)

    def test_all_four_mail_paths_are_covered(self):
        self.assertEqual(len(self.blocks), 4)

    def test_starttls_checks_certificate_and_hostname_before_authentication(self):
        for index, block in enumerate(self.blocks):
            with self.subTest(mail_path=index):
                server, plain, secure = self.run_delivery(block)
                plain.assert_called_once()
                secure.assert_not_called()
                self.assert_verified_context(server.starttls.call_args.kwargs.get("context"))
                calls = [call[0] for call in server.method_calls]
                self.assertLess(calls.index("starttls"), calls.index("login"))
                self.assertLess(calls.index("login"), calls.index("send_message"))

    def test_implicit_tls_checks_certificate_and_hostname(self):
        for index, block in enumerate(self.blocks):
            with self.subTest(mail_path=index):
                server, plain, secure = self.run_delivery(block, implicit=True)
                plain.assert_not_called()
                self.assert_verified_context(secure.call_args.kwargs.get("context"))
                server.starttls.assert_not_called()
                server.send_message.assert_called_once()

    def test_tls_failures_do_not_authenticate_or_deliver(self):
        for index, block in enumerate(self.blocks):
            for implicit in (False, True):
                for error in (ssl.SSLCertVerificationError("untrusted certificate"),
                              ssl.SSLCertVerificationError("hostname mismatch")):
                    with self.subTest(mail_path=index, implicit=implicit, error=str(error)):
                        server, _, _ = self.run_delivery(block, implicit=implicit, failure=error)
                        server.login.assert_not_called()
                        server.send_message.assert_not_called()

    def test_explicit_plain_mode_and_optional_authentication_remain_available(self):
        for index, block in enumerate(self.blocks):
            for tls in (False, True):
                with self.subTest(mail_path=index, tls=tls):
                    server, plain, secure = self.run_delivery(block, tls=tls, user="")
                    plain.assert_called_once()
                    secure.assert_not_called()
                    server.login.assert_not_called()
                    self.assertEqual(server.starttls.call_count, int(tls))
                    server.send_message.assert_called_once()


if __name__ == "__main__":
    unittest.main()
