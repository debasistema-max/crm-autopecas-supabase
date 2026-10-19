#!/usr/bin/env python3
"""Create and commit an audited, field-only ANO rollback batch."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

from sync_onedrive_personal import CHUNK_ROWS, SyncError, edge_call, required_env


def resume_batch(edge_url: str, secret: str, batch_id: str, expected_rows: int) -> dict:
    prepared = edge_call(edge_url, secret, {
        "source": "EXCEL_API", "operation": "prepare", "batch_id": batch_id,
    })
    batch = prepared.get("batch") or {}
    state = str(batch.get("state") or "").upper()
    if state == "COMMITTED":
        return batch

    max_calls = max(10, (expected_rows + CHUNK_ROWS - 1) // CHUNK_ROWS + 10)
    for _ in range(max_calls):
        status = edge_call(edge_url, secret, {
            "source": "EXCEL_API", "operation": "status", "batch_id": batch_id,
        }).get("batch") or {}
        state = str(status.get("state") or "").upper()
        if state in {"PREVIEWED", "COMMITTING", "COMMITTED"}:
            break
        if state != "DRAFT":
            raise SyncError(f"ESTADO_REVERSAO_INESPERADO:{state or 'AUSENTE'}")
        validated = edge_call(edge_url, secret, {
            "source": "EXCEL_API", "operation": "validate", "batch_id": batch_id,
        })
        if validated.get("done"):
            state = str((validated.get("batch") or {}).get("state") or "").upper()
            break
    else:
        raise SyncError("VALIDACAO_REVERSAO_NAO_CONCLUIDA")

    if state == "COMMITTED":
        return status
    if state not in {"PREVIEWED", "COMMITTING"}:
        raise SyncError(f"REVERSAO_SEM_LINHAS_VALIDAS:{state or 'AUSENTE'}")

    for _ in range(max_calls):
        committed = edge_call(edge_url, secret, {
            "source": "EXCEL_API", "operation": "commit", "batch_id": batch_id,
        })
        if committed.get("done"):
            result = committed.get("batch") or {}
            if str(result.get("state") or "").upper() != "COMMITTED":
                raise SyncError("REVERSAO_RETORNOU_ESTADO_INVALIDO")
            return result
    raise SyncError("COMMIT_REVERSAO_NAO_CONCLUIDO")


def rollback_years(target_batch_id: str) -> dict:
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", target_batch_id):
        raise SyncError("LOTE_ORIGINAL_INVALIDO")
    edge_url = required_env("DATA_SYNC_EDGE_URL")
    secret = required_env("DATA_SYNC_SCHEDULER_SECRET")
    plan = edge_call(edge_url, secret, {
        "source": "EXCEL_API",
        "operation": "rollback-years",
        "target_batch_id": target_batch_id,
    })
    rollback_batch_id = str(plan.get("batch_id") or "")
    eligible_rows = int(plan.get("eligible_rows") or 0)
    if not rollback_batch_id or eligible_rows < 1:
        raise SyncError("PLANO_REVERSAO_INVALIDO")
    completed = resume_batch(edge_url, secret, rollback_batch_id, eligible_rows)
    return {"rollback": plan, "result": completed}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-batch", required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(rollback_years(args.target_batch), ensure_ascii=False, separators=(",", ":")))
    except Exception as error:
        message = str(error) if isinstance(error, SyncError) else f"FALHA_REVERSAO:{type(error).__name__}"
        print(json.dumps({"ok": False, "error": message}, ensure_ascii=False, separators=(",", ":")))
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
