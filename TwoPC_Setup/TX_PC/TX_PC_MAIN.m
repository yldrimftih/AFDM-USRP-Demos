%% =========================================================================
%  FILE:     TX_PC_MAIN.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%            X310 port (Ethernet, network scan)
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    TRANSMIT PC ENTRY POINT of the two-PC demo. Sends the PS-OFDM and
%    PS-AFDM image bursts of the deterministic contract in an endless
%    alternating loop and shows the transmit panel: image being sent,
%    transmit spectra, ideal constellation, PAPR, frame counter, a live
%    TX-gain control and the radio-selection strip. Run RX_PC_MAIN.m on
%    the other PC. CLOSE THE WINDOW TO STOP.
%
%    >>> NO SERIAL / IP TO TYPE: press SCAN in the window. The X310 found
%        on this PC's network is connected automatically (if several are
%        found, pick one in the list and press Connect). <<<
%
%  SAFETY:
%    Antenna link only, antennas >= 1 m apart and never touching. The TX
%    gain can never exceed P.txGainMax. For a cable loopback you must
%    insert a 30 dB attenuator and keep the TX gain low.
%
%  INPUTS:
%    P : optional overrides (defaults in the USER SETTINGS block below)
%        .fc .txGain .txGainMin .txGainMax .daughterboard .channel
%        .ipAddress (skip the scan) .autoScan .scanIPs
%        .imgFile ('dog.jpg', must match the RX PC) .maxIter (Inf)
%        .snapshot (save a panel PNG on exit)
%  OUTPUTS:
%    out : struct -- .iters .txGain .ipAddress
%
%  DEPENDENCIES:
%    src/twopc_frame_contract.m and its chain, src/x310_profile.m,
%    src/usrp_scan.m, src/usrp_scan_ui.m, src/gain_ui.m
%    Communications Toolbox + USRP support package (comm.SDRuTransmitter)
% =========================================================================
function out = TX_PC_MAIN(P)

addpath(fullfile(fileparts(mfilename('fullpath')), 'src'));
if nargin < 1, P = struct(); end

%% ================= USER SETTINGS ========================================
def = struct( ...
    'fc',            2.4e9, ...       % carrier [Hz], CBX-120: 1.2-6 GHz
    'txGain',        20, ...          % start TX gain [dB] (live control)
    'txGainMin',     [], ...          % control range [dB]; empty = the
    'txGainMax',     [], ...          %   daughterboard limit (0 / 31.5)
    'daughterboard', 'CBX-120', ...   % 'CBX-120' | 'UBX-160' | 'SBX-120'
    'channel',       1, ...           % 1 = daughterboard slot A, 2 = B
    'ipAddress',     '', ...          % set only to skip the Scan button
    'autoScan',      false, ...       % true: scan once when the window opens
    'scanIPs',       {{'192.168.10.2','192.168.40.2','192.168.30.2'}}, ...
    'imgFile',       'dog.jpg', ...   % must match the RX PC
    'maxIter',       Inf, ...
    'snapshot',      []);
%% ========================================================================
fn = fieldnames(def);
for i = 1:numel(fn)
    if ~isfield(P, fn{i}) || isempty(P.(fn{i})), P.(fn{i}) = def.(fn{i}); end
end
if isempty(P.snapshot), P.snapshot = isfinite(P.maxIter); end

R = x310_profile(P.daughterboard);
if isempty(P.txGainMin), P.txGainMin = R.txGain(1); end
if isempty(P.txGainMax), P.txGainMax = R.txGain(2); end
gRange = [max(P.txGainMin, R.txGain(1)), min(P.txGainMax, R.txGain(2))];
assert(gRange(2) > gRange(1), 'TX gain range [%g %g] is empty (%s: %g..%g dB)', ...
    P.txGainMin, P.txGainMax, R.dboard, R.txGain);
assert(P.txGain >= gRange(1) && P.txGain <= gRange(2), ...
    'SAFETY: txGain %g dB outside the allowed range [%g %g] dB', ...
    P.txGain, gRange);
assert(P.fc >= R.fRange(1) && P.fc <= R.fRange(2), ...
    'fc %.4g GHz outside the %s range %.4g-%.4g GHz', ...
    P.fc/1e9, R.dboard, R.fRange/1e9);

%% ================= T-A: CONTRACT + BUFFERS ==============================
C  = twopc_frame_contract(P.imgFile);
fs = C.prmO.fs;  M = C.prmO.M;  fOff = 240e3;
assert(mod(R.mcr, fs) == 0, 'master clock %g does not divide fs %g', R.mcr, fs);

