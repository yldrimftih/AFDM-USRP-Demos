%% =========================================================================
%  FILE:     afdm_demod.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    AFDM demodulator: cyclic-prefix removal plus discrete affine
%    Fourier transform, multi-symbol grid form.
%  INPUTS:
%    y   : complex column, >= (N+Ncp)*Nsym chips (tail ignored)
%    prm : struct (.Nfft.Ncp .Nsym .c1 .c2)
%  OUTPUTS:
%    Y   : complex N x Nsym DAFT-domain grid
% =========================================================================
function Y = afdm_demod(y, prm)

N  = prm.Nfft;
Ls = N + prm.Ncp;
y  = y(1 : Ls*prm.Nsym);
yb = reshape(y, Ls, prm.Nsym);
r  = yb(prm.Ncp+1:end, :);

n = (0:N-1).';
lam1 = exp(-2j*pi*prm.c1*(n.^2));
lam2 = exp(-2j*pi*prm.c2*(n.^2));

v = lam1 .* r;
u = fft(v, N, 1) / sqrt(N);
Y = lam2 .* u;

end
