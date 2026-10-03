"""Summarises a lab run: prints a table and writes a JSON summary.

Usage: python analyze.py results/<tag>.jsonl summary.json

Per loss level and target: median / min / max download speed over the runs, median and 95th
percentile page-load time over all page requests, failed page requests, and how much of its own
0% speed the target kept ("keep%").
"""
import json
import statistics as st
import sys
from collections import defaultdict

src, dst = sys.argv[1], sys.argv[2]
rows = [json.loads(l) for l in open(src, encoding='utf8') if l.strip()]

groups = defaultdict(list)
for r in rows:
    groups[(r['loss'], r['target'])].append(r)

def pct(values, p):
    if not values:
        return None
    v = sorted(values)
    i = min(len(v) - 1, max(0, round(p / 100 * (len(v) - 1))))
    return v[i]

losses = sorted({r['loss'] for r in rows})
targets = ['direct', 'wireguard', 'openvpn', 'vless-reality', 'hysteria2']
out = {'meta': {'rateMbit': 100, 'delayMsEachWay': 20, 'runs': max(r['run'] for r in rows), 'losses': losses,
                'pageRequestsPerRun': 20, 'downloadCapSecs': 20, 'pageTimeoutSecs': 10},
       'byLoss': {}}

print(f"{'loss':>4} {'target':<14} {'Mbit/s med':>10} {'min':>7} {'max':>7} {'page med':>9} {'page p95':>9} {'fail':>5} {'keep%':>6}")
for loss in losses:
    out['byLoss'][str(loss)] = {}
    for t in targets:
        g = groups.get((loss, t), [])
        if not g:
            continue
        mbps = [r['mbps'] for r in g]
        pages = [s for r in g for s in r['page_secs']]
        fails = sum(r['page_fail'] for r in g)
        total = len(pages) + fails
        base = out['byLoss'].get('0', {}).get(t, {}).get('mbps')
        d = {
            'mbps': round(st.median(mbps), 1),
            'mbpsMin': round(min(mbps), 1),
            'mbpsMax': round(max(mbps), 1),
            'pageMed': round(st.median(pages), 3) if pages else None,
            'pageP95': round(pct(pages, 95), 3) if pages else None,
            'pageFail': fails,
            'pageTotal': total,
        }
        d['keepPct'] = round(100 * d['mbps'] / base) if base else 100
        out['byLoss'][str(loss)][t] = d
        print(f"{loss:>4} {t:<14} {d['mbps']:>10} {d['mbpsMin']:>7} {d['mbpsMax']:>7} {str(d['pageMed']):>9} {str(d['pageP95']):>9} {fails:>5} {d['keepPct']:>6}")

json.dump(out, open(dst, 'w', encoding='utf8'), indent=2)
print('->', dst)
