%% =========================================================================
%  FILE:     rx_chansel.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    RX-SIDE ONLY. Channel-select low-pass on the IF-removed capture.
%    Passes the occupied band (+-135 kHz) plus a CFO margin of +-30 kHz
%    flat, and removes what lies outside -- above all the LO-leakage tones
%    of both radios, which sit 240 kHz below the band after IF removal.
%    Without it those tones (27 dB above the noise on the X310 link,
%    hardware 2026-09-26) dominate the silent parts of the capture: the
%    S&C metric reads ~1 there and biases the coarse CFO, and the
%    pre-burst noise estimate is inflated by the tone power, which
%    over-regularizes both MMSE equalizers.
%
%    Linear phase, group delay removed, unit DC gain: the burst itself is
%    passed unchanged. White noise comes out with variance scaled by
%    nbw = sum(h.^2); the receivers divide their pre-burst noise estimate
%    by prm.noiseBW = nbw to recover the white-noise level they model.
%
%  INPUTS:
%    y   : complex column, capture after IF removal
%    fs  : sample rate [Hz]
%  OUTPUTS:
%    yf  : filtered capture, same length and timing as y
%    nbw : noise-variance gain of the filter (sum of squared taps)
%
%  DEPENDENCIES:
%    fir1, kaiser (Signal Processing Toolbox)
% =========================================================================
function [yf, nbw] = rx_chansel(y, fs)

persistent h fsH
if isempty(h) || fsH ~= fs
    % 120 taps, Kaiser beta 8 (~80 dB stop): flat to ~175 kHz, stop from
    % ~215 kHz at fs = 1 MS/s
    h = fir1(120, 195e3/(fs/2), kaiser(121, 8)).';
    fsH = fs;
end
D   = (numel(h) - 1) / 2;
yf  = filter(h, 1, [y(:); zeros(D, 1)]);
yf  = yf(D+1:end);
nbw = sum(h.^2);

end
