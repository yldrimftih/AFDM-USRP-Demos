%% =========================================================================
%  FILE:     TX_PC_MAIN.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    TRANSMIT PC ENTRY POINT of the two-PC demo. Sends the PS-OFDM and
%    PS-AFDM image bursts of the deterministic contract in an endless
%    alternating loop and shows the transmit panel: image being sent,
%    transmit spectra, ideal constellation, PAPR, frame counter and a
%    live TX-gain slider. Run RX_PC_MAIN.m on the other PC.
%    CLOSE THE WINDOW TO STOP.
%
%    >>> SET YOUR B210 SERIAL IN THE txSerial LINE BELOW (findsdru) <<<
%
%  SAFETY:
%    Antenna link only, antennas >= 30 cm apart and never touching;
%    txGain <= 80 is asserted. For a cable loopback you must insert a
%    30 dB attenuator and stay at txGain <= 55.
%
%  INPUTS:
%    P : optional overrides -- .txSerial .fc (2.4e9) .txGain (65)
%        .imgFile ('dog.jpg', must match the RX PC) .maxIter (Inf)
%        .snapshot (save a panel PNG on exit)
%  OUTPUTS:
%    out : struct -- .iters .txGain
%
%  DEPENDENCIES:
%    src/twopc_frame_contract.m and its chain
%    Communications Toolbox + USRP support package (comm.SDRuTransmitter)
% =========================================================================
function out = TX_PC_MAIN(P)

addpath(fullfile(fileparts(mfilename('fullpath')), 'src'));
if nargin < 1, P = struct(); end
def = struct('txSerial','YOUR_TX_B210_SERIAL', 'fc',2.4e9, 'txGain',65, ...
             'imgFile','dog.jpg', 'maxIter',Inf, 'snapshot',[]);
fn = fieldnames(def);
for i = 1:numel(fn)
    if ~isfield(P, fn{i}) || isempty(P.(fn{i})), P.(fn{i}) = def.(fn{i}); end
end
if isempty(P.snapshot), P.snapshot = isfinite(P.maxIter); end
assert(~contains(P.txSerial,'YOUR_'), ['Set your B210 serial: edit the ' ...
    'txSerial default in TX_PC_MAIN.m, or call ' ...
    'TX_PC_MAIN(struct(''txSerial'',''XXXXXXX'')). Serials are listed by ' ...
    'findsdru in MATLAB or uhd_find_devices in a terminal.']);
assert(P.txGain <= 80, ['SAFETY: txGain %g > 80. Antenna link only, ' ...
    '>= 30 cm; never at cable loopback (<= 55 there, with a 30 dB pad).'], ...
    P.txGain);

%% ================= T-A: CONTRACT + BUFFERS ==============================
C  = twopc_frame_contract(P.imgFile);
fs = C.prmO.fs;  M = C.prmO.M;  fOff = 240e3;

nRF  = @(x) x .* exp(1j*2*pi*fOff*(0:numel(x)-1).'/fs);
lead = zeros(round(0.005*fs), 1);                 % 5 ms
mkB  = @(x) [lead; nRF(x); lead];                 % 5 ms head + 5 ms tail
Lbuf = max(numel(mkB(C.xO)), numel(mkB(C.xA)));
padz = @(x) [x; zeros(Lbuf - numel(x), 1)];
bufs = {padz(mkB(C.xO)), padz(mkB(C.xA))};        % constant buffer length
name = {'PS-OFDM comb', 'PS-AFDM EPA'};
col  = [0.466 0.674 0.188; 0.850 0.325 0.098];
papr = @(x) 10*log10(max(abs(x))^2 / mean(abs(x(abs(x)>0)).^2));

mcr = 16e6;
tx = comm.SDRuTransmitter('Platform','B210','SerialNum',P.txSerial, ...
    'CenterFrequency',P.fc,'MasterClockRate',mcr, ...
    'InterpolationFactor',mcr/fs,'Gain',P.txGain,'ChannelMapping',1);

fprintf('[TX] === TX PC LIVE (serial %s): close the window to stop ===\n', ...
    P.txSerial);

%% ================= T-B: FIGURE + CONTROLS ===============================
fig = figure('Position',[10 60 1500 780], 'Color','w', ...
    'Name','TX PC — PS-OFDM vs PS-AFDM image demo — close window to stop');
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
    '1. antennas >= 30 cm apart, LOS\n' ...
    '2. start RX_PC_MAIN.m on the RX PC\n' ...
    '3. raise TX gain until the RX panel\n' ...
    '   shows peak|y| near (below) 0.7\n\n' ...
    'SAFETY\n' ...
    'txGain <= 80 ANTENNA LINK ONLY\n' ...
    'cable loopback: <= 55 + 30 dB pad\n\n' ...
    'payload is fixed (deterministic\n' ...
    'contract): no backchannel, the RX\n' ...
    'regenerates ground truth locally']), ...
    'FontName','FixedWidth','FontSize',FS,'VerticalAlignment','top');

setappdata(fig,'txGain',P.txGain);
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.05 0.035 0.22 0.022],'String', ...
    'TX gain (max 80, ANTENNA LINK ONLY)','HorizontalAlignment','left', ...
    'BackgroundColor','w');
sT = uicontrol(fig,'Style','slider','Units','normalized', ...
    'Position',[0.05 0.010 0.30 0.025],'Min',40,'Max',80, ...
    'Value',P.txGain,'SliderStep',[1 5]/40);
tT = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.355 0.010 0.04 0.025],'String',sprintf('%.1f',P.txGain), ...
    'BackgroundColor','w');
sT.Callback = @(s,~) txgaincb(s, fig, tT);

updSpec(hSp, bufs, fs);

%% ================= T-C: ENDLESS LOOP ====================================
u = 0;  itS = nan;  itTic = tic;
tx(bufs{1});                                        % warm-up (radio ramp)
while u < P.maxIter && ishandle(fig)
    u = u + 1;

    gT = getappdata(fig,'txGain');
    if abs(tx.Gain - gT) > 1e-9, tx.Gain = min(gT, 80); end

    tx(bufs{1});                                    % PS-OFDM burst
    tx(bufs{2});                                    % PS-AFDM burst

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
            'serial %s'], ...
            P.fc/1e9, fs/1e6, fs/M/1e3, M, fOff/1e3, numel(C.bits), ...
            C.imgFile, Lbuf, 1e3*Lbuf/fs, P.txSerial));
        drawnow limitrate;
        itS = toc(itTic) / max(u - max(u-5,0), 1);  itTic = tic;
    end
end

%% ================= T-D: CLEANUP =========================================
release(tx);
fprintf('[TX] stopped after %d burst pairs (txGain %.1f)\n', ...
    u, getappdata(fig,'txGain'));
out = struct('iters',u, 'txGain',getappdata(fig,'txGain'));
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

function txgaincb(s, fig, t)
v = min(round(s.Value*4)/4, 80);
setappdata(fig,'txGain',v); set(t,'String',sprintf('%.1f',v));
end

function updSpec(hSp, bufPair, fs)
for w = 1:2
    [pp, ff] = pwelch(bufPair{w}, hann(1024), 512, 4096, fs, 'centered');
    set(hSp(w), 'XData', ff/1e3, 'YData', 10*log10(pp));
end
end
