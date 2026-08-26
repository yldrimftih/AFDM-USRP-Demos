%% =========================================================================
%  FILE:     test_afdm_modem.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Unit test for afdm_mod/afdm_demod and the Stage-4 structural claims.
%  INPUTS:
%     none
%  OUTPUTS:
%    none (errors on failure)
%  DEPENDENCIES:
%     stage5_params, afdm_mod, afdm_demod
% =========================================================================
function test_afdm_modem

prm = stage5_params(64, 'native');
N   = prm.Nfft;

% (1) round trip exact
X = (randn(N, prm.Nsym) + 1j*randn(N, prm.Nsym))/sqrt(2);
x = afdm_mod(X, prm);
Y = afdm_demod(x, prm);
assert(max(abs(Y(:) - X(:))) < 1e-10, 'round trip error %.3g', max(abs(Y(:)-X(:))));

% (2) Parseval per symbol (CP stripped)
Ls = N + prm.Ncp;
xb = reshape(x, Ls, prm.Nsym);
eT = sum(abs(xb(prm.Ncp+1:end,:)).^2, 1);
eF = sum(abs(X).^2, 1);
assert(max(abs(eT - eF)) < 1e-9, 'Parseval violated by %.3g', max(abs(eT-eF)));

% (3) CPP == CP: phase factor exp(-j2pi*c1*(N^2 - 2Nn)) must equal 1
nn = (1:prm.Ncp).';
ph = exp(-2j*pi*prm.c1*(N^2 - 2*N*nn));
assert(max(abs(ph - 1)) < 1e-10, 'CPP phase factor differs from 1 by %.3g', ...
    max(abs(ph-1)));

% (4) c1 = c2 = 0 reduces to OFDM (IDFT)
prm0 = prm; prm0.c1 = 0; prm0.c2 = 0;
x0 = afdm_mod(X(:,1), setfield(prm0, 'Nsym', 1)); %#ok<SFLD>
xo = sqrt(N)*ifft(X(:,1));
assert(max(abs(x0(prm.Ncp+1:end) - xo)) < 1e-10, 'c1=c2=0 does not give OFDM');

% (5) shift-q law: circular delay by l chips on the CP'd stream moves a
%     single-bin symbol at m to bin mod(m - q, N), q = (2(fmax+xi)+1)*l
l  = 3;
m0 = 20;
Xs = zeros(N,1); Xs(m0+1) = 1;
xs = afdm_mod(Xs, setfield(prm, 'Nsym', 1)); %#ok<SFLD>
xd = [zeros(l,1); xs];                        % delay within CP
Yd = afdm_demod(xd, setfield(prm, 'Nsym', 1)); %#ok<SFLD>
q  = (2*(prm.fmax + prm.xi) + 1) * l;
[~, kmax] = max(abs(Yd));
assert(kmax-1 == mod(m0 - q, N), ...
    'shift-q law violated: peak at %d, expected %d', kmax-1, mod(m0-q, N));
assert(abs(abs(Yd(kmax)) - 1) < 1e-9, 'shifted peak magnitude %.3g != 1', abs(Yd(kmax)));

% (6) literature matrix identity (Bemani 2023 TWC): A = Lambda_c2 F Lambda_c1
%     with F(m,n) = exp(-j2pi mn/N)/sqrt(N), Lambda_c = diag(exp(-j2pi c n^2)).
%     afdm_mod on the identity grid must return A^H column-for-column
%     (complex values, not magnitudes). With round trip exact and A^H full
%     rank, this also pins afdm_demod == A exactly.
nv = 0:N-1;
F  = exp(-2j*pi*(nv.'*nv)/N) / sqrt(N);
A  = diag(exp(-2j*pi*prm.c2*nv.^2)) * F * diag(exp(-2j*pi*prm.c1*nv.^2));
prmI = prm; prmI.Nsym = N;
xI = reshape(afdm_mod(eye(N), prmI), N+prm.Ncp, N);
xI = xI(prm.Ncp+1:end, :);                    % strip CPs
assert(max(abs(xI - A'), [], 'all') < 1e-9, ...
    'afdm_mod deviates from literature A^H by %.3g', max(abs(xI - A'), [], 'all'));

% (7) Doppler sign: y[n] = exp(j2pi f0 n/N) x[n], n = 0 at first post-CP
%     sample. q = (2(fmax+xi)+1)*0 - f0 = -f0, so bin m0 -> mod(m0 + f0, N).
f0 = 1;  m0 = 20;
Xs = zeros(N,1); Xs(m0+1) = 1;
prm1 = prm; prm1.Nsym = 1;
xs = afdm_mod(Xs, prm1);
np = (-prm.Ncp : N-1).';
yd = xs .* exp(2j*pi*f0*np/N);
Yd = afdm_demod(yd, prm1);
[~, kmax] = max(abs(Yd));
assert(kmax-1 == mod(m0 + f0, N), ...
    'Doppler sign violated: peak at %d, expected %d', kmax-1, mod(m0+f0, N));
assert(abs(abs(Yd(kmax)) - 1) < 1e-9, 'Doppler peak magnitude %.3g != 1', abs(Yd(kmax)));

end
