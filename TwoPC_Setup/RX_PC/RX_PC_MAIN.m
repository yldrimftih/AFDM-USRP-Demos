%% =========================================================================
%  FILE:     RX_PC_MAIN.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%            X310 port (Ethernet, network scan)
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    RECEIVE PC ENTRY POINT of the two-PC demo. Captures the bursts sent by
%    TX_PC_MAIN.m on the other PC, runs BOTH receivers (comb-pilot PS-OFDM
%    and embedded-pilot PS-AFDM, per-symbol channel estimation on both) on
%    every capture, and shows the receive panel: synchronisation tiles,
%    spectrum, equalised constellations, per-symbol EVM, channel views,
%    received images, EVM and CFO histories, running BER, a live RX-gain
%    control, an ADC clip canary and the radio-selection strip.
%    CLOSE THE WINDOW TO STOP.
%
%    There is no link between the two PCs: the receiver rebuilds the
%    transmitted payload locally from the deterministic contract, so the
%    displayed BER is a true measurement.
%
%    >>> NO SERIAL / IP TO TYPE: press SCAN in the window. The X310 found
%        on this PC's network is connected automatically (if several are
%        found, pick one in the list and press Connect). <<<
%
%  SAFETY:
%    Antenna link only, antennas >= 1 m apart. Keep the clip canary
%    green: peak|y| < 0.7. If it goes red, lower RX gain (or TX gain).
%
%  INPUTS:
%    P : optional overrides (defaults in the USER SETTINGS block below)
%        .fc .rxGain .rxGainMin .rxGainMax .daughterboard .channel
%        .ipAddress (skip the scan) .autoScan .scanIPs
%        .imgFile ('dog.jpg', must match the TX PC) .maxIter (Inf)
%        .snapshot (save a panel PNG on exit)
%  OUTPUTS:
%    out : struct -- per-waveform totals (.nOK .nMiss .errTot .bitTot)
%
%  DEPENDENCIES:
%    src/twopc_frame_contract.m, combofdm_rx, stage5_afdm_rx, bits2img420,
%    src/x310_profile.m, src/usrp_scan.m, src/usrp_scan_ui.m, src/gain_ui.m
%    Communications Toolbox + USRP support package (comm.SDRuReceiver)
% =========================================================================
function out = RX_PC_MAIN(P)

addpath(fullfile(fileparts(mfilename('fullpath')), 'src'));
if nargin < 1, P = struct(); end

%% ================= USER SETTINGS ========================================
def = struct( ...
    'fc',            2.4e9, ...       % carrier [Hz], must match the TX PC
    'rxGain',        20, ...          % start RX gain [dB] (live control)
    'rxGainMin',     [], ...          % control range [dB]; empty = the
    'rxGainMax',     [], ...          %   daughterboard limit (0 / 31.5)
    'daughterboard', 'CBX-120', ...   % 'CBX-120' | 'UBX-160' | 'SBX-120'
    'channel',       1, ...           % 1 = daughterboard slot A, 2 = B
    'ipAddress',     '', ...          % set only to skip the Scan button
    'autoScan',      false, ...       % true: scan once when the window opens
    'scanIPs',       {{'192.168.10.2','192.168.40.2','192.168.30.2'}}, ...
    'imgFile',       'dog.jpg', ...   % must match the TX PC
    'maxIter',       Inf, ...
    'snapshot',      []);
%% ========================================================================
fn = fieldnames(def);
for i = 1:numel(fn)
    if ~isfield(P, fn{i}) || isempty(P.(fn{i})), P.(fn{i}) = def.(fn{i}); end
end
if isempty(P.snapshot), P.snapshot = isfinite(P.maxIter); end

R = x310_profile(P.daughterboard);
if isempty(P.rxGainMin), P.rxGainMin = R.rxGain(1); end
if isempty(P.rxGainMax), P.rxGainMax = R.rxGain(2); end
gRange = [max(P.rxGainMin, R.rxGain(1)), min(P.rxGainMax, R.rxGain(2))];
assert(gRange(2) > gRange(1), 'RX gain range [%g %g] is empty (%s: %g..%g dB)', ...
    P.rxGainMin, P.rxGainMax, R.dboard, R.rxGain);
assert(P.rxGain >= gRange(1) && P.rxGain <= gRange(2), ...
    'rxGain %g dB outside the allowed range [%g %g] dB', P.rxGain, gRange);
