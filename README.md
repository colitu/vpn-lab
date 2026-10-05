# Colitu VPN Lab

**Reproducible VPN protocol tests on deliberately broken networks.**

This is the test lab behind the *Can It Survive?* series on the Colitu YouTube channel. We take two Linux servers, put four VPN protocols between them, make the network worse on purpose — packet loss, latency, a speed cap — and measure what still works.

Every number we show in a video comes from these scripts. You can read them, question them, and run them yourself.

[Русский](README.ru.md) · [Türkçe](README.tr.md)

---

## What gets tested

| Protocol | Transport | How it carries your traffic |
|---|---|---|
| **WireGuard** | UDP | IP tunnel — your own TCP connections travel inside it end-to-end |
| **OpenVPN** (UDP mode) | UDP | IP tunnel, same idea as WireGuard |
| **VLESS + Reality** | TCP | Proxy — TCP is terminated at the VPN server and re-sent over one TLS-looking TCP connection |
| **Hysteria2** | UDP (QUIC) | Proxy over QUIC with its own congestion control |
| *No VPN* | — | Reference line: the same request without any tunnel |

All protocols run with standard, documented settings — no protocol gets special tuning. Hysteria2 runs without bandwidth hints, which is its default (it then uses BBR).

## How the lab works

```
          client server                                      lab server
  ┌──────────────────────────┐                    ┌──────────────────────────────┐
  │ curl ──► WireGuard ──────┼──┐              ┌──┼──► WireGuard  ─┐             │
  │ curl ──► OpenVPN ────────┼──┤   internet   ├──┼──► OpenVPN    ─┤             │
  │ curl ──► sing-box SOCKS ─┼──┤ ◄──────────► ├──┼──► sing-box   ─┼─► test site │
  │          (Hysteria2,     │  │              │  │    (Hy2, VLESS)│   :24080    │
  │           VLESS Reality) │  │              │  │                │             │
  │ curl ──► direct ─────────┼──┘              └──┼────────────────┘             │
  │                          │                    └──────────────────────────────┘
  │ netem: loss / delay /    │
  │ rate — ONLY on packets   │
  │ to/from the lab server   │
  └──────────────────────────┘
```

- **The bad network** is made with Linux `tc netem` on the client. It applies the same loss, delay and speed limit **in both directions**, and only to packets exchanged with the lab server — SSH and every other connection on the machine stay untouched.
- **Default conditions:** +20 ms delay each way, 100 Mbit/s cap, random packet loss of 0 %, 1 %, 5 % and 10 % (per direction — 5 % each way is about 10 % round-trip).
- **The test website** is a tiny HTTP server on the lab server. Its TCP congestion control can be switched (see *Fairness*).

## What gets measured

For every loss level, every protocol, **three runs in a shuffled order**:

1. **Download speed** — one 64 MB file, capped at 20 seconds, average Mbit/s.
2. **Page loads** — twenty 100 KB requests, each with a 10-second timeout. We record every load time and count the ones that failed. This is closer to what browsing feels like than a speed test.

`analyze.py` turns the raw results into a table: median / min / max speed, median and 95th-percentile page time, failures, and how much of its own clean-network speed each protocol kept.

## Run it yourself

You need two Linux servers (Ubuntu 24.04+, root, ~1 GB RAM is enough), ideally in different cities.

```bash
# 1) on the LAB SERVER — pass the client's public IP
git clone https://github.com/colitu/vpn-lab && cd colitu-vpn-lab
sudo bash lab-server.sh <client_ip>                 # or: sudo LAB_CC=cubic bash lab-server.sh <client_ip>

# 2) copy /opt/colitu-lab/out/client-bundle.tgz from the server into the repo folder on the CLIENT, then:
sudo bash lab-client.sh                              # sets up the tunnels and prints a connectivity check

# 3) on the CLIENT — run the tests (takes ~1 hour for the full set)
sudo bash /opt/colitu-lab/lab-run.sh mytest "0 1 5 10" 3
python3 analyze.py /opt/colitu-lab/results/mytest.jsonl summary.json

# 4) clean up both machines
sudo bash lab-teardown.sh client
sudo bash lab-teardown.sh server <client_ip>
```

You can also play with the network by hand: `sudo bash /opt/colitu-lab/lab-netem.sh set 5 50 20` (5 % loss, 50 ms each way, 20 Mbit/s) and `... clear`.

## Fairness and limits — read this before quoting numbers

