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
git clone https://github.com/colitu/colitu-vpn-lab && cd colitu-vpn-lab
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

- **Congestion control matters a lot.** Inside WireGuard and OpenVPN, your TCP connection is controlled by the *website's* server. With BBR (used by many large sites and tuned servers) TCP shrugs off random loss; with CUBIC (the Linux default) it slows down sharply. VLESS uses the VPN server's TCP stack, Hysteria2 uses its own QUIC congestion control. That's why we run the website both ways (`LAB_CC=cubic` and the host default) and publish both.
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

| Episode | Topic | Data |
|---|---|---|
| Can It Survive? #1 | Packet loss (0 / 1 / 5 / 10 %) | measurements in progress — added here before the video goes live |

## About Colitu

[Colitu](https://colitu.com) is an open-source VPN for Windows, Android and Linux. Its apps switch between protocols automatically when a network gets bad — which is exactly why we care how each protocol survives.

## License

MIT — see [LICENSE](LICENSE).
