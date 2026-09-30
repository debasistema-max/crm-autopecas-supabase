import importlib.util
import base64
import json
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "authorize_onedrive_personal.py"
SPEC = importlib.util.spec_from_file_location("authorize_onedrive_personal", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AuthorizeOneDrivePersonalTest(unittest.TestCase):
    @staticmethod
    def _jwt(payload):
        encoded = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
        return f"header.{encoded}.signature"

    def test_opaque_personal_account_token_is_validated_by_graph(self):
        MODULE.validate_access_token("opaque-personal-account-token")

    def test_jwt_requires_graph_audience_and_files_readwrite_scope(self):
        MODULE.validate_access_token(self._jwt({
            "aud": "https://graph.microsoft.com",
            "scp": "Files.ReadWrite",
        }))
        with self.assertRaisesRegex(RuntimeError, "ACCESS_TOKEN_PUBLICO_INCORRETO"):
            MODULE.validate_access_token(self._jwt({
                "aud": "another-api",
                "scp": "Files.ReadWrite",
            }))

    def test_refresh_token_is_sent_through_stdin(self):
        with patch.object(MODULE.subprocess, "run") as run:
            MODULE.store_github_secret("owner/private", "secret-refresh-token")
        args, kwargs = run.call_args
        self.assertNotIn("secret-refresh-token", args[0])
        self.assertEqual(kwargs["input"], "secret-refresh-token")
        self.assertTrue(kwargs["check"])

    def test_scope_supports_version_backups(self):
        self.assertEqual(
            MODULE.SCOPES,
            "offline_access https://graph.microsoft.com/Files.ReadWrite",
        )

    def test_workbook_is_verified_before_secret_can_be_stored(self):
        root_response = MagicMock()
        root_response.__enter__.return_value.read.return_value = __import__("json").dumps(
            {"id": "folder-id", "name": "IPS CRM Excel Sync", "folder": {}}
        ).encode()
        file_response = MagicMock()
        file_response.__enter__.return_value.read.return_value = __import__("json").dumps({
            "value": [{"id": "item", "name": "master.xlsx", "size": 10, "file": {"mimeType": "xlsx"}}]
        }).encode()
        with patch.object(MODULE.urllib.request, "urlopen", side_effect=[root_response, file_response]) as urlopen:
            MODULE.verify_workbook("access", "master.xlsx", "IPS CRM Excel Sync")
        self.assertIn(
            "/me/drive/root:/IPS%20CRM%20Excel%20Sync",
            urlopen.call_args_list[0].args[0].full_url,
        )

    def test_folder_path_rejects_traversal(self):
        with self.assertRaisesRegex(RuntimeError, "PASTA_ONEDRIVE_INVALIDA"):
            MODULE.normalize_folder_path("../segredos")


if __name__ == "__main__":
    unittest.main()
