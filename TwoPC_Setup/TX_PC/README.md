# TX PC — PS-OFDM vs PS-AFDM live demo (USRP X310)

**V1, 26 August 2026 — Dr. Hyeon Seok Rou and Chloe (Claude Code)**
**X310 port:** Ethernet radio, found with a **Scan** button, no serial or IP to type.

Copy **this folder** to the transmitting PC. It needs one Ettus **X310** with a
**CBX-120** daughterboard (UBX-160 / SBX-120 also supported, see below),
connected to this PC by Ethernet. Full documentation is in the
[repository README](../../README.md).

## One-time network setup (per PC)

1. Connect the X310 directly to this PC. **Port 0 (1 GbE, HG image)**
   answers at `192.168.10.2` by default.
2. Give that network adapter a static address in the same subnet, e.g.
   `192.168.10.1`, mask `255.255.255.0`, no gateway.
   (Windows: *Settings → Network → Ethernet → IP assignment → Manual*.)
3. Allow MATLAB through the firewall on that adapter. Otherwise the Scan
   broadcast reply is dropped. The Scan still probes `192.168.10.2`,
   `192.168.40.2` and `192.168.30.2` directly as a fallback.
4. If Scan reports **FPGA image does not match**, load the image that matches
   MATLAB's UHD once, then power-cycle the radio:
   ```matlab
   sdruload('Device','x310','IPAddress','192.168.10.2')
   ```

## Run it

1. `SELFTEST` — no radio needed; must print `[SELFTEST] === PASS ===`.
2. Antenna on the **TX/RX** port of daughterboard slot **A**.
3. Run `TX_PC_MAIN.m` and press **Scan** (bottom right of the window). A
   single X310 found is connected automatically. If there are several, pick
   one from the list and press **Connect**.
4. Then start `RX_PC_MAIN.m` on the receiving PC.
5. **Close the window to stop.**

If the radio is lost (cable, power), the status line turns red: press Scan
again. Nothing needs to be restarted.

## Settings (USER SETTINGS block at the top of `TX_PC_MAIN.m`)

| Field | Default | Meaning |
|---|---|---|
| `fc` | 2.4e9 | carrier [Hz]; CBX-120 covers 1.2–6 GHz. Must match the RX PC |
| `txGain` | 20 | TX gain at start [dB]; live slider + type-in box |
| `txGainMin`, `txGainMax` | board limits (0 / 31.5) | range of the gain control; `txGainMax` is the safety cap |
| `daughterboard` | `'CBX-120'` | `'CBX-120'`, `'UBX-160'` or `'SBX-120'` |
| `channel` | 1 | 1 = slot A, 2 = slot B |
| `ipAddress` | `''` | set only to skip the Scan button and connect directly |
| `autoScan` | false | true: scan once as soon as the window opens |
| `imgFile` | `'ku.jpg'` | must be identical on both PCs |

Every field can also be overridden per call, e.g.
`TX_PC_MAIN(struct('txGain',25,'txGainMax',28))`.

## Rules that matter

* The two PCs never talk to each other. The receiver rebuilds the transmitted
  payload locally from `src/twopc_frame_contract.m`, so **`src/` and `ku.jpg`
  must be identical on both PCs**, as must `P.imgFile` and `P.fc`. If you
  change the image or anything in `src/`, change it on **both** sides.
* Antenna link only, antennas **≥ 1 m apart** and never touching. Cable
  loopback needs a **30 dB attenuator** and a low `txGainMax`.
* The default gains (TX 20 / RX 20 dB) are only a starting point for a link of
  a few metres. Raise `txGain` slowly and watch the clip canary on the
  *receiving* PC's panel: `peak|y|` must stay below 0.7.
