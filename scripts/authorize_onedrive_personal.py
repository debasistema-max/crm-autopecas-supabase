#!/usr/bin/env python3
"""Authorize the dedicated OneDrive workbook and its automatic backup folder.

The refresh token is kept in memory and sent to `gh secret set` through stdin.
It is never printed or written to disk.
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request


AUTHORITY = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
SCOPES = "offline_access https://graph.microsoft.com/Files.ReadWrite"
GRAPH_AUDIENCES = {"00000003-0000-0000-c000-000000000000", "https://graph.microsoft.com"}


def post_form(url: str, data: dict[str, str]) -> dict:
    encoded = urllib.parse.urlencode(data).encode("ascii")
    request = urllib.request.Request(
        url, data=encoded, headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        body = json.loads(error.read() or b"{}")
        body["_status"] = error.code
        return body


def authorize(client_id: str) -> tuple[str, str]:
    device = post_form(f"{AUTHORITY}/devicecode", {"client_id": client_id, "scope": SCOPES})
    if not device.get("device_code"):
        raise RuntimeError(f"DISPOSITIVO_NAO_AUTORIZADO:{device.get('error', 'UNKNOWN')}")
    print("Abra:", device.get("verification_uri", "https://microsoft.com/devicelogin"), flush=True)
    print("Código:", device.get("user_code", ""), flush=True)
    print(
        "Entre somente com a conta exclusiva da integração e confirme leitura e gravação para os backups.",
        flush=True,
    )

    deadline = time.monotonic() + int(device.get("expires_in", 900))
    interval = max(int(device.get("interval", 5)), 5)
    while time.monotonic() < deadline:
        time.sleep(interval)
        token = post_form(f"{AUTHORITY}/token", {
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "client_id": client_id,
            "device_code": str(device["device_code"]),
        })
        if token.get("access_token") and token.get("refresh_token"):
            return str(token["access_token"]), str(token["refresh_token"])
        error = token.get("error")
        if error == "authorization_pending":
            continue
        if error == "slow_down":
            interval += 5
            continue
        raise RuntimeError(f"AUTORIZACAO_RECUSADA:{error or 'UNKNOWN'}")
    raise RuntimeError("AUTORIZACAO_EXPIRADA")


def validate_access_token(access_token: str) -> None:
    if not access_token.strip():
        raise RuntimeError("ACCESS_TOKEN_INVALIDO")
    # Microsoft personal accounts can return opaque access tokens. In that case
    # there is no payload to inspect locally; the following Graph request is the
    # authoritative audience/scope validation and fails closed if access is wrong.
    if access_token.count(".") != 2:
        return
    try:
        payload_part = access_token.split(".")[1]
        payload = json.loads(base64.urlsafe_b64decode(payload_part + "=" * (-len(payload_part) % 4)))
    except (IndexError, ValueError, json.JSONDecodeError) as error:
        raise RuntimeError("ACCESS_TOKEN_INVALIDO") from error
    audience = str(payload.get("aud") or "")
    scopes = set(str(payload.get("scp") or "").split())
    if audience not in GRAPH_AUDIENCES:
        raise RuntimeError("ACCESS_TOKEN_PUBLICO_INCORRETO")
    if "Files.ReadWrite" not in scopes:
        raise RuntimeError("ACCESS_TOKEN_SEM_FILES_READWRITE")


def graph_error_detail(error: urllib.error.HTTPError) -> str:
    code = "UNKNOWN"
    message = ""
    try:
        body = json.loads(error.read() or b"{}")
        raw_error = body.get("error") or {}
        if isinstance(raw_error, dict):
            code = str(raw_error.get("code") or code)
            message = str(raw_error.get("message") or "")
        else:
            code = str(raw_error or code)
    except (json.JSONDecodeError, UnicodeDecodeError, AttributeError):
        pass
    message = re.sub(r"[\w.+-]+@[\w.-]+", "<email>", message)
    message = re.sub(r"\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b", "<id>", message)
    message = " ".join(message.split())[:240]
    return f"HTTP_{error.code}_{code}" + (f"_{message}" if message else "")


def normalize_folder_path(folder_path: str) -> str:
    normalized = folder_path.strip().strip("/")
    parts = normalized.split("/")
    if not normalized or "\\" in normalized or any(part in {"", ".", ".."} for part in parts):
        raise RuntimeError("PASTA_ONEDRIVE_INVALIDA")
    return "/".join(parts)


def get_sync_folder(access_token: str, folder_path: str) -> dict:
    headers = {"Authorization": f"Bearer {access_token}"}
    encoded_path = urllib.parse.quote(normalize_folder_path(folder_path), safe="/")
    folder_url = f"{GRAPH_ROOT}/me/drive/root:/{encoded_path}?$select=id,name,folder"
    try:
        with urllib.request.urlopen(
            urllib.request.Request(folder_url, headers=headers), timeout=60
        ) as response:
            folder = json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"PASTA_ONEDRIVE_INACESSIVEL:{graph_error_detail(error)}") from error
    if folder.get("folder") is None or not folder.get("id"):
        raise RuntimeError("PASTA_ONEDRIVE_NAO_ENCONTRADA")
    return folder


def verify_workbook(
    access_token: str,
    workbook_name: str,
    folder_path: str,
    wait_seconds: int = 0,
) -> None:
    if not workbook_name.lower().endswith(".xlsx"):
        raise RuntimeError("PLANILHA_INVALIDA")
    headers = {"Authorization": f"Bearer {access_token}"}
    folder = get_sync_folder(access_token, folder_path)
    folder_id = urllib.parse.quote(str(folder["id"]), safe="")
    fields = urllib.parse.quote("id,name,size,file", safe=",")
    deadline = time.monotonic() + max(wait_seconds, 0)
    announced = False
    while True:
        try:
            with urllib.request.urlopen(urllib.request.Request(
                f"{GRAPH_ROOT}/me/drive/items/{folder_id}/children?$select={fields}", headers=headers
            ), timeout=60) as response:
                items = json.loads(response.read()).get("value", [])
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"PASTA_ONEDRIVE_INACESSIVEL:HTTP_{error.code}") from error
        matches = [item for item in items if item.get("name") == workbook_name and item.get("file")]
        if len(matches) == 1 and int(matches[0].get("size") or 0) > 0:
            return
        if time.monotonic() >= deadline:
            raise RuntimeError("PLANILHA_EXCLUSIVA_NAO_ENCONTRADA")
        if not announced:
            print(
                f"Copie {workbook_name} para OneDrive/{normalize_folder_path(folder_path)}. Aguardando...",
                flush=True,
            )
            announced = True
        time.sleep(5)


def store_github_secret(repo: str, refresh_token: str) -> None:
    subprocess.run(
        ["gh", "secret", "set", "MS_GRAPH_REFRESH_TOKEN", "--repo", repo],
        input=refresh_token, text=True, check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--workbook-name", required=True)
    parser.add_argument("--folder-path", required=True)
    args = parser.parse_args()
    access_token, refresh_token = authorize(args.client_id)
    validate_access_token(access_token)
    verify_workbook(
        access_token,
        args.workbook_name,
        args.folder_path,
        wait_seconds=900,
    )
    store_github_secret(args.repo, refresh_token)
    print("Autorização de backup validada; token salvo no GitHub Secrets sem ser exibido.")


if __name__ == "__main__":
    main()