nRF  = @(x) x .* exp(1j*2*pi*fOff*(0:numel(x)-1).'/fs);
lead = zeros(round(0.005*fs), 1);                 % 5 ms
mkB  = @(x) [lead; nRF(x); lead];                 % 5 ms head + 5 ms tail
Lbuf = max(numel(mkB(C.xO)), numel(mkB(C.xA)));
padz = @(x) [x; zeros(Lbuf - numel(x), 1)];
bufs = {padz(mkB(C.xO)), padz(mkB(C.xA))};        % constant buffer length
name = {'PS-OFDM comb', 'PS-AFDM EPA'};
col  = [0.466 0.674 0.188; 0.850 0.325 0.098];
papr = @(x) 10*log10(max(abs(x))^2 / mean(abs(x(abs(x)>0)).^2));

fprintf('[TX] === TX PC ready (%s): press Scan, close the window to stop ===\n', ...
    R.dboard);

%% ================= T-B: FIGURE + CONTROLS ===============================
fig = figure('Position',[10 60 1500 780], 'Color','w', ...
    'Name','TX PC (X310) — PS-OFDM vs PS-AFDM image demo — close window to stop');
tl = tiledlayout(fig,2,3,'TileSpacing','compact','Padding','compact');
tl.OuterPosition = [0 0.07 1 0.93];
title(tl, ['TX PC: matched PS-OFDM vs PS-AFDM, one 84x84 image per ' ...
    'frame, 16-QAM, N = 256 — demo by Dr. Hyeon Seok Rou'], ...
    'FontWeight','bold','FontSize',12);
FS = 9;

axI = nexttile(1);
image(axI, C.rgb); axis(axI,'image'); axis(axI,'off');
title(axI, 'image being sent (as-transmitted, 4:2:0 / 4-bit)', ...
    'FontSize', FS+1);

axSp = nexttile(2); hold(axSp,'on'); grid(axSp,'on');
hSp = gobjects(1,2);
for w = 1:2, hSp(w) = plot(axSp, nan, nan, 'Color', col(w,:)); end
xlim(axSp,[-500 500]); set(axSp,'FontSize',FS);
xlabel(axSp,'f [kHz]'); ylabel(axSp,'PSD [dB/Hz]');
title(axSp,'TX baseband spectra (as sent, IF +240 kHz)','FontSize',FS+1);
legend(axSp, hSp, name, 'Location','south','FontSize',FS-1);

axP = nexttile(3); axis(axP,'off');
hPar = text(axP,-0.08,0.98,'', 'FontName','FixedWidth','FontSize',FS, ...
    'VerticalAlignment','top');

axC = nexttile(4);
qpts = unique(C.refA.dataSyms(:));
plot(axC, real(qpts), imag(qpts), 'ko', 'MarkerFaceColor',[0.2 0.2 0.2], ...
    'MarkerSize', 5);
grid(axC,'on'); set(axC,'DataAspectRatio',[1 1 1],'FontSize',FS);
axis(axC,[-1.4 1.4 -1.4 1.4]); xlabel(axC,'I'); ylabel(axC,'Q');
title(axC,'ideal TX constellation (16-QAM, unit avg power)','FontSize',FS+1);

axM = nexttile(5); axis(axM,'off');
hMt = text(axM,-0.08,0.98,'starting...', 'FontName','FixedWidth', ...
    'FontSize',FS+1,'VerticalAlignment','top');

axH = nexttile(6); axis(axH,'off');
text(axH,-0.08,0.98, sprintf([ ...
    'HOW TO RUN\n\n' ...
    '1. X310 on this PC''s Ethernet,\n' ...
    '   antenna on TX/RX (slot %s)\n' ...
    '2. press Scan (bottom right)\n' ...
    '3. start RX_PC_MAIN.m on the RX PC\n' ...
    '4. raise TX gain until the RX panel\n' ...
    '   shows peak|y| near (below) 0.7\n\n' ...
    'SAFETY\n' ...
    'TX gain capped at %g dB\n' ...
    'ANTENNA LINK ONLY, >= 1 m apart\n' ...
    'cable loopback: 30 dB pad\n\n' ...
    'payload is fixed (deterministic\n' ...
    'contract): no backchannel, the RX\n' ...
    'regenerates ground truth locally'], ...
    char('A' + P.channel - 1), gRange(2)), ...
    'FontName','FixedWidth','FontSize',FS,'VerticalAlignment','top', ...
    'Interpreter','none');

gain_ui(fig, [0.05 0.008 0.33 0.052], 'TX gain (ANTENNA LINK ONLY)', ...
    'txGain', gRange, R.gainStep, P.txGain);
ui = usrp_scan_ui(fig, [0.44 0.008 0.54 0.052], P, R);

updSpec(hSp, bufs, fs);

%% ================= T-C: ENDLESS LOOP ====================================
u = 0;  itS = nan;  itTic = tic;
tx = [];  dev = [];
while u < P.maxIter && ishandle(fig)
    % ---- radio (re)connect requested by the Scan strip ------------------
    req = getappdata(fig,'usrpReq');
    if ~isempty(req)
        setappdata(fig,'usrpReq',[]);
        [tx, dev] = connectTx(tx, req, P, R, fs, ...
            getappdata(fig,'txGain'), bufs{1}, fig, ui);
    end
    if isempty(tx)
        set(hMt,'String',sprintf('TX IDLE\n\nno radio connected\npress Scan'));
        pause(0.1);                               % keeps the GUI alive
        continue;
    end

    gT = getappdata(fig,'txGain');
    if abs(tx.Gain - gT) > 1e-9, tx.Gain = min(gT, gRange(2)); end

    try
        tx(bufs{1});                                % PS-OFDM burst
        tx(bufs{2});                                % PS-AFDM burst
    catch e
        try release(tx); catch, end;  tx = [];  dev = [];  setappdata(fig,'usrpIP','');
        ui.setStatus(['radio lost: ' e.message ' -- press Scan'], 'err');
        continue;
    end
    u = u + 1;

    if mod(u, 5) == 1 || isfinite(P.maxIter)
        set(hMt,'String',sprintf([ ...
            'TX LIVE\n\nburst pairs sent %d\n' ...
            'txGain %.1f dB\n\nPAPR OFDM %.2f dB\nPAPR AFDM %.2f dB\n\n' ...
            '~%.2f s / burst pair'], u, tx.Gain, ...
            papr(bufs{1}), papr(bufs{2}), itS));
        set(hPar,'String',sprintf([ ...
            'PARAMS (contract)\n' ...
            'fc %.4g GHz | fs %g MS/s\n%g kchip/s (M %d), IF +%d kHz\n' ...
            'N 256 matched, CP 16, Nsym 48\n' ...
            '221 data bins/sym, 16-QAM\n' ...
            'bits/frame %d (84x84 px)\n' ...
            'ZC roots: OFDM u=25, AFDM u=34\n' ...
            'scrambler seed 46\n' ...
            'image %s\n' ...
            'burst %g samples (%.0f ms)\n' ...
            'radio %s'], ...
            P.fc/1e9, fs/1e6, fs/M/1e3, M, fOff/1e3, numel(C.bits), ...
            C.imgFile, Lbuf, 1e3*Lbuf/fs, devStr(dev, R, P)));
        itS = toc(itTic) / max(u - max(u-5,0), 1);  itTic = tic;
    end
    drawnow limitrate;                            % also runs the callbacks
end

%% ================= T-D: CLEANUP =========================================
if ~isempty(tx), release(tx); end
gEnd = P.txGain;
if ishandle(fig), gEnd = getappdata(fig,'txGain'); end
fprintf('[TX] stopped after %d burst pairs (txGain %.1f)\n', u, gEnd);
ip = '';  if ~isempty(dev), ip = dev.IPAddress; end
out = struct('iters',u, 'txGain',gEnd, 'ipAddress',ip);
if P.snapshot && ishandle(fig)
    fdir = fullfile(fileparts(mfilename('fullpath')), 'figures');
    if ~exist(fdir, 'dir'), mkdir(fdir); end
    png = fullfile(fdir, sprintf('tx_pc_panel_%s.png', ...
        char(datetime('now','Format','yyyyMMdd_HHmmss'))));
    exportgraphics(fig, png, 'Resolution', 150);
    fprintf('[TX] snapshot: %s\n', png);
end
if ishandle(fig) && isfinite(P.maxIter), close(fig); end

end

function [tx, dev] = connectTx(tx, dev, P, R, fs, g, warm, fig, ui)
% (re)open the transmitter on dev; the first burst actually opens the radio
if ~isempty(tx), release(tx); end
tx = [];  setappdata(fig,'usrpIP','');
try
    tx = comm.SDRuTransmitter('Platform',dev.Platform, ...
        'IPAddress',dev.IPAddress,'CenterFrequency',P.fc, ...
        'MasterClockRate',R.mcr,'InterpolationFactor',R.mcr/fs, ...
        'Gain',g,'ChannelMapping',P.channel);
    tx(warm);                                        % warm-up (radio ramp)
catch e
    if ~isempty(tx), try release(tx); catch, end, end
    ui.setStatus(sprintf('connect to %s failed: %s', dev.IPAddress, ...
        e.message), 'err');
    tx = [];  dev = [];
    return;
end
setappdata(fig,'usrpIP',dev.IPAddress);
ui.setStatus(sprintf('connected: %s', devStr(dev, R, P)), 'ok');
fprintf('[TX] connected: %s\n', devStr(dev, R, P));
end

function s = devStr(dev, R, P)
if isempty(dev), s = 'none'; return; end
sn = dev.SerialNum;  if isempty(sn), sn = '-'; end
s = sprintf('%s %s SN %s, %s slot %s', dev.Platform, dev.IPAddress, sn, ...
    R.dboard, char('A' + P.channel - 1));
end

function updSpec(hSp, bufPair, fs)
for w = 1:2
    [pp, ff] = pwelch(bufPair{w}, hann(1024), 512, 4096, fs, 'centered');
    set(hSp(w), 'XData', ff/1e3, 'YData', 10*log10(pp));
end
end
