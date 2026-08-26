%% =========================================================================
%  FILE:     test_twopc_contract.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Unit test for the two-PC deterministic frame contract and for the
%    Zadoff-Chu root discrimination that lets both receivers share one
%    capture. Checks: (a) the contract is deterministic (the premise of
%    running it independently on two PCs), (b) the bit budget, (c) the
%    bit <-> pixel mapping round trip, (d) a synthetic composite capture
%    at 30 dB where each receiver locks its own section and reaches BER 0,
%    (e) the received image is bit-exact.
%
%  INPUTS:  none
%  OUTPUTS: none (errors on failure)
%
%  DEPENDENCIES:
%    twopc_frame_contract, combofdm_rx, stage5_afdm_rx, img2bits420,
%    bits2img420
% =========================================================================
function test_twopc_contract

% (a) determinism
C  = twopc_frame_contract();
C2 = twopc_frame_contract();
assert(isequaln(C, C2), 'contract not deterministic');

% (b) bit budget
assert(numel(C.bits) == 42432 && C.nPad == 96, ...
    'budget: %d bits, %d pad', numel(C.bits), C.nPad);
assert(C.prmA.u == 34 && C.prmO.u == 25, 'ZC roots not split');

% (c) lattice round trip: transmitted rgb view re-maps to the same bits
bTx = double(xor(C.bits(1:6*C.S^2), C.pn(1:6*C.S^2)));
assert(isequal(img2bits420(C.rgb), bTx), 'lattice round trip failed');

% (d) composite capture: OFDM burst then AFDM burst, one capture,
%     both receivers, 30 dB
y = 0.02 * [zeros(3000,1); C.xO; zeros(10000,1); C.xA; zeros(3000,1)];
Ps = mean(abs(0.02*C.xO).^2);
y  = y + sqrt(Ps*10^(-30/10)/2) * (randn(size(y)) + 1j*randn(size(y)));
oO = combofdm_rx(y, C.refO, C.prmO);
oA = stage5_afdm_rx(y, C.refA, C.prmA);
assert(oO.m > 0.6 && oA.m > 0.6, 'section detection: m = %.2f / %.2f', ...
    oO.m, oA.m);
assert(oO.t0 < oA.t0, ...
    'root discrimination failed: OFDM t0 %d !< AFDM t0 %d', oO.t0, oA.t0);
assert(mean(oO.bitsHat ~= C.bits) == 0, 'OFDM BER %.3g != 0', ...
    mean(oO.bitsHat ~= C.bits));
assert(mean(oA.bitsHat ~= C.bits) == 0, 'AFDM BER %.3g != 0', ...
    mean(oA.bitsHat ~= C.bits));

% (e) received image bit-exact vs transmitted lattice view
dsc = double(xor(oA.bitsHat, C.pn));
assert(isequal(bits2img420(dsc(1:6*C.S^2), C.S), C.rgb), ...
    'received image not bit-exact');

end
