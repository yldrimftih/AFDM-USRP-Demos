%% =========================================================================
%  FILE:     frac_shift.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Fractional-sample advance of a signal segment via FFT phase ramp:
%    ys[n] = y[n + d] for non-integer d. Shared by burst_sync/burst_demod
%    (sub-sample timing alignment).
%  INPUTS:
%    y : complex column vector
%    d : scalar fractional advance [samples], |d| <= 1
%  OUTPUTS:
%    ys : complex column, y advanced by d samples
% =========================================================================
function ys = frac_shift(y, d)

y  = y(:);
N  = numel(y);
k  = [0:ceil(N/2)-1, -floor(N/2):-1].';       % FFT bin frequencies
ys = ifft( fft(y) .* exp(1j*2*pi*k*d/N) );

end
