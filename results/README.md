# Raw results

One file per run, one JSON object per line: `loss`, `run`, `target`, `mbps`, `dl_bytes`, `dl_secs`, `dl_exit` (curl exit code; 28 = hit the 20 s cap), `page_secs` (successful page loads), `page_fail`, `ts`.

Summarise with `python3 analyze.py results/<file>.jsonl summary.json`.
