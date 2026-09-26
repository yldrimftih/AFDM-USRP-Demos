%% =========================================================================
%  FILE:     SELFTEST.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Fresh-install check, NO RADIO NEEDED. Run this first on each PC: it
%    verifies the required toolboxes, builds the deterministic contract,
%    and runs the complete synthetic transmit -> channel -> receive
%    pipeline for both waveforms, asserting BER 0 and a bit-exact image.
%    When it passes, connect the X310 (Ethernet), start the MAIN script of
%    this PC and press Scan in its window.
%
%  INPUTS:  none
%  OUTPUTS: none (prints [SELFTEST] PASS, or errors with a reason)
%
%  DEPENDENCIES:
%    src/twopc_frame_contract.m and its chain
% =========================================================================
function SELFTEST

addpath(fullfile(fileparts(mfilename('fullpath')), 'src'));
fprintf('[SELFTEST] MATLAB %s on %s\n', version, computer);

% 1. dependency probes with actionable messages
probes = { ...
  'qammod',        'Communications Toolbox';
  'rcosdesign',    'Signal Processing Toolbox';
  'pwelch',        'Signal Processing Toolbox';
  'comm.SDRuTransmitter', 'Communications Toolbox Support Package for USRP Radio'};
for k = 1:size(probes,1)
    assert(exist(probes{k,1}, 'file') > 0 || exist(probes{k,1}, 'class') > 0, ...
        '[SELFTEST] missing %s -> install: %s', probes{k,1}, probes{k,2});
end
fprintf('[SELFTEST] toolbox probes OK\n');

% 2. contract + synthetic composite capture at 30 dB
C = twopc_frame_contract();
fprintf('[SELFTEST] contract OK: %d bits/frame, %d-sample frames\n', ...
    numel(C.bits), numel(C.xA));
y  = 0.02*[zeros(3000,1); C.xO; zeros(10000,1); C.xA; zeros(3000,1)];
Ps = mean(abs(0.02*C.xO).^2);
y  = y + sqrt(Ps*10^(-3))/sqrt(2) * (randn(size(y)) + 1j*randn(size(y)));
oO = combofdm_rx(y, C.refO, C.prmO);
oA = stage5_afdm_rx(y, C.refA, C.prmA);

% 3. asserts
assert(oO.m > 0.6 && oA.m > 0.6, '[SELFTEST] sync failed (m %.2f / %.2f)', ...
    oO.m, oA.m);
berO = mean(oO.bitsHat ~= C.bits);  berA = mean(oA.bitsHat ~= C.bits);
assert(berO == 0 && berA == 0, '[SELFTEST] BER %.3g / %.3g != 0', berO, berA);
dsc = double(xor(oA.bitsHat, C.pn));
assert(isequal(bits2img420(dsc(1:6*C.S^2), C.S), C.rgb), ...
    '[SELFTEST] image not bit-exact');
fprintf(['[SELFTEST] synthetic chain OK: BER 0 both waveforms, EVM ' ...
    '%.2f%% / %.2f%%, image bit-exact\n'], oO.evmPct, oA.evmPct);
fprintf(['[SELFTEST] === PASS === next: connect the X310 (Ethernet), run ' ...
    'the MAIN script and press Scan\n']);

end
