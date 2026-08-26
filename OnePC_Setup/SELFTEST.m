%% =========================================================================
%  FILE:     SELFTEST.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Fresh-install check, NO RADIO NEEDED. Verifies the required toolboxes
%    and runs the complete synthetic transmit -> channel -> receive chain
%    of both waveforms at 30 dB, asserting BER 0, then checks that the
%    demo image loads into the transmitted lattice. When it passes, plug
%    both B210s in, run findsdru to read the serial numbers, put them in
%    RUN_IMAGE_DEMO.m / RUN_PANEL_DEMO.m and run one of them.
%
%  INPUTS:  none
%  OUTPUTS: none (prints [SELFTEST] PASS, or errors with a reason)
%
%  DEPENDENCIES:
%    src/ (combofdm_*, stage5_*, img_load_quant)
% =========================================================================
function SELFTEST

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'src'));
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

% 2. both chains, matched profile, 24 symbols, 16-QAM, 30 dB
prmO = combofdm_params(256, 'matched');  prmO.useSTF = true;
prmA = stage5_params(256, 'matched');    prmA.useSTF = true;
prmO.Nsym = 24;  prmO.NsymData = 24;
prmA.Nsym = 24;  prmA.NsymData = 24;
nBits = prmO.bps * numel(prmO.dataBins) * prmO.Nsym;
bits  = double(randi([0 1], nBits, 1));
[xO, refO] = combofdm_build(bits, prmO);
[xA, refA] = stage5_afdm_build(bits, prmA);

for k = 1:2
    if k == 1, x = xO; ref = refO; prm = prmO; nm = 'PS-OFDM comb';
    else,      x = xA; ref = refA; prm = prmA; nm = 'PS-AFDM EPA';  end
    y  = 0.02 * [zeros(3000,1); x; zeros(3000,1)];
    Ps = mean(abs(0.02*x).^2);
    y  = y + sqrt(Ps*10^(-3)/2) * (randn(size(y)) + 1j*randn(size(y)));
    if k == 1, o = combofdm_rx(y, ref, prm); else, o = stage5_afdm_rx(y, ref, prm); end
    assert(o.m > 0.6, '[SELFTEST] %s sync failed (m %.2f)', nm, o.m);
    ber = mean(o.bitsHat ~= bits);
    assert(ber == 0, '[SELFTEST] %s BER %.3g != 0', nm, ber);
    fprintf('[SELFTEST] %-14s OK: BER 0 over %d bits, EVM %.2f%%\n', ...
        nm, nBits, o.evmPct);
end

% 3. demo image loads into the transmitted lattice
img = img_load_quant(fullfile(here, 'dog.jpg'), 84);
assert(isequal(size(img), [84 84 3]) && max(img(:)) <= 15, ...
    '[SELFTEST] image lattice wrong: size %s, max %d', ...
    mat2str(size(img)), max(img(:)));
fprintf('[SELFTEST] demo image OK: 84x84x3, 4 bits per channel\n');

fprintf('[SELFTEST] === PASS === next: plug both B210s (USB3), run findsdru\n');

end