assert(P.fc >= R.fRange(1) && P.fc <= R.fRange(2), ...
    'fc %.4g GHz outside the %s range %.4g-%.4g GHz', ...
    P.fc/1e9, R.dboard, R.fRange/1e9);

%% ================= R-A: CONTRACT + RADIO ================================
C    = twopc_frame_contract(P.imgFile);
prms = {C.prmO, C.prmA};
refs = {C.refO, C.refA};                      % sync refs + ideal symbols
rxf  = {@combofdm_rx, @stage5_afdm_rx};
name = {'PS-OFDM comb', 'PS-AFDM EPA'};
col  = [0.466 0.674 0.188; 0.850 0.325 0.098];
fs = prms{1}.fs;  M = prms{1}.M;  fOff = 240e3;  S = C.S;
nBits = numel(C.bits);
band  = fOff + [-1 1]*(1+prms{1}.beta)*(fs/M)/2;
pn    = C.pn;
assert(mod(R.mcr, fs) == 0, 'master clock %g does not divide fs %g', R.mcr, fs);

fprintf('[RX] === RX PC ready (%s): press Scan, close the window to stop ===\n', ...
    R.dboard);

%% ================= R-B: FIGURE + CONTROLS ===============================
fig = figure('Position',[10 60 1920 900], 'Color','w', ...
    'Name','RX PC (X310) — PS-OFDM vs PS-AFDM image demo — close window to stop');
tl = tiledlayout(fig,3,5,'TileSpacing','tight','Padding','tight');
tl.OuterPosition = [0 0.055 1 0.945];
title(tl, ['RX PC: matched PS-OFDM vs PS-AFDM, per-symbol CE — one ' ...
    '84x84 image per frame, 16-QAM, N = 256 — demo by Dr. Hyeon Seok Rou'], ...
    'FontWeight','bold','FontSize',12);
tid = @(r,c) (r-1)*5 + c;
FS = 8;  W = 100;

% ---- row 1: common ------------------------------------------------------
axS1 = nexttile(tid(1,1)); hold(axS1,'on'); grid(axS1,'on');
hS1 = gobjects(1,2);
for w = 1:2, hS1(w) = plot(axS1,nan,nan,'-','Color',col(w,:)); end
ylim(axS1,[0 1.05]); xlim(axS1,[-1.7 0.3]); set(axS1,'FontSize',FS);
xlabel(axS1,'t - t_0 [ms]'); ylabel(axS1,'S&C metric');
title(axS1,'COMMON: STF plateau (coarse CFO)','FontSize',FS+1);
legend(axS1,hS1,{'OFDM','AFDM'},'Location','southwest','FontSize',FS-1);

axS2 = nexttile(tid(1,2)); hold(axS2,'on'); grid(axS2,'on');
hS2 = gobjects(1,2); hM2 = gobjects(1,2);
for w = 1:2
    hS2(w) = plot(axS2,nan,nan,'-','Color',col(w,:));
    hM2(w) = plot(axS2,0,nan,'v','Color',col(w,:), ...
                  'MarkerFaceColor',col(w,:),'MarkerSize',5);
end
ylim(axS2,[0 1]); xlim(axS2,[-2.5 2.5]); set(axS2,'FontSize',FS);
xlabel(axS2,'t - t_0 [ms]'); ylabel(axS2,'normalized corr');
title(axS2,'COMMON: ZC peaks (roots 25 / 34)','FontSize',FS+1);

axSp = nexttile(tid(1,3)); hold(axSp,'on'); grid(axSp,'on');
hSp = plot(axSp, nan, nan, 'Color', [0.3 0.3 0.6]);
xlim(axSp,[-500 500]); set(axSp,'FontSize',FS);
xlabel(axSp,'f [kHz]'); ylabel(axSp,'PSD [dB/Hz]');
title(axSp,'RX spectrum (full capture)','FontSize',FS+1);
arrayfun(@(v) xline(axSp, v/1e3, ':k', 'LineWidth', 1), band);

axE = nexttile(tid(1,4)); hold(axE,'on'); grid(axE,'on');
yyaxis(axE,'left');  hE = gobjects(1,2);
for w = 1:2, hE(w) = plot(axE,nan,nan,'-o','Color',col(w,:), ...
        'MarkerSize',3,'LineStyle','-','Marker','o'); end
ylabel(axE,'EVM [%]'); ylim(axE,[0 10]);
yyaxis(axE,'right'); hF = plot(axE,nan,nan,':k','Marker','.');
ylabel(axE,'CFO [Hz]');
xlabel(axE,'iteration'); set(axE,'FontSize',FS);
title(axE,'EVM (left) + CFO (right), rolling 100','FontSize',FS+1);

