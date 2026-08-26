%% =========================================================================
%  FILE:     test_combofdm_chain.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Unit test for the comb-pilot PS-OFDM chain (native per-symbol CE):
%    combofdm_build -> impaired channel -> combofdm_rx, both N.
%  INPUTS:
%     none
%  OUTPUTS:
%    none (errors on failure)
%  DEPENDENCIES:
%    combofdm_params, combofdm_build, combofdm_rx, frac_shift
% =========================================================================
function test_combofdm_chain

for N = [64 256]
    prm = combofdm_params(N);

    % (a) flat noiseless
    o = runChain(0, 0, 1, Inf, prm);
    assert(o.ber == 0, 'N=%d flat: BER %.3g', N, o.ber);
    assert(o.evmPct < 3, 'N=%d flat: EVM %.2f%%', N, o.evmPct);
    hSpread = max(abs(o.Hsym(:,1))) / min(abs(o.Hsym(:,1)));
    assert(hSpread < 1.2, 'N=%d flat: |H| spread %.2f', N, hSpread);

    % (b) planted integer delay (within ellmax)
    o = runChain(min(2,prm.ellmax), 0, 1, Inf, prm);
    assert(o.ber == 0, 'N=%d delay: BER %.3g', N, o.ber);

    % (c) fractional small delay within the backoff budget
    o = runChain(0.40, 0, 1, Inf, prm);
    assert(o.ber == 0, 'N=%d frac delay: BER %.3g', N, o.ber);
    assert(o.evmPct < 8, 'N=%d frac delay: EVM %.2f%%', N, o.evmPct);

    % (d) differential-Doppler 2-path: per-symbol re-estimation closes it
    o = runChain([0 min(2,prm.ellmax)], [0.01 -0.01], [1 0.7], Inf, prm);
    assert(o.ber < 1e-3, 'N=%d diff-Doppler: BER %.3g', N, o.ber);

    % (e) 30 dB draws
    for t = 1:2
        o = runChain(0, 0, 1, 30, prm);
        assert(o.ber == 0, 'N=%d 30 dB draw %d: BER %.3g', N, t, o.ber);
    end
end

% (f) MATCHED profile (N = 256): nulls carry zero
% energy and are invisible downstream; chain closes as before.
prmM = combofdm_params(256, 'matched');
assert(numel(prmM.dataBins) == 221 && numel(prmM.nullBins) == 3, ...
    'matched comb: data %d, nulls %d', numel(prmM.dataBins), ...
    numel(prmM.nullBins));
nB0 = prmM.bps * numel(prmM.dataBins) * prmM.Nsym;
[~, refM] = combofdm_build(randi([0 1], nB0, 1), prmM);
assert(all(all(refM.Xgrid(prmM.nullBins + 1, :) == 0)), ...
    'matched comb: nulled bins carry energy');
o = runChain(0, 0, 1, Inf, prmM);
assert(o.ber == 0 && o.evmPct < 3, 'matched flat: BER %.3g EVM %.2f%%', ...
    o.ber, o.evmPct);
o = runChain(0.40, 0, 1, Inf, prmM);
assert(o.ber == 0, 'matched frac delay: BER %.3g', o.ber);
o = runChain(0, 0, 1, 30, prmM);
assert(o.ber == 0, 'matched 30 dB: BER %.3g', o.ber);

end

function o = runChain(taus, nus, gains, snrdB, prmU)
M = prmU.M;
nBits = prmU.bps * numel(prmU.dataBins) * prmU.Nsym;
bits  = randi([0 1], nBits, 1);
[x, ref] = combofdm_build(bits, prmU);
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
o = combofdm_rx(y, ref, prmU);
assert(o.m > 0.6, 'N=%d: detection failed (m=%.2f)', prmU.Nfft, o.m);
o.ber = mean(o.bitsHat ~= bits);
end
