%% =========================================================================
%  FILE:     stage5_afdm_rx.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    RX-SIDE ONLY. Stage 5 EPA receiver: burst_sync -> align/derot/WL ->
%    matched filter -> chip sampling with timing backoff -> DAFT ->
%    PER-SYMBOL integer channel estimation from the embedded pilot ->
%    per-symbol MMSE -> demap. No cross-symbol tracking or prediction of
%    any kind: time variation between symbols is handled by re-estimating
%    the channel on every symbol.
%  INPUTS:
%    y   : complex column capture
%    ref : struct from stage5_afdm_build
%    prm : struct from stage5_params
%  OUTPUTS:
%    out : struct — .bitsHat.dEq (Nd x Nsym) .evmPct .evmSym
%          .ddGrid (mean |h| over symbols, (leff+1) x (2fmax+1), delay
%          axis -nBack..ellmax physical) .hSym {Nsym} .sigma2Sym
%          .cpe(=0) .t0 .m.cfoHz .g .g2 .dfrac .nBack
%          .fracSym {Nsym} per-symbol fractional (tau,nu,h) physical
%          ({} unless prm.fracCE)
%  DEPENDENCIES:
%    burst_sync, frac_shift, afdm_demod, afdm_frac_ce (prm.fracCE)
% =========================================================================
function out = stage5_afdm_rx(y, ref, prm)

y = y(:);
N = prm.Nfft;

% 1. Sync, extract, align, de-rotate, WL-correct (identical front end)
[t0, cfoHz, g, m, dfrac, g2, dbg] = burst_sync(y, ref, prm);
Lseg = ref.chipIdx(end) + prm.gd + prm.M;
assert(t0 + Lseg - 1 <= numel(y), 'frame truncated by capture end');
nSeg = (0:Lseg-1).';
seg  = frac_shift(y(t0 + nSeg), dfrac);
seg  = seg .* exp(-1j*2*pi*cfoHz*nSeg/prm.fs);
g2n  = g2 * exp(-1j*4*pi*cfoHz*nSeg/prm.fs);
seg  = (conj(g)*seg - g2n.*conj(seg)) / (abs(g)^2 - abs(g2)^2);
seg  = seg / ref.scale;

% 2. Matched filter, backoff chip sampling, DAFT
nB   = prm.nBack;
p    = rcosdesign(prm.beta, prm.span, prm.M, 'sqrt');
smf  = conv(seg, p(:));
assert(ref.chipIdx(1) - nB*prm.M >= 1, 'backoff exceeds available samples');
chips = smf(ref.chipIdx - nB*prm.M);
Y    = afdm_demod(chips, prm);

% 3a. Frame-level noise variance from the PRE-BURST window. The zone's
%     non-readout bins are NOT noise-only: data shifted by q lands there
%     legitimately (measured 2026-08-13: sigma2 read 0.136 on a noiseless
%     planted-delay run -> 12 % EVM from over-regularization; at N = 64
%     exactly ONE zone bin is data-unreachable). Noise is stationary over
%     the frame, so estimate it once, before the burst (pre-STF), and
%     translate through the known linear front end: WL combine scales
%     noise power by (|g|^2+|g2|^2)/(|g|^2-|g2|^2)^2, then 1/scale^2;
%     the unit-energy MF and the unitary DAFT preserve variance.
iEnd   = t0 - ref.nSTF*prm.M - 200;
iStart = max(1, iEnd - 2000);
assert(iEnd - iStart > 400, 'no pre-burst noise window in capture');
w      = y(iStart:iEnd);
s2t    = median(abs(w).^2) / log(2);          % robust vs stray energy
sigma2 = s2t * (abs(g)^2 + abs(g2)^2) / ((abs(g)^2 - abs(g2)^2)^2 ...
         * ref.scale^2);
sigma2 = max(sigma2, 1e-12);                  % noiseless sims -> ~ZF

% 3b. PER-SYMBOL integer CE + MMSE
s    = 2*(prm.fmax + prm.xi) + 1;
leff = prm.ellmax + nB;
nl   = leff + 1;   nf = 2*prm.fmax + 1;
[lg, fg] = meshgrid(0:leff, -prm.fmax:prm.fmax);
lg = lg(:);  fg = fg(:);
qg = s*lg - fg;
kg = mod(prm.p0 - qg, N);
p0ph = exp(+2j*pi*prm.c2*prm.p0^2);
corr = exp(-2j*pi*prm.c2*(kg.^2)) .* p0ph .* exp(-2j*pi*lg*prm.p0/N);
mv   = (0:N-1).';
c2m2 = exp(+2j*pi*prm.c2*(mv.^2));

