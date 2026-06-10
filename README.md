# NetworkRepairKit 🐿️

> Internet borked? The squirrel fixes it one careful step at a time — and stops the moment it's back.

The Friday "my internet's dead" fix in one command — without the blind `netsh`-everything shotgun. It diagnoses first, then climbs an escalation ladder from gentlest to bluntest, re-testing after every step and quitting while it's ahead. Pure PowerShell, no install, no dependencies, one file.

```
  🐿️  SquirrelScripts — Network Repair Kit
  -------------------------------------

  Checking what's actually broken...
  Gateway    (192.168.1.1)        OK
  Internet   (1.1.1.1)            OK
  DNS        (example.com)        FAIL
  Web        (port 443)           FAIL

  Verdict: you're online but DNS is down — names won't resolve

  Receipts (state before repairs): C:\Users\JohnDoe\AppData\Local\Temp\SquirrelNet-receipts-20260609-164210.txt

  [1/4]  Flush DNS cache... done
           re-testing...

  -------------------------------------
  Gateway    (192.168.1.1)        OK
  Internet   (1.1.1.1)            OK
  DNS        (example.com)        OK
  Web        (port 443)           OK

  Fixed after: Flush DNS cache  🐿️
  Stopped there — no need to keep poking a working network.
```

## Run it

Downloaded `.ps1` files come into Windows **blocked** (Mark-of-the-Web), so unblock it first, then run. From the folder you saved it in, in an **elevated** PowerShell:

```powershell
# 1. unblock the downloaded file
Unblock-File .\Repair-SquirrelNet.ps1

# 2. dry run first — diagnose and show the plan, fix nothing
powershell -ExecutionPolicy Bypass -File .\Repair-SquirrelNet.ps1 -WhatIf

# 3. for real
powershell -ExecutionPolicy Bypass -File .\Repair-SquirrelNet.ps1
```

Always do the `-WhatIf` pass first. The diagnosis runs either way (it's read-only); `-WhatIf` then lists exactly which repair steps would fire.

If your network is actually fine, it tells you so and exits — it will not "repair" a working connection.

## The ladder

Gentlest first. After **every** step it re-tests, and the moment the checks pass it stops.

| # | Step | Needs admin? | Notes |
|---|------|:---:|-------|
| 1 | Flush DNS cache | – | |
| 2 | Re-register DNS | yes | |
| 3 | Renew DHCP lease | yes | renew without release — doesn't drop the lease first |
| 4 | Restart network adapter | yes | warns first — Wi-Fi/VPN blip for a few seconds |
| 5 | Reset Winsock | yes + `-Deep` | warns first — can break VPN clients; needs a reboot |
| 6 | Reset TCP/IP stack | yes + `-Deep` | warns first — back to defaults; needs a reboot |

Steps 5–6 are the blunt instruments every other repair script leads with. Here they're opt-in (`-Deep`), they explain the risk before running, and they only happen after the gentle rungs failed.

## Switches

| Switch | What it does |
|--------|--------------|
| `-WhatIf` | Diagnose and show the plan — fixes nothing |
| `-Confirm` | Prompt before each step |
| `-Deep` | Add the Winsock and TCP/IP stack resets to the ladder |
| `-Force` | Skip the are-you-sure prompts on the disruptive steps |

Without admin, the script runs what it can (DNS flush), skips the rest, and tells you to re-run elevated — it doesn't fail.

## Is it safe?

Reasonable thing to ask before letting a stranger's script touch your network stack:

- **It diagnoses before it touches anything.** Four read-only checks (gateway, raw internet, DNS, web). If they pass, it exits.
- **It stops the moment you're back online.** No step runs after the one that fixed it.
- **Receipts before repairs.** Your full network state — `ipconfig /all`, the IPv4 route table, the Winsock catalog — is saved to a timestamped file *before* the first repair step, so there's always a record of the working-ish config.
- **The scary steps announce themselves.** Winsock and TCP/IP resets can break VPN clients and security agents that hook the stack — so they're behind `-Deep`, they warn you specifically, and they wait for a yes.
- Read the code — it's ~280 lines and not minified.

## Requirements

Windows, PowerShell 5.1 or newer (works on PowerShell 7 too). Elevated session for everything past the DNS flush.

## Pairs with

The rest of the stash: [**SquirrelCleaner**](https://github.com/SquirrelScripts/SquirrelCleaner) · [**DiskHogFinder**](https://github.com/SquirrelScripts/DiskHogFinder)

---

Part of **[SquirrelScripts](https://squirrelscripts.github.io)** — a stash of small, sharp tools for sysadmins.

If it saved you a headache: ☕ **[Buy me a coffee](https://buymeacoffee.com/eblank)**

<sub>Built in a tree.</sub>