axP = nexttile(tid(1,5)); axis(axP,'off');
hPar = text(axP,-0.10,0.98,'starting...', 'FontName','FixedWidth', ...
    'FontSize',FS,'VerticalAlignment','top');

% ---- rows 2-3: per waveform ---------------------------------------------
[hC, hEs, hIm, hMt, axEsAx] = deal(gobjects(1,2));
for w = 1:2
    r = 1 + w;
    ax = nexttile(tid(r,1));
    hC(w) = plot(ax,nan,nan,'.','Color',col(w,:),'MarkerSize',4);
    grid(ax,'on'); set(ax,'DataAspectRatio',[1 1 1],'FontSize',FS);
    axis(ax,[-1.55 1.55 -1.55 1.55]); xlabel(ax,'I'); ylabel(ax,'Q');
    title(ax,sprintf('%s: equalized',name{w}),'FontSize',FS+1);

    ax = nexttile(tid(r,2)); hold(ax,'on'); grid(ax,'on');
    axEsAx(w) = ax;
    hEs(w) = plot(ax, 1:prms{w}.Nsym, nan(1,prms{w}.Nsym), '-o', ...
        'Color',col(w,:),'MarkerFaceColor',col(w,:),'MarkerSize',3);
    xlim(ax,[0.5 prms{w}.Nsym+0.5]); ylim(ax,[0 10]); set(ax,'FontSize',FS);
    xlabel(ax,'symbol index'); ylabel(ax,'EVM [%]');
    title(ax,'per-symbol EVM (per-symbol CE)','FontSize',FS+1);

    ax = nexttile(tid(r,4));
    hIm(w) = image(ax, zeros(S,S,3,'uint8')); axis(ax,'image'); axis(ax,'off');
    title(ax,sprintf('%s: received image',name{w}),'FontSize',FS+1);

    ax = nexttile(tid(r,5)); axis(ax,'off');
    hMt(w) = text(ax,-0.10,0.98,'waiting for burst...', ...
        'FontName','FixedWidth','FontSize',FS,'VerticalAlignment','top');
end
% (2,3) comb |H(k)| overlay
axHk = nexttile(tid(2,3)); hold(axHk,'on'); grid(axHk,'on');
N = prms{1}.Nfft;
cmapH = interp1([1 prms{1}.Nsym], [0.7 0.85 0.55; 0.15 0.35 0.05], ...
                1:prms{1}.Nsym);
hHk = gobjects(1,prms{1}.Nsym);
for sy = 1:prms{1}.Nsym
    hHk(sy) = plot(axHk, 0:N-1, nan(1,N), '-', 'Color', cmapH(sy,:));
end
xlim(axHk,[-1 N]); ylim(axHk,[-8 8]); set(axHk,'FontSize',FS);
xlabel(axHk,'DFT bin k'); ylabel(axHk,'|H(k)| [dB]');
title(axHk,'per-symbol |H(k)| overlaid','FontSize',FS+1);
% (3,3) EPA delay-Doppler grid
axDD = nexttile(tid(3,3));
leffA = prms{2}.ellmax + prms{2}.nBack;
hDD = imagesc(axDD, -prms{2}.fmax:prms{2}.fmax, ...
    -prms{2}.nBack:prms{2}.ellmax, nan(leffA+1, 2*prms{2}.fmax+1));
axis(axDD,'xy'); colorbar(axDD); clim(axDD,[-60 0]); set(axDD,'FontSize',FS);
xlabel(axDD,'Doppler tap f'); ylabel(axDD,'delay l [chips]');
title(axDD,'DD grid |h(l,f)| [dB], mean over symbols','FontSize',FS+1);

% ---- control strip ------------------------------------------------------
gain_ui(fig, [0.03 0.004 0.27 0.048], 'RX gain', 'rxGain', gRange, ...
    R.gainStep, P.rxGain);
hClip = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.32 0.006 0.26 0.042],'String','peak|y| —', ...
    'HorizontalAlignment','left','BackgroundColor','w', ...
    'FontSize',10,'FontWeight','bold');
ui = usrp_scan_ui(fig, [0.60 0.004 0.39 0.048], P, R);

%% ================= R-C: ENDLESS LOOP ====================================
evm = nan(2,0);  cfo = nan(2,0);
nOK = zeros(1,2);  nMiss = zeros(1,2);
errTot = zeros(1,2);  bitTot = zeros(1,2);
peakY = nan;  itTic = tic;  itS = nan;