% Optional per-symbol FRACTIONAL readout: bins
% [0, qmax+2*xif] are DATA-FREE by the zone construction (data lands at
% d - q >= zoneLen - qmax = qmax+2*xif+1), so projecting the symbol onto
% them removes data exactly and keeps the complete pilot response; the
% matched-filter estimator then runs unchanged. Enable via prm.fracCE.
useFrac = isfield(prm,'fracCE') && prm.fracCE;
xif   = prm.fmax + prm.xi;
qmax  = s*leff + xif;
kKeep = (0 : qmax + 2*xif).';               % data-free pilot subspace
fracSym = cell(1, prm.Nsym);

Nd   = numel(prm.dataBins);
dEq  = zeros(Nd, prm.Nsym);
hSym = cell(1, prm.Nsym);
s2S  = zeros(1, prm.Nsym);
grid = zeros(nl*nf, prm.Nsym);
for sy = 1:prm.Nsym
    yp = Y(:, sy);
    peaks = yp(kg+1) ./ (prm.Ap * corr);
    grid(:, sy) = abs(peaks);
    % Gate against the KNOWN noise level, not the median: the readout
    % lattice is small (5 points at N = 64) and mostly carries REAL taps
    % (a fractional delay spreads over several integer taps), so a
    % 3x-median rule gates on the taps themselves (measured 2026-08-13:
    % it dropped a |h| = 0.48 tap and floored EVM). Noise on a peak has
    % variance sigma2/Ap^2; 9x covers the small-lattice extreme value
    % (2 ln 5 ~ 3.2) with ~3x margin.
    sel = find(abs(peaks).^2 > 9 * sigma2 / prm.Ap^2);
    if isempty(sel), [~, sel] = max(abs(peaks)); end
    s2S(sy) = sigma2;                 % frame-level (see 3a)
    G = zeros(N, N);
    for pp = 1:numel(sel)
        nr   = mod(mv - qg(sel(pp)), N);
        vals = peaks(sel(pp)) * exp(-2j*pi*prm.c2*(nr.^2)) .* c2m2 ...
               .* exp(-2j*pi*lg(sel(pp))*mv/N);
        G(sub2ind([N N], nr+1, mv+1)) = G(sub2ind([N N], nr+1, mv+1)) + vals;
    end
    if useFrac
        yz = zeros(N,1);  yz(kKeep+1) = yp(kKeep+1);   % exact data removal
        fr = afdm_frac_ce(yz, prm, struct('sigma2', sigma2, ...
                 'kernelSpan', prm.kernelSpan));
        if ~isempty(fr.h)
            G = fr.G;                                  % dense fractional G
        end
        fr.tau   = fr.tau   - nB;                      % physical delays
        fr.tauAx = fr.tauAx - nB;
        if isfield(prm,'fracKeepS') && prm.fracKeepS   % display scripts
            fr = rmfield(fr, {'Gp'});
        else
            fr = rmfield(fr, {'S','Gp'});              % keep out light
        end
        fracSym{sy} = fr;
    end
    xh = ((G'*G + sigma2*eye(N)) \ G') * yp;
    dEq(:, sy) = xh(prm.dataBins + 1);
    hSym{sy} = struct('h', peaks(sel), 'l', lg(sel) - nB, 'f', fg(sel));
end

err    = dEq - ref.dataSyms;
evmPct = 100 * sqrt( mean(abs(err(:)).^2) / mean(abs(ref.dataSyms(:)).^2) );
evmSym = 100 * sqrt( mean(abs(err).^2, 1) ./ mean(abs(ref.dataSyms).^2, 1) );

switch prm.modType
    case 'qam'
        bitsHat = qamdemod(dEq(:), prm.modOrder, 'OutputType','bit', ...
                           'UnitAveragePower', true);
    case 'psk'
        bitsHat = int2bit(pskdemod(dEq(:), prm.modOrder, 0, 'gray'), prm.bps);
end

% ddGrid: mean |h| over symbols, delay axis -nBack..ellmax PHYSICAL
out = struct('bitsHat', bitsHat(:), 'dEq', dEq, 'evmPct', evmPct, ...
    'evmSym', evmSym, 'ddGrid', reshape(mean(grid,2), nf, nl).', ...
    'sigma2Sym', s2S, 'cpe', zeros(1,prm.Nsym), 't0', t0, 'm', m, ...
    'cfoHz', cfoHz, 'g', g, 'g2', g2, 'dfrac', dfrac, 'nBack', nB);
out.hSym = hSym;
out.dbg  = dbg;
out.fracSym = fracSym;   % per-symbol fractional readout ({} unless fracCE)

end
