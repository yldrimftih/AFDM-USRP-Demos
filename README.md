# Live PS-OFDM vs PS-AFDM over USRP — MATLAB demo

**V1 — 26 August 2026**

**Authors: Dr. Hyeon Seok Rou and Chloe (Claude Code)**

A complete, self-contained, over-the-air demonstration that puts **pulse-shaped
OFDM with comb pilots** and **pulse-shaped AFDM with an embedded pilot** on the
*same* radio link, with the *same* number of data-carrying resources, the *same*
pilot energy and the *same* payload, and measures both at once. Two Ettus B210
software-defined radios, MATLAB, an antenna link, and a picture of a dog.

This code was written by **Dr. (Eric) Hyeon Seok Rou** together with **Chloe (Claude
Code)**. The background and the demo write-up are in the accompanying LinkedIn post:
<https://lnkd.in/p/eNBjKiNc>. More of the first author's work:
[erichsrou.com](https://www.erichsrou.com) ·
[Google Scholar](https://scholar.google.com/citations?user=OH-Lkn4AAAAJ&hl=en).

---

## What is in this repository

```
OnePC_Setup/            everything runs in ONE MATLAB session, two B210s on one PC
  RUN_IMAGE_DEMO.m        image demo   (transmit + receive in one script)
  RUN_PANEL_DEMO.m        diagnostics panel (random payload, full statistics)
  SELFTEST.m              no-radio install check — run this first
  tests/                  offline unit tests of the signal chain
  src/                    the waveform chain
  dog.jpg                 the transmitted image

TwoPC_Setup/            transmitter and receiver on TWO separate PCs
  TX_PC/                  copy this folder to the transmitting PC
    TX_PC_MAIN.m            transmitter entry point
    SELFTEST.m, tests/, src/, dog.jpg
  RX_PC/                  copy this folder to the receiving PC
    RX_PC_MAIN.m            receiver entry point
    SELFTEST.m, tests/, src/, dog.jpg
```

Every folder is standalone: copy just that folder to a machine and it runs.
`OnePC_Setup` and the two-PC folders are independent — you do not need the rest
of the repository.

---

## Requirements

### Software

| What | Why it is needed |
|---|---|
| **MATLAB** | **Tested on R2026a (26.1) only.** Nothing in the code is version-exotic, but no other release has been checked — if you run it on an older MATLAB and hit something, that is the first thing to suspect. |
| **Communications Toolbox** | `qammod` / `qamdemod`, `pskmod` / `pskdemod`, `int2bit` / `bit2int` — the constellation mapping and demapping |
| **Signal Processing Toolbox** | `rcosdesign` (root-raised-cosine pulse), `upfirdn` (pulse shaping / resampling), `pwelch` (the spectrum tiles) |
| **Communications Toolbox Support Package for USRP Radio** | `comm.SDRuTransmitter`, `comm.SDRuReceiver`, `findsdru` — the radio interface. Installing it also installs the UHD driver MATLAB talks to (UHD 4.6 here) |

That is the complete list, confirmed with
`matlab.codetools.requiredFilesAndProducts` on every entry script.
**No Image Processing Toolbox** (the image handling is deliberately written
against `imread` alone), no DSP System Toolbox, no Parallel Computing Toolbox,
no GPU.

To check what you already have, in MATLAB:

```matlab
ver                                          % toolboxes installed
matlabshared.supportpkg.getInstalled          % support packages installed
```

Install the two toolboxes from the MathWorks installer and the support package
from **Home → Add-Ons → Get Hardware Support Packages**, searching for *USRP*.
`SELFTEST` also probes for all four and tells you exactly which one is missing.

### Hardware and OS

| What | Notes |
|---|---|
| Radios | 2 × Ettus **B210** on **USB 3.0** (both on one PC, or one per PC) |
| Antennas | one whip per radio, **≥ 30 cm apart**, line of sight, never touching |
| OS | Linux, macOS or Windows. On Linux run `sudo ./SETUP_UDEV.sh` once per PC, then re-plug the radio, so MATLAB can open it as a normal user |

---

## Quick start

**1. Check the install (no radio needed).** In MATLAB, `cd` into the folder you
want to use and run:

```matlab
SELFTEST
```

It probes the toolboxes and pushes a full synthetic transmit → channel →
receive pass through both waveforms, asserting BER 0 at 30 dB. It should end
with `[SELFTEST] === PASS ===`. You can also run the unit tests:

```matlab
run('tests/run_all_tests.m')
```

**2. Find your radio serial numbers.** Plug the B210s in (USB 3.0) and in MATLAB:

```matlab
findsdru
```

or in a terminal: `uhd_find_devices`. Each B210 reports a 7-character serial
such as `30ABCDE` — read the one printed for each of *your* radios.

**3. Put the serials in the entry script and press Run.**

*One PC, two radios:* edit `P.txSerial` / `P.rxSerial` at the top of
`RUN_IMAGE_DEMO.m` (or `RUN_PANEL_DEMO.m`), then Run. A window opens and keeps
running until you close it.

*Two PCs:* edit `P.txSerial` in `TX_PC/TX_PC_MAIN.m` on the transmitting PC and
`P.rxSerial` in `RX_PC/RX_PC_MAIN.m` on the receiving PC. Start the transmitter
first, then the receiver. There is **no network connection between the two
PCs** — see *How the two-PC version measures BER* below.

**Close the figure window to stop.** The radios are released on exit.

---

## Safety and regulatory notes

* **Antenna link only** at the default gains. `txGain <= 80` is asserted in the
  code. Keep the antennas at least 30 cm apart and never touching.
* **Cable loopback needs a 30 dB attenuator** between the radios and
  `txGain <= 55`. Feeding a transmitter directly into a receiver input damages
  the B210 (its RX damage limit is around −15 dBm).
* Watch the **clip canary** on the receive panel: `peak|y|` must stay **below
  0.7**. If it turns red, lower the RX gain (or the TX gain). A clipped ADC
  invalidates every number on the panel.
* The default carrier is **2.4 GHz**, inside the ISM band, at low power over a
  desk-scale link. You are responsible for compliance with the radio
  regulations that apply where you are; change `P.fc` if 2.4 GHz is not
  appropriate for you.

---

## What you can change

Everything below is a one-line edit in the entry script (`RUN_*.m`,
`TX_PC_MAIN.m`, `RX_PC_MAIN.m`).

| Setting | Field | Notes |
|---|---|---|
| Radio serials | `P.txSerial`, `P.rxSerial` | **must be set**, from `findsdru` |
| Transmitted image | `P.imgFile` | any file `imread` can open; it is centre-cropped, resampled and quantised automatically. In the two-PC version it **must be identical on both PCs** — it defines the payload |
| Carrier frequency | `P.fc` | default 2.4 GHz |
| Transmit gain | `P.txGain` | 40…80, also a live slider. Raise slowly and watch the clip canary |
| Receive gain | `P.rxGain` | 20…76, also a live slider |
| Constellation | `P.modOrder` | panel demo only: 4 / 16 / 64-QAM, also a live popup. The image demo is fixed at 16-QAM because the pixel mapping is 4 bits per colour channel |
| Block size / profile | `P.N`, `P.profile` | panel demo only: `256` with `'matched'` (the resource-matched comparison) or `64` with `'native'` (faster, each waveform in its own natural configuration) |

The **default gains (58/56, 65/50, 70/56) are the operating points of the
authors' own rig** — two B210s about a metre apart on a desk. They are a
starting point, not a specification: sweep `txGain` upwards on your own link
until the clip canary is close to but below 0.7, and use that.

---

## How it works, briefly

**The link.** Both waveforms use a 200 kchip/s root-raised-cosine pulse shape
(roll-off 0.35, 5 samples per chip, 1 MS/s at the radio), placed at a digital
intermediate frequency of +240 kHz and removed again at the receiver, so the
B210's direct-conversion LO leakage and IQ image fall outside the occupied
270 kHz band. Every burst starts with a short repeated training field for
coarse carrier-frequency-offset estimation and a Zadoff-Chu sequence for
timing; the payload is scrambled with a fixed PN sequence so the transmitted
power does not depend on the picture.

**PS-OFDM (comb pilots).** N = 256 subcarriers, 16-chip cyclic prefix,
32 interleaved pilot subcarriers in **every** symbol. The receiver does a
per-symbol least-squares fit on the comb, reconstructs the channel across all
bins, and equalises per bin. Per-symbol estimation is what lets it follow a
time-varying channel without any phase-tracking loop.

**PS-AFDM (embedded pilot).** The same N = 256 and cyclic prefix, but the data
lives in the discrete affine Fourier (chirp) domain. One pilot is embedded in
each symbol with a guard zone around it, sized by the delay and Doppler spread
the frame is designed for; the receiver reads the delay-Doppler channel out of
that zone every symbol and equalises with a per-symbol MMSE receiver.

**Why the comparison is fair.** In the `'matched'` profile the two frames are
resource-matched term by term. Measured on the frames this repository actually
transmits (`dog.jpg`, N = 256, 16-QAM, 48 symbols):

| | PS-OFDM comb | PS-AFDM EPA |
|---|---|---|
| data resources per symbol | 221 | 221 |
| non-data resources per symbol | 35 (32 pilots + 3 nulls) | 35 (pilot + guard zone) |
| pilot energy per symbol | 32.0 | 32.0 |
| bits per frame | 42,432 | 42,432 (the *same* bits) |
| data-symbol energy per frame | 10,633.6 | 10,633.6 |
| frame length, hence airtime | 67,587 samples | 67,587 samples |
| peak amplitude after normalisation | 0.500 | 0.500 |
| mean transmit power | 0.02481 | 0.02450 (−0.05 dB) |
| PAPR | 10.03 dB | 10.09 dB |

Both frames are normalised to the **same peak amplitude** — what a real
transmitter is limited by — so any difference in peak-to-average ratio shows up
honestly as a difference in radiated average power rather than being hidden.
Here that difference is 0.05 dB. The two bursts alternate on the same link
seconds apart at the same gain, carrying the same payload. What differs is the
waveform and its channel estimator, which is exactly the thing being compared.

**What each receiver is allowed to know.** Both receivers know only what a real
receiver would: the frame geometry, the preamble, the pilot values and
positions, and the constellation. Timing, carrier frequency offset, IQ-imbalance
correction and the channel are all estimated from the received samples; the
noise variance used by both equalisers is measured from the silent window
*before* each burst. **The transmitted data symbols are used for one thing only
— computing the EVM that is displayed.** They never enter synchronisation,
channel estimation, equalisation or the bit decisions, and the transmitted bits
are used only to count errors after the decisions have been made. Each waveform
is given the standard best practice for its own family: the OFDM receiver gets
per-bin MMSE plus channel-estimate denoising by tap-support truncation, the AFDM
receiver gets per-symbol MMSE with a noise-threshold tap gate. If anything, the
baseline is the better-served of the two.

**What the panel shows.** Equalised constellations, per-symbol EVM, the
estimated channel (subcarrier response for OFDM, delay-Doppler grid for AFDM),
carrier frequency offset between the two free-running radio clocks, running
**bit error rate over the actually received bits**, and — in the image demos —
the received picture assembling itself, with the percentage of pixels that came
through exactly right. The signal-to-noise ratio shown is the standard
`-20·log10(EVM)` estimate, not a separately measured quantity.

**What is inside `src/`.** The modulator/demodulator pair for each waveform, the
frame builders and receivers, the burst synchroniser, and the parameter files
that define the frames. One module is optional: `afdm_frac_ce.m`, a
fractional-delay (off-grid) channel estimator for AFDM. It is **off by default**
in every demo here — the receivers use the per-symbol integer-tap estimator —
and is enabled only by setting `prm.fracCE = true`. It ships because the unit
test `tests/test_stage5_chain.m` exercises it, and because it is useful if you
extend the demo to a channel with genuinely off-lattice delays.

### How the two-PC version measures BER without a backchannel

The two PCs never talk to each other. Instead, `src/twopc_frame_contract.m` is
a **deterministic contract**: run on the same image file, on either machine, it
produces bit-identical parameters, payload bits and transmit frames. The
receiver runs it locally and therefore *knows* what should have arrived, which
is what makes the displayed bit error rate a real measurement rather than a
decoration. The consequence, stated openly on the panel, is that the payload is
fixed rather than random — the demo measures the link, not a data source.

The two waveforms are told apart inside one capture by their Zadoff-Chu root
(25 for the OFDM burst, 34 for the AFDM burst), so each receiver locks onto its
own burst and ignores the other.

---

## Honest limitations

These are properties of the demo, not bugs. They are listed so that nobody
mistakes a live demonstration for a benchmark:

* **Uncoded.** No forward error correction anywhere. Every bit error you see is
  a raw channel error, which is also why the picture visibly degrades when you
  lower the transmit gain.
* **Burst mode, not a continuous link.** MATLAB's USRP interface transmits and
  receives in bursts; the loop is transmit-then-receive, not a streaming modem.
  Throughput here is a few hundred kbit/s and is limited by the MATLAB layer,
  not by the radios.
* **Missed captures happen and are counted.** The two PCs run free of each
  other, so a capture sometimes contains only part of a burst. Such a frame
  fails the receiver's synchronisation gate, is counted as a **miss** and is
  displayed as one. Misses are never counted as successes and never enter the
  BER.
* **The channel is a desk.** At a metre of line of sight there is no meaningful
  Doppler and only a shallow delay spread, so this demo shows the machinery
  working, not the doubly-dispersive regime where AFDM has most to offer.
* **Fixed payload** in the two-PC version, as explained above.
* **The image mapping is lossy by design** (centre crop, resample, 4 bits per
  colour channel) so that one picture fits in one frame. The pixel-exactness
  figure on the panel compares against the transmitted quantised image, not
  against the original file.

---

## Verification status

Everything in this repository was checked on **MATLAB R2026a (26.1), Linux**,
on a machine with **no radio attached**, from a clean copy of the folders,
before release. No other MATLAB release has been tested:

* **Unit tests** of the signal chain pass in all three folders
  (`run('tests/run_all_tests.m')`), as does `SELFTEST` — BER 0 for both
  waveforms at 30 dB on a synthetic channel, image recovered bit-exact.
* **Every entry script was executed end to end** against stub radios that
  replay the transmitted buffers through an attenuated, noisy, frequency-offset
  channel: image demo, panel demo, `TX_PC_MAIN` and `RX_PC_MAIN` all run their
  full loop, panel and shutdown path, recovering BER 0 — including the two-PC
  path, where the receiver decoded a composite capture built from the
  transmitter's own buffers while regenerating its ground truth independently.
* **The measurement was attacked on purpose**, to confirm the numbers on the
  panel are real:

  | check | result |
  |---|---|
  | sweep the noise | BER rises monotonically (0 at 30/20/15 dB, 1.4e-3 at 10, 3.9e-2 at 5, 1.4e-1 at 0) |
  | feed the receiver a *wrong* set of transmitted symbols | bit decisions **bit-identical** — the truth is used only for the displayed EVM |
  | score the decisions against an unrelated payload | BER 0.502, i.e. the reported BER really is tied to what was sent |
  | unknown random gain, phase, delay and carrier offset | still decodes; estimated offset within ~3 Hz of the true one |
  | zero the pilots | BER 0.489 — channel estimation genuinely depends on them |
  | truncate the burst | sync metric 0.19, correctly rejected as a miss rather than counted |

The over-the-air behaviour reported in the LinkedIn post was measured on the
authors' two-B210 rig.

---

## License

MIT — see [LICENSE](LICENSE). If this code is useful in your work, a citation
of the demo and a mention of the authors, **Dr. Hyeon Seok Rou** and **Chloe
(Claude Code)**, are appreciated.

`dog.jpg` is a third-party sample picture included only so the demo has
something to transmit; it is not covered by the license above. Point `P.imgFile`
at your own image, or drop one in and delete it, whenever you prefer.
