# RX PC — PS-OFDM vs PS-AFDM live demo

**V1, 26 August 2026 — Dr. Hyeon Seok Rou and Chloe (Claude Code)**

Copy **this folder** to the receiving PC. It needs one Ettus B210. Full
documentation is in the [repository README](../../README.md).

## Run it

1. `SELFTEST` — no radio needed; must print `[SELFTEST] === PASS ===`.
   (Linux, once per PC: `sudo ./SETUP_UDEV.sh`, then re-plug the radio.)
2. `findsdru` — note the serial number.
3. Put it into `P.rxSerial` at the top of `RX_PC_MAIN.m`.
4. Start `TX_PC_MAIN.m` on the transmitting PC **first**, then press **Run**
   here.
5. **Close the window to stop.**

## Rules that matter

* The two PCs never talk to each other. The receiver rebuilds the transmitted
  payload locally from `src/twopc_frame_contract.m`, so **`src/` and `dog.jpg`
  must be identical on both PCs**, as must `P.imgFile`. If you change the image
  or anything in `src/`, change it on **both** sides.
* Antenna link only, antennas **≥ 30 cm apart**, `txGain <= 80`. Cable loopback
  needs a **30 dB attenuator** and `txGain <= 55`.
* Keep the clip canary on this panel green: `peak|y|` must stay **below 0.7**.
  If it turns red, lower `rxGain` (slider) or ask for less `txGain` on the
  other PC. A clipped ADC invalidates every number shown.
