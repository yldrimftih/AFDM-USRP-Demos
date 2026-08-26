%% =========================================================================
%  FILE:     test_stage5_chain.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Unit test for the Stage 5 EPA chain (embedded per-symbol pilot):
%    stage5_afdm_build -> impaired channel -> stage5_afdm_rx, both
%    deployed configurations (N = 64 moderate, N = 256 comfortable).
%  INPUTS:
%     none
%  OUTPUTS:
%    none (errors on failure)
%  DEPENDENCIES:
%    stage5_params, stage5_afdm_build, stage5_afdm_rx, frac_shift
% =========================================================================
function test_stage5_chain

for N = [64 256]
    prm = stage5_params(N);

    % (a) flat noiseless: clean, dominant path (0,0) in every symbol
    o = runChain(0, 0, 1, Inf, prm);
    assert(o.ber == 0, 'N=%d flat: BER %.3g', N, o.ber);
    assert(o.evmPct < 3, 'N=%d flat: EVM %.2f%%', N, o.evmPct);
    for sy = 1:prm.Nsym
        [~, ip] = max(abs(o.hSym{sy}.h));
        assert(o.hSym{sy}.l(ip) == 0 && o.hSym{sy}.f(ip) == 0, ...
            'N=%d flat: sym %d dominant (%d,%d)', N, sy, ...
            o.hSym{sy}.l(ip), o.hSym{sy}.f(ip));
    end

    % (b) planted integer delay (within ellmax): localized per symbol
    lPlant = min(2, prm.ellmax);
    o = runChain(lPlant, 0, 1, Inf, prm);
    assert(o.ber == 0, 'N=%d delay: BER %.3g', N, o.ber);
    [~, ip] = max(abs(o.hSym{1}.h));
    assert(o.hSym{1}.l(ip) == lPlant, 'N=%d delay: read %d != %d', ...
        N, o.hSym{1}.l(ip), lPlant);

    % (c) fractional small delay within the backoff budget
    o = runChain(0.40, 0, 1, Inf, prm);
    assert(o.ber == 0, 'N=%d frac delay: BER %.3g', N, o.ber);
    assert(o.evmPct < 8, 'N=%d frac delay: EVM %.2f%%', N, o.evmPct);

    % (d) ACCEPTANCE: differential-Doppler 2-path. Drift over the frame
    % dph*dnu*Nsym = 7.854*0.02*9 = 1.4 rad >> 0.5 -- a single
    % frame-level estimate cannot close this; per-symbol CE must.
    o = runChain([0 min(2,prm.ellmax)], [0.01 -0.01], [1 0.7], Inf, prm);
    assert(o.ber < 1e-3, 'N=%d diff-Doppler: BER %.3g', N, o.ber);

    % (e) 30 dB draws
    for t = 1:2
        o = runChain(0, 0, 1, 30, prm);
        assert(o.ber == 0, 'N=%d 30 dB draw %d: BER %.3g', N, t, o.ber);
    end

    % (f) FRACTIONAL readout from the embedded pilot (entry 03:40):
    % per-symbol recovery of a fractional delay, physical units
    prmF = prm;  prmF.fracCE = true;
    o = runChain(0.40, 0, 1, Inf, prmF);
    assert(o.ber == 0, 'N=%d fracCE: BER %.3g', N, o.ber);
    for sy = 1:prmF.Nsym
        [~, ip] = max(abs(o.fracSym{sy}.h));
        assert(abs(o.fracSym{sy}.tau(ip) - 0.40) < 0.05, ...
            'N=%d fracCE sym %d: tau %.3f != 0.40', N, sy, ...
            o.fracSym{sy}.tau(ip));
    end

    % (g) PHASE-SLOPE law: per-path Doppler readable across symbols.
    % 2-path differential Doppler; the recovered gain phase of each path
    % must advance by dph*nu_p per symbol (entry 03:40 sanity 2).
    nuP = [0.02 -0.02];
    o = runChain([0 min(2,prm.ellmax)], nuP, [1 0.7], Inf, prmF);
    dph = 2*pi*(prm.Nfft + prm.Ncp)/prm.Nfft;
    tauRef = [0 min(2,prm.ellmax)];
    for pth = 1:2
        ph = nan(1, prmF.Nsym);
        for sy = 1:prmF.Nsym
            [dm, ip] = min(abs(o.fracSym{sy}.tau - tauRef(pth)));
            if dm < 0.5, ph(sy) = angle(o.fracSym{sy}.h(ip)); end
        end
        ok = find(~isnan(ph));
        assert(numel(ok) >= 5, 'N=%d phase-slope: path %d found in %d syms', ...
            N, pth, numel(ok));
        slope = median(diff(unwrap(ph(ok))));
        want  = dph * nuP(pth);
        assert(abs(slope - want) < 0.3*abs(want) + 0.02, ...
            'N=%d phase-slope path %d: %.4f rad/sym != %.4f', ...
            N, pth, slope, want);
    end
