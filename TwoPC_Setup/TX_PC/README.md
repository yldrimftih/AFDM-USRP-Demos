# TX PC — PS-OFDM vs PS-AFDM live demo

**V1, 26 August 2026 — Dr. Hyeon Seok Rou and Chloe (Claude Code)**

Copy **this folder** to the transmitting PC. It needs one Ettus B210. Full
documentation is in the [repository README](../../README.md).

## Run it

1. `SELFTEST` — no radio needed; must print `[SELFTEST] === PASS ===`.
   (Linux, once per PC: `sudo ./SETUP_UDEV.sh`, then re-plug the radio.)
2. `findsdru` — note the serial number.
3. Put it into `P.txSerial` at the top of `TX_PC_MAIN.m` and press **Run**.
4. Then start `RX_PC_MAIN.m` on the receiving PC.
5. **Close the window to stop.**

## Rules that matter

* The two PCs never talk to each other. The receiver rebuilds the transmitted
  payload locally from `src/twopc_frame_contract.m`, so **`src/` and `dog.jpg`
  must be identical on both PCs**, as must `P.imgFile`. If you change the image
  or anything in `src/`, change it on **both** sides.
* Antenna link only, antennas **≥ 30 cm apart**, `txGain <= 80`. Cable loopback
  needs a **30 dB attenuator** and `txGain <= 55`.
* Raise `txGain` slowly and watch the clip canary on the *receiving* PC's
  panel: `peak|y|` must stay below 0.7.
