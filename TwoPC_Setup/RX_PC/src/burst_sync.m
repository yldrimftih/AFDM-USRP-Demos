%% =========================================================================
%  FILE:     burst_sync.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    RX-SIDE ONLY. Find the burst in a capture: timing (normalized
%    cross-correlation against the shaped preamble), CFO (Moose estimator
%    from the preamble repeat), and complex channel tap (LS on preamble).
%  INPUTS:
%    y   : complex column, capture
%    ref : struct from burst_build (.preambleWave.Lp .Lr)
%    prm : struct from stage2_params
%  OUTPUTS:
%    t0    : scalar, integer burst start sample (1-based)
%    cfoHz : scalar, CFO estimate [Hz]
%    g     : complex scalar, channel tap estimate
%    m     : scalar in [0,1], normalized detection metric (gate > 0.6)
%    dfrac : scalar in [-0.5,0.5], fractional timing [samples]; true start
%            = t0 + dfrac. Pass to burst_demod.
%    g2    : complex scalar, widely-linear (image) tap — IQ imbalance;
%            pass to burst_demod for WL equalization (Eq. s2b-eq).
% =========================================================================
function [t0, cfoHz, g, m, dfrac, g2, dbg] = burst_sync(y, ref, prm)
% dbg (optional 7th output) exposes the two acquisition metrics actually
% used, so displays plot the real curves instead of a re-derivation that
% could silently diverge: .mS (S&C plateau metric, [] if no STF), .mCurve
% (normalized ZC cross-correlation), .cfoC / .cfoF (coarse / fine parts).

y  = y(:);
r  = ref.preambleWave(:);
Lr = ref.Lr;
N  = numel(y);
assert(N >= Lr, 'capture shorter than preamble reference');

