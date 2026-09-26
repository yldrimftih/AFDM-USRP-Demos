# RX PC — PS-OFDM vs PS-AFDM live demo (USRP X310)

**V1, 26 August 2026 — Dr. Hyeon Seok Rou and Chloe (Claude Code)**
**X310 port:** Ethernet radio, found with a **Scan** button, no serial or IP to type.

Copy **this folder** to the receiving PC. It needs one Ettus **X310** with a
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
2. Antenna on the **RX2** port of daughterboard slot **A**.
3. Start `TX_PC_MAIN.m` on the transmitting PC **first**.
4. Run `RX_PC_MAIN.m` here and press **Scan** (bottom right of the window). A
   single X310 found is connected automatically. If there are several, pick
   one from the list and press **Connect**.
5. **Close the window to stop.**

If the radio is lost (cable, power), the status line turns red: press Scan
again. Nothing needs to be restarted.

## Settings (USER SETTINGS block at the top of `RX_PC_MAIN.m`)

| Field | Default | Meaning |
|---|---|---|
| `fc` | 2.4e9 | carrier [Hz]; CBX-120 covers 1.2–6 GHz. Must match the TX PC |
| `rxGain` | 20 | RX gain at start [dB]; live slider + type-in box |
| `rxGainMin`, `rxGainMax` | board limits (0 / 31.5) | range of the gain control |
| `daughterboard` | `'CBX-120'` | `'CBX-120'`, `'UBX-160'` or `'SBX-120'` |
| `channel` | 1 | 1 = slot A, 2 = slot B |
| `ipAddress` | `''` | set only to skip the Scan button and connect directly |
| `autoScan` | false | true: scan once as soon as the window opens |
| `imgFile` | `'dog.jpg'` | must be identical on both PCs |

Every field can also be overridden per call, e.g.
`RX_PC_MAIN(struct('rxGain',15))`.

## Rules that matter

* The two PCs never talk to each other. The receiver rebuilds the transmitted
  payload locally from `src/twopc_frame_contract.m`, so **`src/` and `dog.jpg`
  must be identical on both PCs**, as must `P.imgFile` and `P.fc`. If you
  change the image or anything in `src/`, change it on **both** sides.
* Antenna link only, antennas **≥ 1 m apart** and never touching. Cable
  loopback needs a **30 dB attenuator** and a low TX gain.
* Keep the clip canary on this panel green: `peak|y|` must stay **below 0.7**.
  If it turns red, lower `rxGain` or ask for less `txGain` on the other PC. A
  clipped ADC invalidates every number shown. If `peak|y|` is very small
  (< 0.05) and frames are missed, raise the gains.
