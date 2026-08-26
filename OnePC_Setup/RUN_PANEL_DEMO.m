%% =========================================================================
%  FILE:     RUN_PANEL_DEMO.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    ONE-PC ENTRY POINT (diagnostics panel). Same link as the image demo,
%    but with a fresh random payload every iteration and the full receive
%    panel: synchronisation, spectra, constellations, per-symbol EVM,
%    channel views (|H(k)| and delay-Doppler grid), EVM / CFO histories
%    and running BER for both waveforms. Constellation order (4/16/64-QAM)
%    and both gains are tunable live. CLOSE THE WINDOW TO STOP.
%
%    >>> SET THE TWO SERIAL NUMBERS BELOW (findsdru) <<<
%
%  SAFETY:
%    Antenna link only, antennas >= 30 cm apart and never touching.
%    Cable loopback requires a 30 dB attenuator and txGain <= 55.
%
%  DEPENDENCIES:  src/tworadio_panel_live.m and its chain
% =========================================================================

%% ========================== PARAMETERS =================================
P = struct();
P.txSerial = 'YOUR_TX_B210_SERIAL';   % <-- transmitting B210 (findsdru)
P.rxSerial = 'YOUR_RX_B210_SERIAL';   % <-- receiving B210
P.N        = 256;                     % 64 (faster) or 256 (standing config)
P.profile  = 'matched';               % 'matched' (N = 256) | 'native'
P.modOrder = 16;                      % start value; popup 4 / 16 / 64
P.fc       = 2.4e9;                   % carrier [Hz] (2.4 GHz ISM)
P.txGain   = 70;                      % start value; slider 40..80
P.rxGain   = 56;                      % start value; slider 20..76

%% ============================ RUN ======================================
addpath(fullfile(fileparts(mfilename('fullpath')), 'src'));
out = tworadio_panel_live(P);