% 0. Optional STF coarse stage (two-radio).
%    At |eps| >~ 1 kHz the coherent xcorr below collapses (13 rad of
%    rotation across Lr at the measured 1855 Hz), so detection itself
%    must be CFO-immune: Schmidl-Cox autocorrelation at lag Ls forms a
%    plateau over the STF for ANY eps; its phase gives coarse CFO
%    (range +-fs/(2 Ls) = +-7.8 kHz). De-rotate, then run the verified
%    chain unchanged. cfoC = 0 when disabled -> legacy path identical.
cfoC = 0;  mS = [];
yRaw = y;                                       % steps 3-4 use the RAW y
if isfield(prm, 'useSTF') && prm.useSTF
    % Guard: the coarse stage is only valid on a waveform that actually
    % carries an STF. Without this, calling it with a Stage-3/4 prm (no
    % STF in the frame) would silently lock the lag-Ls correlator onto the
    % OFDM/AFDM cyclic prefix -- prm.Nfft = 64 = stfLs -- and return a
    % plausible but CP-limited estimate (audit 2026-08-13).
    assert(isfield(ref, 'nSTF') && ref.nSTF > 0, ...
        ['burst_sync: prm.useSTF is true but ref has no STF ' ...
         '(ref.nSTF missing or 0) -- waveform/receiver mismatch']);
    Ls = prm.stfLs;
    % Window must stay inside the STF's periodic INTERIOR: pulse shaping
    % makes y[n+Ls] = y[n] only for start indices
    % j in [span*M-M+2, (Nrep-1)*Ls], i.e. an interior of
    % (Nrep-1)*Ls - span*M + M - 1 samples (539 at the defaults).
    % W = (Nrep-4)*Ls = 384 leaves a 156-sample plateau of fully valid
    % window starts; (Nrep-2)*Ls = 512 still fits but only 28 wide
    % (marginal), (Nrep-1)*Ls does not fit at all. Verified by audit
    % 2026-08-13.
    W  = max(2, prm.stfNrep - 4) * Ls;
    K  = N - Ls - W + 1;                        % valid start positions
    assert(K > 0, 'capture shorter than STF correlation window');
    pr = conj(y(1:N-Ls)) .* y(1+Ls:N);
    P  = movsum(pr, [0 W-1]);      P = P(1:K);
    E  = movsum(abs(y).^2, [0 W-1]);
    E1 = E(1:K);                                % 1st window energy
    R  = E(1+Ls : Ls+K);                        % 2nd window energy
    % Normalize by the PRODUCT of the two window energies: Cauchy-Schwarz
    % gives |P|^2 <= E1*R, so mS <= 1 always. Using R^2 alone is unbounded
    % wherever E1 > R -- e.g. the burst TRAILING edge (first window in
    % signal, second in silence), where mS ~ SNR/W. Above ~25-30 dB that
    % spurious peak beats the true plateau and the coarse estimate is
    % garbage (audit 2026-08-13: at 40 dB the argmax jumped to the burst
    % tail, cfoC error 3.8 kHz). The 0.25 gate is only meaningful with
    % this normalization.
    mS = abs(P).^2 ./ (E1 .* R + eps);
    mPk = max(mS);
    assert(mPk > 0.25, 'STF not detected (S&C metric %.3f)', mPk);
    % coherent average of P over the plateau (phase is constant there):
    % lower-variance coarse estimate than the single peak
    Ppl  = sum(P(mS > 0.8*mPk));
    cfoC = prm.fs * angle(Ppl) / (2*pi*Ls);
    % Ambiguity resolution (prm.cfoAmbig = K, default 0 = off): the S&C
    % phase only gives eps modulo fs/Ls (12.5 kHz), but two free-running
    % X310s at 2.4 GHz measured -7.5 kHz (3.1 ppm), which aliased to
    % +5 kHz and broke every frame (hardware 2026-09-26). Try
    % cfoC + k*fs/Ls, k = -K..K, and keep the one whose coherent ZC
    % correlation is strongest -- a wrong k leaves ~17 turns of rotation
    % across Lr and collapses it. Evaluated on short segments following
    % EVERY plateau: both bursts carry the same STF, so the strongest
    % plateau may belong to the other waveform, whose ZC root this r does
    % not match.
    if isfield(prm, 'cfoAmbig') && prm.cfoAmbig > 0
        iPl = find(mS > 0.8*mPk);
        iPl = iPl([true; diff(iPl) > 1]);        % first index of each plateau
        cands = cfoC + (-prm.cfoAmbig:prm.cfoAmbig) * prm.fs/Ls;
        best  = zeros(size(cands));
        for p = 1:numel(iPl)
            seg = max(1, iPl(p) - Lr) : min(N, iPl(p) + ref.nSTF*prm.M + 3*Lr);
            if numel(seg) < Lr, continue; end
            nS  = (seg - 1).';
            for q = 1:numel(cands)
                mc = max(zcMetric(y(seg) .* ...
                    exp(-1j*2*pi*cands(q)*nS/prm.fs), r, Lr));
                best(q) = max(best(q), mc);
            end
        end
        [~, q] = max(best);
        cfoC = cands(q);
    end
    y    = y .* exp(-1j*2*pi*cfoC*(0:N-1).'/prm.fs);   % for steps 1-3 only
end

% 1. Cross-correlation r^* (*) y via convolution with conj(flip(r));
%    c(tau) = sum_n r*[n] y[n+tau-1], tau = 1..N-Lr+1
mCurve = zcMetric(y, r, Lr);

% 2. Peak -> timing + detection metric; fractional refinement by parabolic
%    interpolation on the correlation magnitude (integer timing at M=4
%    leaves up to T/8 ISI ~ 15% EVM — observed on hardware 2026-08-11)
%    Only bursts whose whole frame fits in the capture are eligible: a
%    capture often ends inside a later burst of the same waveform, whose
%    intact preamble can out-peak the complete one and turn a decodable
%    capture into a miss (X310 hardware 2026-09-26, ~1 capture in 6).
mSel = mCurve;
if isfield(ref, 'chipIdx')
    tMax = N - (ref.chipIdx(end) + prm.gd + prm.M);
    if tMax >= 1 && tMax < numel(mSel), mSel(tMax+1:end) = 0; end
end
[m, t0] = max(mSel);
if t0 > 1 && t0 < numel(mCurve)
    a = mCurve(t0-1); b = mCurve(t0); c2 = mCurve(t0+1);
    dfrac = 0.5*(a - c2) / (a - 2*b + c2);    % peak at t0 + dfrac
else
    dfrac = 0;
end

% 3. Moose CFO from preamble repeat (first copy window, lag Lp)
P1 = t0 : t0 + ref.Lp - 1;                    % first ZC copy (shaped)
P  = sum( conj(y(P1)) .* y(P1 + ref.Lp) );
cfoF  = prm.fs * angle(P) / (2*pi*ref.Lp);    % fine (residual after STF)
cfoHz = cfoC + cfoF;                          % total, for callers (raw y)

% 4. Widely-linear joint LS [g1, g2] on de-rotated, aligned preamble
%    (Eq. s2b-ls). After CFO de-rotation the IQ-imbalance image term
%    rotates at -2*eps, so its basis carries that phase explicitly —
%    a static conj(r) basis fails for |eps| beyond a few Hz.
%    g2 = 0 recovers plain LS.
%    RAW y + TOTAL cfoHz here (not the coarse-derotated copy): the callers
%    de-rotate their own segment from t0 by cfoHz, so g and g2 must carry
%    exactly that reference. Fitting on the coarse-derotated copy instead
%    scales BOTH taps by the same c = exp(-j2pi cfoC (t0-1)/fs); the WL
%    formula then applies conj(c) to the direct term but c to the image
%    term, so the image residual is (c* - c) = -2j Im(c) times g* g2 --
%    i.e. up to ~11% EVM of uncancelled image at 25 dB IRR (audit
%    2026-08-13, which also measured |g2| collapsing to 0.48 of truth if
%    the image basis additionally used cfoF instead of the total).
nSeg = (0:Lr-1).';
ySeg = frac_shift(yRaw(t0 + nSeg), dfrac);
ySeg = ySeg .* exp(-1j*2*pi*cfoHz*nSeg/prm.fs);
bImg = conj(r) .* exp(-1j*4*pi*cfoHz*nSeg/prm.fs);
h    = [r, bImg] \ ySeg;
g    = h(1);
g2   = h(2);          % image tap referenced to n = 0 (= t0)

if nargout > 6
    dbg = struct('mS', mS, 'mCurve', mCurve, 'cfoC', cfoC, 'cfoF', cfoF);
end

end

function mCurve = zcMetric(y, r, Lr)
% normalized cross-correlation r^* (*) y via convolution with conj(flip(r));
% c(tau) = sum_n r*[n] y[n+tau-1], tau = 1..N-Lr+1
N     = numel(y);
cFull = conv(y, conj(flipud(r)));
c     = cFull(Lr:N);                          % valid part
% moving capture energy over Lr-sample windows, same tau grid
eWin  = movsum(abs(y).^2, [0 Lr-1]);
eWin  = eWin(1:N-Lr+1);
mCurve = abs(c) ./ sqrt(eWin * sum(abs(r).^2) + eps);
end