end

% (h) MATCHED profile (N = 256)
prmM = stage5_params(256, 'matched');
prmC = combofdm_params(256, 'matched');
% resource + energy accounting must be EXACT vs the comb by construction
assert(prmM.zoneLen == 35 && numel(prmM.dataBins) == 221, ...
    'matched EPA: zone %d, data %d', prmM.zoneLen, numel(prmM.dataBins));
assert(numel(prmC.dataBins) == 221 && ...
    numel(prmC.pilotBins) + numel(prmC.nullBins) == 35, ...
    'matched comb: data %d, non-data %d', numel(prmC.dataBins), ...
    numel(prmC.pilotBins) + numel(prmC.nullBins));
assert(abs(prmM.Ap^2 - numel(prmC.pilotBins)) < 1e-9, ...
    'matched: Ap^2 %.3f != comb pilot energy %d', prmM.Ap^2, ...
    numel(prmC.pilotBins));

% flat noiseless / frac delay (span = 2 kernel) / 30 dB
o = runChain(0, 0, 1, Inf, prmM);
assert(o.ber == 0 && o.evmPct < 3, 'matched flat: BER %.3g EVM %.2f%%', ...
    o.ber, o.evmPct);
o = runChain(0.40, 0, 1, Inf, prmM);
assert(o.ber == 0 && o.evmPct < 8, ...
    'matched frac delay (span 2): BER %.3g EVM %.2f%%', o.ber, o.evmPct);
o = runChain(0, 0, 1, 30, prmM);
assert(o.ber == 0, 'matched 30 dB: BER %.3g', o.ber);

% xi = 0 leakage: benign at the indoor residual (nu = 0.01), degraded
% beyond the declared boundary (nu = 0.25) -- the boundary is a claim of
% the profile, so both directions are asserted.
oB = runChain(0, 0.01, 1, Inf, prmM);
assert(oB.ber == 0 && oB.evmPct < 8, ...
    'matched nu=0.01: BER %.3g EVM %.2f%%', oB.ber, oB.evmPct);
oX = runChain(0, 0.25, 1, Inf, prmM);
assert(oX.evmPct > 1.5*oB.evmPct, ...
    'matched xi=0 boundary: nu=0.25 EVM %.2f%% not > 1.5x nu=0.01 %.2f%%', ...
    oX.evmPct, oB.evmPct);

% differential-Doppler acceptance at the matched guards
o = runChain([0 2], [0.01 -0.01], [1 0.7], Inf, prmM);
assert(o.ber < 1e-3, 'matched diff-Doppler: BER %.3g', o.ber);

% per-symbol fractional readout at kernelSpan = 2
prmMF = prmM;  prmMF.fracCE = true;
o = runChain(0.40, 0, 1, Inf, prmMF);
assert(o.ber == 0, 'matched fracCE: BER %.3g', o.ber);
for sy = 1:prmMF.Nsym
    [~, ip] = max(abs(o.fracSym{sy}.h));
    assert(abs(o.fracSym{sy}.tau(ip) - 0.40) < 0.05, ...
        'matched fracCE sym %d: tau %.3f != 0.40', sy, ...
        o.fracSym{sy}.tau(ip));
end

end

function o = runChain(taus, nus, gains, snrdB, prmU)
M = prmU.M;
nBits = prmU.bps * numel(prmU.dataBins) * prmU.Nsym;
bits  = randi([0 1], nBits, 1);
[x, ref] = stage5_afdm_build(bits, prmU);
cut  = ref.chipIdx(1) - 2*prmU.gd + ref.nSTF*M;
head = x(1:cut-1);  sec = x(cut:end);
k    = (0:numel(sec)-1).';
secP = zeros(numel(sec),1);
for p = 1:numel(taus)
    sd = frac_shift(sec, -taus(p)*M);
    secP = secP + gains(p) * sd .* exp(2j*pi*nus(p)*k/(M*prmU.Nfft));
end
y = 0.05*[zeros(700,1); head; secP; zeros(3000,1)];
if isfinite(snrdB)
    Ps = mean(abs(0.05*x).^2);
    y = y + sqrt(Ps*10^(-snrdB/10)/2)*(randn(size(y))+1j*randn(size(y)));
end
o = stage5_afdm_rx(y, ref, prmU);
assert(o.m > 0.6, 'N=%d: detection failed (m=%.2f)', prmU.Nfft, o.m);
o.ber = mean(o.bitsHat ~= bits);
end