- **Congestion control matters a lot.** Inside WireGuard and OpenVPN, your TCP connection is controlled by the *website's* server. With BBR (used by many large sites and tuned servers) TCP shrugs off random loss; with CUBIC (the Linux default) it slows down sharply. VLESS uses the VPN server's TCP stack, Hysteria2 uses its own QUIC congestion control. In episode #1 the test website used BBR (the host default) — the most forgiving case for TCP inside a tunnel. With CUBIC the tunnel numbers can be lower; run `LAB_CC=cubic` to see it on your own setup.
- **Loss is random and independent.** Real Wi-Fi and mobile loss often comes in bursts; that can change the ranking.
- **One route, one pair of servers.** Different distances, CPUs or providers will give different absolute numbers. Compare protocols *within* a run, not against numbers from another setup.
- **This is not a blocking/censorship test.** Here every protocol is allowed through. How protocols behave when UDP is blocked or traffic is inspected is a separate episode.
- **Speed is capped at 100 Mbit/s** on purpose, so the test measures behaviour, not server CPU.

## Safety

- All services listen on 24xxx ports and live in `/opt/colitu-lab`; `lab-teardown.sh` removes them, their systemd units and the firewall rules.
- Lab ports are opened only to the client's IP (when `ufw` is active).
- Keys and certificates are generated per lab and expire after 30 days. Nothing secret is stored in this repository.

## Files

| File | Runs on | Purpose |
|---|---|---|
| `lab-server.sh` | server | Installs WireGuard, OpenVPN, sing-box (Hysteria2 + VLESS Reality) and the test site |
| `lab-client.sh` | client | Installs the matching clients and checks every path |
| `lab-netem.sh` | client | Turns the bad network on and off |
| `lab-run.sh` | client | The measurement loop, writes JSON lines |
| `lab-www.py` | server | The test website (with switchable congestion control) |
| `analyze.py` | anywhere | Summary table + JSON |
| `lab-teardown.sh` | both | Removes everything |
| `results/` | — | Raw data from the episodes |

## Results

### Can It Survive? #1 — packet loss

Two servers (Germany ↔ Netherlands, ~36 ms apart), +20 ms each way, 100 Mbit/s cap, random loss in **both** directions. Test website on BBR (host default). Median of 3 runs; page load = median of 60 requests of 100 KB. Raw data: [`results/ep01-packet-loss.jsonl`](results/ep01-packet-loss.jsonl).

**Download speed (Mbit/s) — and how much of its own clean-network speed each kept**

| Loss (each way) | No VPN | WireGuard | OpenVPN | VLESS Reality | Hysteria2 |
|---|---|---|---|---|---|
| 0 % | 86.4 | 75.7 | 75.3 | 85.1 | 80.6 |
| 1 % | 83.8 (97 %) | 36.3 (48 %) | 20.8 (28 %) | 82.9 (97 %) | 77.7 (96 %) |
| 5 % | 75.8 (88 %) | 11.2 (15 %) | 9.3 (12 %) | 76.4 (90 %) | 73.6 (91 %) |
| 10 % | 66.3 (77 %) | 2.9 (4 %) | 2.9 (4 %) | 66.8 (78 %) | 37.9 (47 %) |

**Page load, 100 KB (median seconds)**

| Loss (each way) | No VPN | WireGuard | OpenVPN | VLESS Reality | Hysteria2 |
|---|---|---|---|---|---|
| 0 % | 0.39 | 0.53 | 0.56 | 0.48 | 0.08 |
| 1 % | 0.40 | 0.59 | 0.61 | 0.51 | 0.15 |
| 5 % | 0.52 | 0.65 | 0.72 | 0.67 | 0.16 |
| 10 % | 0.60 | 0.90 | 1.08 | 0.80 | 0.23 |

Notes:

- Hysteria2's page loads are fast mostly because QUIC keeps one connection open and opens a new stream per request, while the other paths start a fresh TCP connection (and, for VLESS, a fresh Reality handshake) for every request.
- Failures: one OpenVPN download at 1 % and one VLESS Reality download at 5 % failed to start (counted as 0 Mbit/s; the medians are unaffected). A handful of page requests failed at 1 % and 10 % (see the raw data).
- Why the tunnels fall so far: WireGuard and OpenVPN don't recover lost packets — the TCP connection inside the tunnel has to. Sampling that connection on the server (`ss -tin`) at 5 % loss showed BBR estimating 14–55 Mbit/s inside the tunnels versus ~96 Mbit/s on the direct path, and 165–179 reordering events inside the tunnels (none on the direct path).

## About Colitu

[Colitu](https://colitu.com) is an open-source VPN for Windows, Android and Linux. Its apps switch between protocols automatically when a network gets bad — which is exactly why we care how each protocol survives.

## License

MIT — see [LICENSE](LICENSE).
