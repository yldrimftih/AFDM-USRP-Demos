%% =========================================================================
%  FILE:     combofdm_rx.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    RX-SIDE ONLY. Comb-pilot PS-OFDM receiver: burst_sync -> align/
%    derot/WL -> matched filter -> chip sampling with timing backoff ->
%    DFT -> PER-SYMBOL comb LS + exact DFT-domain H(k) reconstruction ->
%    per-bin equalization -> demap. Per-symbol CE = native OFDM answer to
%    time-varying channels (no CPE loop needed; CE carries the phase).
%  INPUTS:
%    y   : complex column capture
%    ref : struct from combofdm_build
%    prm : struct from combofdm_params
%  OUTPUTS:
%    out : struct — .bitsHat.dEq (Nd x Nsym) .evmPct .evmSym
%          .Hsym (N x Nsym, per-symbol H(k)) .t0 .m.cfoHz .g .g2 .dfrac
%          .nBack.dbg
%  DEPENDENCIES:
%    burst_sync, frac_shift, afdm_demod
% =========================================================================
function out = combofdm_rx(y, ref, prm)

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

% 2. Matched filter, backoff chip sampling, DFT
nB   = prm.nBack;
p    = rcosdesign(prm.beta, prm.span, prm.M, 'sqrt');
smf  = conv(seg, p(:));
assert(ref.chipIdx(1) - nB*prm.M >= 1, 'backoff exceeds available samples');
chips = smf(ref.chipIdx - nB*prm.M);
Y    = afdm_demod(chips, prm);          % c1 = c2 = 0 -> plain DFT grid

% 3. Per-symbol comb CE + equalization
Nd   = numel(prm.dataBins);
Np   = numel(prm.pilotBins);
useTrunc = isfield(prm,'ceTrunc') && prm.ceTrunc;
useMMSE  = isfield(prm,'eqMode') && strcmp(prm.eqMode,'mmse');
S = prm.nBack + prm.ellmax + prm.kernelSpan + 1;   % causal tap support
if useMMSE
    % pre-burst noise variance, translated through the linear front end
    % (identical recipe to stage5_afdm_rx step 3a; unitary DFT preserves)
    iEnd   = t0 - ref.nSTF*prm.M - 200;
    iStart = max(1, iEnd - 2000);
    assert(iEnd - iStart > 400, 'no pre-burst noise window in capture');
    s2t    = median(abs(y(iStart:iEnd)).^2) / log(2);
    if isfield(prm, 'noiseBW'), s2t = s2t / prm.noiseBW; end   % rx_chansel
    sigma2 = s2t * (abs(g)^2 + abs(g2)^2) / ((abs(g)^2 - abs(g2)^2)^2 ...
             * ref.scale^2);
    sigma2 = max(sigma2, 1e-12);
end
dEq  = zeros(Nd, prm.Nsym);
Hsym = zeros(N, prm.Nsym);
for sy = 1:prm.Nsym
    Hp = Y(prm.pilotBins + 1, sy) ./ ref.pilotSeq;
    gt = ifft(Hp);                      % Np causal taps (backoff)
    if useTrunc
        gt(S+1:end) = 0;                % known-support denoising (x S/Np)
    end
    H  = fft([gt; zeros(N - Np, 1)]);   % exact alias-free reconstruction
    Hsym(:, sy) = H;
    Yd = Y(prm.dataBins + 1, sy);  Hd = H(prm.dataBins + 1);
    if useMMSE
        % biased per-bin MMSE, then bias correction for symbol metrics/
        % demap; unbiased scalar MMSE == ZF algebraically (entry 17:55)
        c = abs(Hd).^2 ./ (abs(Hd).^2 + sigma2);
        dEq(:, sy) = (Yd .* conj(Hd) ./ (abs(Hd).^2 + sigma2)) ./ c;
    else
        dEq(:, sy) = Yd ./ Hd;
    end
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

out = struct('bitsHat', bitsHat(:), 'dEq', dEq, 'evmPct', evmPct, ...
    'evmSym', evmSym, 'Hsym', Hsym, 't0', t0, 'm', m, 'cfoHz', cfoHz, ...
    'g', g, 'g2', g2, 'dfrac', dfrac, 'nBack', nB);
out.dbg = dbg;

end
