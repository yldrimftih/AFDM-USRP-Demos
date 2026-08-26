%% =========================================================================
%  FILE:     stf_chips.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Single source of the short-training-field (STF) chip sequence shared by
%    every builder (burst / OFDM / PS-OFDM / PS-AFDM). Keeps the four TX
%    paths from ever diverging, and keeps the sequence definition next to
%    the receiver assumption it must satisfy (exact period stfNzc chips).
%  INPUTS:
%    prm : struct with.stfNzc .stfU .stfNrep (and .useSTF honored by the
%          callers, not here)
%  OUTPUTS:
%    c    : complex column, stfNzc*stfNrep chips ([] if Nrep = 0)
%    nChip: numel(c)
% =========================================================================
function [c, nChip] = stf_chips(prm)

N = prm.stfNzc;
u = prm.stfU;
assert(gcd(u, N) == 1, 'stf_chips: stfU=%d must be coprime to stfNzc=%d', u, N);
assert(mod(u*N, 2) == 0, ...
    'stf_chips: u*N must be even so the chunk repeats exactly (u=%d, N=%d)', u, N);

n = (0:N-1).';
z = exp(-1j*pi*u*n.^2/N);          % even-length Zadoff-Chu
c = repmat(z, prm.stfNrep, 1);
nChip = numel(c);

end
