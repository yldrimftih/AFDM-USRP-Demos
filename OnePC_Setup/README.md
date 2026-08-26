# One-PC setup — PS-OFDM vs PS-AFDM live demo

**V1, 26 August 2026 — Dr. Hyeon Seok Rou and Chloe (Claude Code)**

Transmitter and receiver run in **one MATLAB session**, with **two Ettus B210**
radios attached to this PC. Full documentation is in the [repository
README](../README.md).

## Run it

1. `SELFTEST` — no radio needed; must print `[SELFTEST] === PASS ===`.
   (Linux, once per PC: `sudo ./SETUP_UDEV.sh`, then re-plug the radios.)
2. `findsdru` — note the serial number of each B210.
3. Put the serials into `P.txSerial` / `P.rxSerial` at the top of the script
   you want, and press **Run**:
   * `RUN_IMAGE_DEMO.m` — sends `dog.jpg` quadrant by quadrant over both
     waveforms and shows both received pictures side by side.
   * `RUN_PANEL_DEMO.m` — random payload, full diagnostics panel, live
     4/16/64-QAM switching.
4. **Close the window to stop.**

## Change these if you want

`P.imgFile` (any image file in this folder), `P.fc` (carrier, default 2.4 GHz),
`P.txGain` / `P.rxGain` (also live sliders), and for the panel demo `P.modOrder`
and `P.N` / `P.profile`.

The gain defaults are the authors' desk-rig operating points. On your own link,
raise `txGain` slowly and keep the panel's clip canary **`peak|y| < 0.7`**.

## Safety

Antenna link only, antennas **≥ 30 cm apart**, `txGain <= 80`. A cable loopback
needs a **30 dB attenuator** and `txGain <= 55`, otherwise the receiver front
end is damaged.
