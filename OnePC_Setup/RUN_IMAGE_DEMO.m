%% =========================================================================
%  FILE:     RUN_IMAGE_DEMO.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    ONE-PC ENTRY POINT (image demo). Runs transmitter and receiver from a
%    single MATLAB session with two B210s attached to this PC, sending the
%    image quadrant by quadrant over comb-pilot PS-OFDM and embedded-pilot
%    PS-AFDM in turn. Open in MATLAB and press Run.
%    CLOSE THE WINDOW TO STOP.
%
%    >>> SET THE TWO SERIAL NUMBERS BELOW (findsdru) <<<
%
%  SAFETY:
%    Antenna link only, antennas >= 30 cm apart and never touching.
%    Cable loopback requires a 30 dB attenuator and txGain <= 55.
%
%  DEPENDENCIES:  src/tworadio_image_live.m and its chain
% =========================================================================

%% ========================== PARAMETERS =================================
P = struct();
P.txSerial = 'YOUR_TX_B210_SERIAL';   % <-- transmitting B210 (findsdru)
P.rxSerial = 'YOUR_RX_B210_SERIAL';   % <-- receiving B210
P.imgFile  = 'dog.jpg';               % image to transmit (this folder)
P.fc       = 2.4e9;                   % carrier [Hz] (2.4 GHz ISM)
P.txGain   = 58;                      % start value; slider 40..80
P.rxGain   = 56;                      % start value; slider 20..76

%% ============================ RUN ======================================
addpath(fullfile(fileparts(mfilename('fullpath')), 'src'));
out = tworadio_image_live(P);
