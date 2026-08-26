%% =========================================================================
%  FILE:     afdm_mod.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    AFDM modulator: inverse discrete affine Fourier transform plus
%    cyclic prefix, multi-symbol grid form.
%  INPUTS:
%    X   : complex N x Nsym DAFT-domain grid
%    prm : struct (.Nfft.Ncp .c1 .c2)
%  OUTPUTS:
%    x   : complex column, (N+Ncp)*Nsym serialized chips
% =========================================================================
function x = afdm_mod(X, prm)

N = prm.Nfft;
n = (0:N-1).';
lam1 = exp(-2j*pi*prm.c1*(n.^2));
lam2 = exp(-2j*pi*prm.c2*(n.^2));

v  = conj(lam2) .* X;
u  = sqrt(N) * ifft(v, N, 1);
s  = conj(lam1) .* u;

xc = [s(end-prm.Ncp+1:end, :); s];
x  = xc(:);

end
