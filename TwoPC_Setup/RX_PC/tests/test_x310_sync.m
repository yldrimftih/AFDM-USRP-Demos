%% =========================================================================
%  FILE:     test_x310_sync.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    Replays the failure seen on the X310 pair (2026-09-26): CFO of
%    -7.5 kHz, beyond the STF's +-6.25 kHz unambiguous range, plus LO-
%    leakage tones 27 dB above the noise, and a capture that ends inside
%    a second OFDM burst. With the RX front end of RX_PC_MAIN
%    (rx_chansel + cfoAmbig + noiseBW) both waveforms must decode with
%    BER 0 and the CFO must be estimated within 50 Hz; the second check
%    shows the legacy front end really did alias.
%  INPUTS:
%    none
%  OUTPUTS:
%    none (errors on failure)
%  DEPENDENCIES:
%    twopc_frame_contract, combofdm_rx, stage5_afdm_rx, rx_chansel
% =========================================================================
function test_x310_sync

C = twopc_frame_contract();
fs = C.prmO.fs;  cfo = -7500;
rs = RandStream('mt19937ar', 'Seed', 7);

% IF-removed composite: OFDM, AFDM, then an OFDM burst cut by the end
y = [zeros(20000,1); C.xO; zeros(15000,1); C.xA; zeros(15000,1); ...
     C.xO(1:30000)];
n = (0:numel(y)-1).';
y = 0.05 * y .* exp(1j*(2*pi*cfo*n/fs + 0.7));
Ps = mean(abs(0.05*C.xO).^2);
sig2 = Ps * 10^(-3.5);                                  % 35 dB SNR
y = y + sqrt(sig2/2) * (randn(rs, size(y)) + 1j*randn(rs, size(y)));
% RX and TX LO leakage: tones at -240 kHz and -240 kHz + cfo
aT = sqrt(sig2 * 10^2.7);
y = y + aT * (exp(-1j*2*pi*240e3*n/fs) + 0.5*exp(1j*2*pi*(cfo-240e3)*n/fs));

prms = {C.prmO, C.prmA};  refs = {C.refO, C.refA};
rxf  = {@combofdm_rx, @stage5_afdm_rx};
[yf, nbw] = rx_chansel(y, fs);
for w = 1:2
    p = prms{w};  p.cfoAmbig = 2;  p.noiseBW = nbw;
    o = rxf{w}(yf, refs{w}, p);
    assert(o.m > 0.9, 'w%d: sync metric %.3f', w, o.m);
    assert(abs(o.cfoHz - cfo) < 50, 'w%d: CFO %.0f Hz, true %.0f', w, o.cfoHz, cfo);
    ber = mean(o.bitsHat ~= C.bits);
    assert(ber == 0, 'w%d: BER %.3g', w, ber);
end

% legacy front end on the same capture: the coarse CFO aliases
[~, cfoL] = burst_sync(y, C.refO, C.prmO);
assert(abs(cfoL - cfo) > 1000, 'legacy sync unexpectedly resolved %.0f Hz', cfoL);

end
