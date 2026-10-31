"""Offline regression tests for pub.dev detection; never publish or query the network."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github/scripts/pub-dev-version-published.sh"


class PubDevVersionPublishedTests(unittest.TestCase):
    def run_check(self, body="", status="200", curl_exit=0, version="0.1.0"):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            bin_directory = directory / "bin"
            bin_directory.mkdir()
            curl = bin_directory / "curl"
            curl.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "args = sys.argv[1:]\n"
                "Path(os.environ['TEST_ARGS']).write_text(json.dumps(args))\n"
                "if int(os.environ['TEST_CURL_EXIT']):\n"
                "    sys.exit(int(os.environ['TEST_CURL_EXIT']))\n"
                "output = args[args.index('--output') + 1]\n"
                "Path(output).write_text(os.environ['TEST_BODY'])\n"
                "sys.stdout.write(os.environ['TEST_HTTP_STATUS'])\n"
            )
            curl.chmod(0o755)
            args_path = directory / "args.json"
            environment = {
                **os.environ,
                "PATH": f"{bin_directory}{os.pathsep}{os.environ['PATH']}",
                "TMPDIR": temporary,
                "TEST_ARGS": str(args_path),
                "TEST_BODY": body,
                "TEST_HTTP_STATUS": status,
                "TEST_CURL_EXIT": str(curl_exit),
            }
            result = subprocess.run(
                ["bash", str(SCRIPT), "advanced_webview", version],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )
            args = json.loads(args_path.read_text())
            self.assertEqual(args[-1], "https://pub.dev/api/packages/advanced_webview")
            self.assertIn("Accept: application/vnd.pub.v2+json", args)
            self.assertIn("--connect-timeout", args)
            self.assertIn("--max-time", args)
            self.assertIn("--retry-max-time", args)
            # The response file is removed on success and on error.
            self.assertFalse(
                any(path.is_file() and path.name != "args.json" for path in directory.iterdir())
            )
            return result

    @staticmethod
    def metadata(*versions, name="advanced_webview"):
        return json.dumps(
            {"name": name, "versions": [{"version": version} for version in versions]}
        )

    def assert_failure(self, **kwargs):
        result = self.run_check(**kwargs)
        self.assertNotEqual(result.returncode, 0, result)
        self.assertEqual(result.stdout, "", result)
        self.assertIn("::error::", result.stderr)

    def test_published_version_is_not_required_to_be_latest(self):
        result = self.run_check(body=self.metadata("0.1.0", "0.2.0"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "true\n")

    def test_existing_package_with_absent_version(self):
        result = self.run_check(body=self.metadata("0.0.1", "0.2.0"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "false\n")

    def test_missing_package_404_follows_normal_publish_path(self):
        result = self.run_check(status="404", body='{"error":{"code":"NotFound"}}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "false\n")

    def test_exact_prerelease_and_build_versions(self):
        for version in ("0.1.0-dev.1", "0.1.0+1"):
            with self.subTest(version=version):
                result = self.run_check(body=self.metadata(version), version=version)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "true\n")
                result = self.run_check(body=self.metadata(version))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "false\n")

    def test_network_failures_fail_closed(self):
        for curl_exit in (6, 28, 60):
            with self.subTest(curl_exit=curl_exit):
                self.assert_failure(curl_exit=curl_exit)

    def test_server_and_other_http_errors_fail_closed(self):
        for status in ("500", "503", "429", "403", "301", "000"):
            with self.subTest(status=status):
                self.assert_failure(status=status)

    def test_malformed_json_fails_closed(self):
        for body in ("", "not JSON", "{", "null", "[]"):
            with self.subTest(body=body):
                self.assert_failure(body=body)

    def test_multiple_json_documents_fail_closed(self):
        self.assert_failure(body=self.metadata("0.1.0") + "\n" + self.metadata("0.1.0"))

    def test_wrong_package_fails_closed(self):
        self.assert_failure(body=self.metadata("0.1.0", name="another_package"))

    def test_invalid_versions_schema_fails_closed(self):
        for versions in (None, "0.1.0", {}, [None], ["0.1.0"], [{}], [{"version": 1}]):
            with self.subTest(versions=versions):
                self.assert_failure(
                    body=json.dumps({"name": "advanced_webview", "versions": versions})
                )
        self.assert_failure(body='{"name":"advanced_webview"}')


if __name__ == "__main__":
    unittest.main()