rx = [];  dev = [];
u = 0;
while u < P.maxIter && ishandle(fig)
    % ---- radio (re)connect requested by the Scan strip ------------------
    req = getappdata(fig,'usrpReq');
    if ~isempty(req)
        setappdata(fig,'usrpReq',[]);
        [rx, dev] = connectRx(rx, req, P, R, fs, ...
            getappdata(fig,'rxGain'), fig, ui);
    end
    if isempty(rx)
        set(hPar,'String',sprintf('RX IDLE\n\nno radio connected\npress Scan'));
        pause(0.1);                               % keeps the GUI alive
        continue;
    end

    gR = getappdata(fig,'rxGain');
    if abs(rx.Gain - gR) > 1e-9, rx.Gain = gR; end

    try
        [y, len] = rx();
    catch e
        try release(rx); catch, end;  rx = [];  dev = [];  setappdata(fig,'usrpIP','');
        ui.setStatus(['radio lost: ' e.message ' -- press Scan'], 'err');
        continue;
    end
    u = u + 1;
    evm(:,u) = nan;  cfo(:,u) = nan;
    if len == 0, nMiss = nMiss + 1; drawnow limitrate; continue; end
    peakY = max(abs(y));
    yd = y .* exp(-1j*2*pi*fOff*(0:numel(y)-1).'/fs);

    [ppc, ffc] = pwelch(y, hann(1024), 512, 4096, fs, 'centered');
    set(hSp,'XData',ffc/1e3,'YData',10*log10(ppc));

    for w = 1:2
        det = false;
        try
            o = rxf{w}(yd, refs{w}, prms{w});
            if o.m > 0.6
                D = refs{w}.dataSyms;
                nErr = sum(o.bitsHat ~= C.bits);
                nOK(w) = nOK(w)+1;  errTot(w) = errTot(w)+nErr;
                bitTot(w) = bitTot(w)+nBits;
                evm(w,u) = o.evmPct;  cfo(w,u) = o.cfoHz;
                evmSym = 100*sqrt(mean(abs(o.dEq - D).^2,1) ./ ...
                                  mean(abs(D).^2,1));
                dsc = double(xor(o.bitsHat, pn));
                rgbHat = bits2img420(dsc(1:6*S^2), S);
                det = true;
            end
        catch
        end
        if ~det, nMiss(w) = nMiss(w)+1; continue; end

        t0 = o.t0;
        idxS = (1:numel(o.dbg.mS)).';
        selS = idxS > t0-1.7e-3*fs & idxS < t0+0.3e-3*fs;
        set(hS1(w),'XData',(idxS(selS)-t0)/fs*1e3,'YData',o.dbg.mS(selS));
        idxC = (1:numel(o.dbg.mCurve)).';
        selC = idxC > t0-2.5e-3*fs & idxC < t0+2.5e-3*fs;
        set(hS2(w),'XData',(idxC(selC)-t0)/fs*1e3, ...
                   'YData',o.dbg.mCurve(selC));
        set(hM2(w),'YData',o.m);
        set(hC(w),'XData',real(o.dEq(:)),'YData',imag(o.dEq(:)));
        set(hEs(w),'YData',evmSym);
        if max(evmSym) > max(ylim(axEsAx(w)))
            ylim(axEsAx(w),[0 ceil(max(evmSym)*1.2)]);
        end
        set(hIm(w),'CData',rgbHat);
        if w == 1
            for sy = 1:prms{1}.Nsym
                set(hHk(sy),'YData',20*log10(abs(o.Hsym(:,sy))));
            end
        else
            set(hDD,'CData',20*log10(o.ddGrid/max(o.ddGrid(:))+eps));
        end
        pxOK = 100*mean(all(rgbHat == C.rgb, 3), 'all');
        set(hMt(w),'String',sprintf([ ...
            '%s\n\nframes OK/missed %d/%d\n\n' ...
            'm    %.3f\nCFO  %+.0f Hz\nEVM  %.2f %% (SNR~ %.1f dB)\n\n' ...
            'frame BER    %.3g\nrunning BER  %.3g\nbits counted %d\n' ...
            'pixels exact %.1f %%\n\n~%.1f s / iteration'], ...
            name{w}, nOK(w), nMiss(w), o.m, cfo(w,u), ...
            evm(w,u), -20*log10(evm(w,u)/100), nErr/nBits, ...
            errTot(w)/max(bitTot(w),1), bitTot(w), pxOK, itS));
    end
    if ~ishandle(fig), break; end

    iw2 = max(1, u-W+1) : u;
    yyaxis(axE,'left');
    for w = 1:2, set(hE(w),'XData',iw2,'YData',evm(w,iw2)); end
    eAll = evm(:,iw2);
    if any(~isnan(eAll(:))) && max(eAll(:),[],'omitnan') > max(ylim(axE))
        ylim(axE,[0 ceil(max(eAll(:),[],'omitnan')*1.2)]);
    end
    yyaxis(axE,'right');
    set(hF,'XData',iw2,'YData',mean(cfo(:,iw2),1,'omitnan'));
    xlim(axE,[iw2(1)-1, iw2(end)+1]);
    set(hPar,'String',sprintf([ ...
        'PARAMS (contract)\n' ...
        'fc %.4g GHz | fs %g MS/s\nN 256 matched, Nsym 48, 16-QAM\n' ...
        'bits/frame %d (84x84 px)\nZC roots 25 / 34, scrambler 46\n' ...
        'image %s\nradio %s\n%s slot %s\n\niteration %d\n' ...
        'payload fixed (deterministic\ncontract), no backchannel'], ...
        P.fc/1e9, fs/1e6, nBits, C.imgFile, devStr(dev), R.dboard, ...
        char('A' + P.channel - 1), u));
    if ~isnan(peakY)
        if peakY > 0.7
            set(hClip,'String',sprintf( ...
                'peak|y| %.2f — CLIP RISK, lower a gain!',peakY), ...
                'ForegroundColor',[0.8 0 0]);
        else
            set(hClip,'String',sprintf('peak|y| %.2f (ok, < 0.7)',peakY), ...
                'ForegroundColor',[0 0.5 0]);
        end
    end
    itS = toc(itTic);  itTic = tic;
    drawnow limitrate;
end

%% ================= R-D: CLEANUP =========================================
if ~isempty(rx), release(rx); end
for w = 1:2
    fprintf(['[RX] %-14s: %d OK / %d missed, running BER %.3g over ' ...
        '%d bits\n'], name{w}, nOK(w), nMiss(w), ...
        errTot(w)/max(bitTot(w),1), bitTot(w));
end
out = struct('name',{name},'nOK',nOK,'nMiss',nMiss,'errTot',errTot, ...
    'bitTot',bitTot,'evm',evm,'cfo',cfo,'iters',u,'P',P);
if P.snapshot && ishandle(fig)
    fdir = fullfile(fileparts(mfilename('fullpath')), 'figures');
    if ~exist(fdir, 'dir'), mkdir(fdir); end
    png = fullfile(fdir, sprintf('rx_pc_panel_%s.png', ...
        char(datetime('now','Format','yyyyMMdd_HHmmss'))));
    exportgraphics(fig, png, 'Resolution', 150);
    fprintf('[RX] snapshot: %s\n', png);
end
if ishandle(fig) && isfinite(P.maxIter), close(fig); end

end

function [rx, dev] = connectRx(rx, dev, P, R, fs, g, fig, ui)
% (re)open the receiver on dev; the warm-up capture actually opens the radio
if ~isempty(rx), release(rx); end
rx = [];  setappdata(fig,'usrpIP','');
try
    rx = comm.SDRuReceiver('Platform',dev.Platform, ...
        'IPAddress',dev.IPAddress,'CenterFrequency',P.fc, ...
        'MasterClockRate',R.mcr,'DecimationFactor',R.mcr/fs, ...
        'Gain',g,'ChannelMapping',P.channel, ...
        'SamplesPerFrame',375000,'OutputDataType','double', ...
        'EnableBurstMode',true,'NumFramesInBurst',1);
    rx();                                            % warm-up, discard
catch e
    if ~isempty(rx), try release(rx); catch, end, end
    ui.setStatus(sprintf('connect to %s failed: %s', dev.IPAddress, ...
        e.message), 'err');
    rx = [];  dev = [];
    return;
end
setappdata(fig,'usrpIP',dev.IPAddress);
ui.setStatus(sprintf('connected: %s', devStr(dev)), 'ok');
fprintf('[RX] connected: %s\n', devStr(dev));
end

function s = devStr(dev)
if isempty(dev), s = 'none'; return; end
sn = dev.SerialNum;  if isempty(sn), sn = '-'; end
s = sprintf('%s %s SN %s', dev.Platform, dev.IPAddress, sn);
end
