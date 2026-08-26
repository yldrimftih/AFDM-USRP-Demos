%% =========================================================================
%  FILE:     tworadio_panel_live.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    LIVE, CONTINUOUS version of the two-radio native panel (comb PS-OFDM
%    vs EPA PS-AFDM, per-symbol CE both) with LIVE-TUNABLE controls:
%    QAM order (4 / 16 / 64), TX gain, RX gain — retuned without touching
%    the radios' streaming state. RX-side tiles only (TX spectrum dropped
%    to make room for the control strip; TX data is redundant with fresh
%    random payloads anyway). Runs until the window is closed.
%  INPUTS:
%    P : optional overrides — .N (256) .profile ('matched'|'native')
%        .modOrder (16) .fc (2.4e9) .txGain (70) .rxGain (56)
%        .maxIter (Inf; finite = bounded smoke-test hook)
%        .snapshot (finite-maxIter default: save PNG on exit)
%  OUTPUTS:
%    out : struct — totals per waveform (nOK, nMiss, errTot, bitTot)
%  DEPENDENCIES:
%    combofdm_params/build/rx, stage5_params, stage5_afdm_build,
%    stage5_afdm_rx (+ burst_sync)
% =========================================================================
function out = tworadio_panel_live(P)

if nargin < 1, P = struct(); end
def = struct('N',256, 'profile','matched', 'modOrder',16, 'fc',2.4e9, ...
             'txSerial','YOUR_TX_B210_SERIAL', ...
             'rxSerial','YOUR_RX_B210_SERIAL', ...
             'txGain',70, 'rxGain',56, 'maxIter',Inf, 'snapshot',[]);
fn = fieldnames(def);
for i = 1:numel(fn)
    if ~isfield(P, fn{i}) || isempty(P.(fn{i})), P.(fn{i}) = def.(fn{i}); end
end
if isempty(P.snapshot), P.snapshot = isfinite(P.maxIter); end
assert(~contains([P.txSerial P.rxSerial],'YOUR_'), ['Set your two B210 ' ...
    'serial numbers in RUN_PANEL_DEMO.m. Serials are listed by findsdru ' ...
    'in MATLAB or uhd_find_devices in a terminal.']);
assert(P.txGain <= 80, ['OTA safety: txGain %g > 80. Antenna link only, ' ...
    '>= 30 cm; never at cable loopback (<= 55 there).'], P.txGain);
N = P.N;

%% ================= L-A: PARAMS, RADIOS =================================
prmO = combofdm_params(N, P.profile);  prmO.useSTF = true;
prmA = stage5_params(N, P.profile);    prmA.useSTF = true;
prms = {prmO, prmA};
curQ = P.modOrder;
for w = 1:2
    prms{w}.modType = 'qam';  prms{w}.modOrder = curQ;
    prms{w}.bps = log2(curQ);
end
fs = prms{2}.fs;  M = prms{2}.M;  fOff = [240e3, 240e3];
NdO = numel(prms{1}.dataBins);  NdA = numel(prms{2}.dataBins);
nBits = log2(curQ) * [NdO*prms{1}.Nsym, NdA*prms{2}.Nsym];
bldf  = {@combofdm_build, @stage5_afdm_build};
rxf   = {@combofdm_rx,    @stage5_afdm_rx};
ovh   = [100*(numel(prms{1}.pilotBins)+numel(prms{1}.nullBins))/N, ...
         100*prms{2}.zoneLen/N];
name  = {'PS-OFDM comb', 'PS-AFDM EPA'};
col   = [0.466 0.674 0.188; 0.850 0.325 0.098];

% frame length + fixed TX buffer geometry (native-panel recipe: 60 ms
% lead + 10 ms tail; frame + tail << 61k airs after tx() returns)
bits = {randi([0 1],nBits(1),1), randi([0 1],nBits(2),1)};
[x0O, refO] = bldf{1}(bits{1}, prms{1});
[x0A, refA] = bldf{2}(bits{2}, prms{2});
refs = {refO, refA};  xw = {x0O, x0A};
Lfr  = [refO.chipIdx(end) + prms{1}.gd + M, ...
        refA.chipIdx(end) + prms{2}.gd + M];
band = {fOff(1) + [-1 1]*(1+prms{1}.beta)*(fs/M)/2, ...
        fOff(2) + [-1 1]*(1+prms{2}.beta)*(fs/M)/2};
nRF  = @(x,f) x .* exp(1j*2*pi*f*(0:numel(x)-1).'/fs);
padF = @(x,f) [zeros(round(0.06*fs),1); nRF(x,f); zeros(round(0.01*fs),1)];
Lpad = max(numel(padF(x0O,fOff(1))), numel(padF(x0A,fOff(2))));

mcr = 16e6;
tx = comm.SDRuTransmitter('Platform','B210','SerialNum',P.txSerial, ...
    'CenterFrequency',P.fc,'MasterClockRate',mcr, ...
    'InterpolationFactor',mcr/fs,'Gain',P.txGain,'ChannelMapping',1);
rx = comm.SDRuReceiver('Platform','B210','SerialNum',P.rxSerial, ...
    'CenterFrequency',P.fc,'MasterClockRate',mcr, ...
    'DecimationFactor',mcr/fs,'Gain',P.rxGain,'ChannelMapping',1, ...
    'SamplesPerFrame',262144,'OutputDataType','double', ...
    'EnableBurstMode',true,'NumFramesInBurst',1);

fprintf('[LIVE] === PANEL LIVE, N = %d [%s]: close the window to stop ===\n', ...
    N, upper(P.profile));

%% ================= L-B: FIGURE + CONTROLS ==============================
fig = figure('Position',[10 60 1920 900], 'Color','w', ...
    'Name',sprintf('PANEL LIVE N=%d [%s] — close window to stop', ...
    N, upper(P.profile)));
tl = tiledlayout(fig,3,5,'TileSpacing','tight','Padding','tight');
tl.OuterPosition = [0 0.055 1 0.945];      % reserve strip for controls
title(tl, sprintf(['TWO-RADIO LIVE PANEL: %s vs %s (N = %d, %s) — ' ...
    'per-symbol CE both — demo by Dr. Hyeon Seok Rou'], ...
    name{1}, name{2}, N, upper(P.profile)), 'FontWeight','bold','FontSize',12);
tid = @(r,c) (r-1)*5 + c;
bandlines = @(ax,b) arrayfun(@(v) xline(ax,v/1e3,':k','LineWidth',1), b);
FS = 8;  W = 100;                          % rolling history window

% ---------------- ROW 1: COMMON -----------------------------------------
axS1 = nexttile(tid(1,1)); hold(axS1,'on'); grid(axS1,'on');
hS1 = gobjects(1,2);
for w = 1:2, hS1(w) = plot(axS1,nan,nan,'-','Color',col(w,:)); end
ylim(axS1,[0 1.05]); xlim(axS1,[-1.7 0.3]); set(axS1,'FontSize',FS);
xlabel(axS1,'t - t_0 [ms]'); ylabel(axS1,'S&C metric');
title(axS1,'COMMON: STF plateau (stage 0)','FontSize',FS+1);
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
title(axS2,'COMMON: ZC peak (stage 1)','FontSize',FS+1);

axE = nexttile(tid(1,3)); hold(axE,'on'); grid(axE,'on');
hE = gobjects(1,2);
for w = 1:2, hE(w) = plot(axE,nan,nan,'-o','Color',col(w,:),'MarkerSize',3); end
xlabel(axE,'iteration'); ylabel(axE,'EVM [%]'); set(axE,'FontSize',FS);
ylim(axE,[0 10]);
title(axE,'COMMON: EVM history (rolling 100)','FontSize',FS+1);

axF = nexttile(tid(1,4)); hold(axF,'on'); grid(axF,'on');
hF = gobjects(1,2);
for w = 1:2, hF(w) = plot(axF,nan,nan,'-o','Color',col(w,:),'MarkerSize',3); end
xlabel(axF,'iteration'); ylabel(axF,'CFO [Hz]'); set(axF,'FontSize',FS);
title(axF,'COMMON: measured CFO','FontSize',FS+1);

axP = nexttile(tid(1,5)); axis(axP,'off');
text(axP,-0.10,0.98,sprintf([ ...
    'PARAMS [%s]\n' ...
    'fc %.4g GHz | fs %g MS/s\n%g kchip/s (M %d)\n' ...
    'N %d, CP %d, Nsym %d both\n\n' ...
    'OFDM comb: %d pilots + %d nulls/sym\nAFDM EPA:  zone %d bins\n' ...
    'overhead %.1f%% vs %.1f%%\n\n' ...
    'gains: 70/56 clean, 58/56 stressed\n' ...
    '64-QAM point: 75/50\n' ...
    'CLIP CANARY: keep peak|y| < 0.7'], ...
    upper(P.profile), P.fc/1e9, fs/1e6, fs/M/1e3, M, N, prms{2}.Ncp, ...
    prms{2}.Nsym, numel(prms{1}.pilotBins), numel(prms{1}.nullBins), ...
    prms{2}.zoneLen, ovh(1), ovh(2)), ...
    'FontName','FixedWidth','FontSize',FS,'VerticalAlignment','top');

% ---------------- ROWS 2-3: PER WAVEFORM (RX side only) ------------------
hRX = gobjects(1,2);  hC = gobjects(1,2);  hEs = gobjects(1,2);
hMt = gobjects(1,2);  axEsAx = gobjects(1,2);
for w = 1:2
    r = 1 + w;
    ax = nexttile(tid(r,1));
    hRX(w) = plot(ax,nan,nan,'Color',col(w,:)); grid(ax,'on');
    xlim(ax,[-500 500]); ylim(ax,[-115 -40]); set(ax,'FontSize',FS);
    xlabel(ax,'f [kHz]'); ylabel(ax,'PSD [dB/Hz]');
    title(ax,sprintf('%s: RX spectrum (live)',name{w}),'FontSize',FS+1);
    bandlines(ax,band{w});

    ax = nexttile(tid(r,2));
    ax.Tag = 'const';
    hC(w) = plot(ax,nan,nan,'.','Color',col(w,:),'MarkerSize',4);
    grid(ax,'on'); set(ax,'DataAspectRatio',[1 1 1]);
    axis(ax,[-1.55 1.55 -1.55 1.55]);      % square 1:1 (IQ)
    set(ax,'FontSize',FS); xlabel(ax,'I'); ylabel(ax,'Q');
    if w == 1
        if strcmp(prms{1}.eqMode,'mmse'), eqO = 'per-bin MMSE'; else, eqO = 'per-symbol ZF'; end
        title(ax,sprintf('equalized (%s)',eqO),'FontSize',FS+1);
    else
        title(ax,'equalized (per-symbol MMSE)','FontSize',FS+1);
    end

    % col 3: channel view (per waveform, set below)
    ax = nexttile(tid(r,4)); hold(ax,'on'); grid(ax,'on');
    axEsAx(w) = ax;
    hEs(w) = plot(ax, 1:prms{w}.Nsym, nan(1,prms{w}.Nsym), '-o', ...
        'Color',col(w,:),'MarkerFaceColor',col(w,:),'MarkerSize',4);
    xlim(ax,[0.5 prms{w}.Nsym+0.5]); ylim(ax,[0 10]); set(ax,'FontSize',FS);
    xlabel(ax,'symbol index'); ylabel(ax,'EVM [%]');
    title(ax,'per-symbol EVM (one CE each)','FontSize',FS+1);

    ax = nexttile(tid(r,5)); axis(ax,'off');
    hMt(w) = text(ax,-0.10,0.98,'starting...','FontName','FixedWidth', ...
        'FontSize',FS,'VerticalAlignment','top');
end
% row 2 col 3: per-symbol |H(k)| overlay (OFDM comb)
axHk = nexttile(tid(2,3)); hold(axHk,'on'); grid(axHk,'on');
cmapH = interp1([1 prms{1}.Nsym], [0.7 0.85 0.55; 0.15 0.35 0.05], ...
                1:prms{1}.Nsym);
hHk = gobjects(1,prms{1}.Nsym);
for sy = 1:prms{1}.Nsym
    hHk(sy) = plot(axHk, 0:N-1, nan(1,N), '-', 'Color', cmapH(sy,:));
end
xlim(axHk,[-1 N]); ylim(axHk,[-8 8]); set(axHk,'FontSize',FS);
xlabel(axHk,'DFT bin k'); ylabel(axHk,'|H(k)| [dB]');
title(axHk,'per-symbol |H(k)| overlaid','FontSize',FS+1);
% row 3 col 3: EPA DD grid
axDD = nexttile(tid(3,3));
leffA = prms{2}.ellmax + prms{2}.nBack;
hDD = imagesc(axDD, -prms{2}.fmax:prms{2}.fmax, -prms{2}.nBack:prms{2}.ellmax, ...
    nan(leffA+1, 2*prms{2}.fmax+1));
axis(axDD,'xy'); colorbar(axDD); clim(axDD,[-60 0]); set(axDD,'FontSize',FS);
xlabel(axDD,'Doppler tap f'); ylabel(axDD,'delay l [chips]');
title(axDD,'DD grid |h(l,f)| [dB], mean over symbols','FontSize',FS+1);
for a = findall(fig,'Type','axes','Tag','const').'
    set(a, 'PlotBoxAspectRatio', [1 1 1]);
end

% --- control strip (figure-normalized, below the tiles) -----------------
setappdata(fig, 'txGain', P.txGain);
setappdata(fig, 'rxGain', P.rxGain);
setappdata(fig, 'modOrder', curQ);
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.02 0.028 0.06 0.020],'String','QAM order', ...
    'HorizontalAlignment','left','BackgroundColor','w');
pQ = uicontrol(fig,'Style','popupmenu','Units','normalized', ...
    'Position',[0.02 0.006 0.06 0.022],'String',{'4','16','64'}, ...
    'Value',find([4 16 64]==curQ,1));
pQ.Callback = @(s,~) setappdata(fig,'modOrder', ...
    [4 16 64]*((1:3)==s.Value).');
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.11 0.028 0.14 0.020],'String', ...
    'TX gain (max 80, ANTENNA LINK ONLY)','HorizontalAlignment','left', ...
    'BackgroundColor','w');
sT = uicontrol(fig,'Style','slider','Units','normalized', ...
    'Position',[0.11 0.006 0.22 0.022],'Min',40,'Max',80, ...
    'Value',P.txGain,'SliderStep',[1 5]/40);
tT = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.335 0.006 0.035 0.022],'String',sprintf('%.1f',P.txGain), ...
    'BackgroundColor','w');
sT.Callback = @(s,~) gaincb(s, fig, tT, 'txGain', 80);
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.40 0.028 0.06 0.020],'String','RX gain', ...
    'HorizontalAlignment','left','BackgroundColor','w');
sR = uicontrol(fig,'Style','slider','Units','normalized', ...
    'Position',[0.40 0.006 0.22 0.022],'Min',20,'Max',76, ...
    'Value',P.rxGain,'SliderStep',[1 5]/56);
tR = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.625 0.006 0.035 0.022],'String',sprintf('%.1f',P.rxGain), ...
    'BackgroundColor','w');
sR.Callback = @(s,~) gaincb(s, fig, tR, 'rxGain', 76);
hClip = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.70 0.006 0.20 0.040],'String','peak|y| —', ...
    'HorizontalAlignment','left','BackgroundColor','w', ...
    'FontSize',10,'FontWeight','bold');

%% ================= L-C: ENDLESS LOOP ===================================
evm = nan(2,0);  cfo = nan(2,0);
nOK = zeros(1,2);  nMiss = zeros(1,2);
errTot = zeros(1,2);  bitTot = zeros(1,2);
peakY = nan;  itTic = tic;  itS = nan;

tx(padz(padF(xw{1},fOff(1)),Lpad)); rx();      % warm-up, discard
u = 0;
while u < P.maxIter && ishandle(fig)
    u = u + 1;

    % ---- live controls ----
    gT = getappdata(fig,'txGain');  gR = getappdata(fig,'rxGain');
    if abs(tx.Gain - gT) > 1e-9, tx.Gain = min(gT, 80); end
    if abs(rx.Gain - gR) > 1e-9, rx.Gain = gR; end
    qNew = getappdata(fig,'modOrder');
    if qNew ~= curQ                            % QAM switch: rebuild, reset
        curQ = qNew;
        for w = 1:2
            prms{w}.modOrder = curQ;  prms{w}.bps = log2(curQ);
        end
        nBits = log2(curQ) * [NdO*prms{1}.Nsym, NdA*prms{2}.Nsym];
        nOK(:) = 0;  nMiss(:) = 0;  errTot(:) = 0;  bitTot(:) = 0;
        xline(axE, u, ':k', sprintf('QAM-%d', curQ), 'FontSize', FS-1);
        fprintf('[LIVE] iteration %d: switched to QAM-%d (counters reset)\n', ...
            u, curQ);
    end

    evm(:,u) = nan;  cfo(:,u) = nan;
    for w = 1:2
        bits{w} = randi([0 1], nBits(w), 1);   % fresh payload (PAPR lottery)
        [xw{w}, refs{w}] = bldf{w}(bits{w}, prms{w});
        tx(padz(padF(xw{w},fOff(w)),Lpad));
        [y,len] = rx();
        det = false;
        if len > 0
            peakY = max(abs(y));
            yd = y .* exp(-1j*2*pi*fOff(w)*(0:numel(y)-1).'/fs);
            try
                o = rxf{w}(yd, refs{w}, prms{w});
                if o.m > 0.6
                    nErr = sum(o.bitsHat ~= bits{w});
                    nOK(w) = nOK(w)+1;  errTot(w) = errTot(w)+nErr;
                    bitTot(w) = bitTot(w)+nBits(w);
                    evm(w,u) = o.evmPct;  cfo(w,u) = o.cfoHz;
                    det = true;
                end
            catch
            end
        end
        if ~det, nMiss(w) = nMiss(w)+1; continue; end

        t0 = o.t0;
        idxS = (1:numel(o.dbg.mS)).';
        selS = idxS > t0-1.7e-3*fs & idxS < t0+0.3e-3*fs;
        set(hS1(w),'XData',(idxS(selS)-t0)/fs*1e3,'YData',o.dbg.mS(selS));
        idxC = (1:numel(o.dbg.mCurve)).';
        selC = idxC > t0-2.5e-3*fs & idxC < t0+2.5e-3*fs;
        set(hS2(w),'XData',(idxC(selC)-t0)/fs*1e3,'YData',o.dbg.mCurve(selC));
        set(hM2(w),'YData',o.m);
        seg  = yd(t0 : min(t0+Lfr(w)-1, numel(yd)));
        segR = seg .* exp(1j*2*pi*fOff(w)*(0:numel(seg)-1).'/fs);
        [pp,ff] = pwelch(segR,hann(1024),512,4096,fs,'centered');
        set(hRX(w),'XData',ff/1e3,'YData',10*log10(pp));
        set(hC(w),'XData',real(o.dEq(:)),'YData',imag(o.dEq(:)));
        set(hEs(w),'YData',o.evmSym);
        if max(o.evmSym) > max(ylim(axEsAx(w)))
            ylim(axEsAx(w),[0 ceil(max(o.evmSym)*1.2)]);
        end
        if w == 1
            for sy = 1:prms{1}.Nsym
                set(hHk(sy),'YData',20*log10(abs(o.Hsym(:,sy))));
            end
        else
            set(hDD,'CData',20*log10(o.ddGrid/max(o.ddGrid(:))+eps));
        end
        set(hMt(w),'String',sprintf([ ...
            '%s  [QAM-%d]\n\niteration %d\nframes OK/missed %d/%d\n\n' ...
            'm    %.3f\nCFO  %+.0f Hz\nEVM  %.2f %% (SNR~ %.1f dB)\n\n' ...
            'frame BER    %.3g\nrunning BER  %.3g\nbits counted %d\n\n' ...
            '~%.1f s / iteration'], ...
            name{w}, curQ, u, nOK(w), nMiss(w), o.m, cfo(w,u), ...
            evm(w,u), -20*log10(evm(w,u)/100), nErr/nBits(w), ...
            errTot(w)/max(bitTot(w),1), bitTot(w), itS));
    end
    if ~ishandle(fig), break; end

    % ---- rolling histories + canary ----
    iw = max(1, u-W+1) : u;
    for w = 1:2
        set(hE(w),'XData',iw,'YData',evm(w,iw));
        set(hF(w),'XData',iw,'YData',cfo(w,iw));
    end
    xlim(axE,[iw(1)-1, iw(end)+1]); xlim(axF,[iw(1)-1, iw(end)+1]);
    eAll = evm(:,iw);
    if any(~isnan(eAll(:))) && max(eAll(:),[],'omitnan') > max(ylim(axE))
        ylim(axE,[0 ceil(max(eAll(:),[],'omitnan')*1.2)]);
    end
    cAll = cfo(:,iw);
    if any(~isnan(cAll(:)))
        ylim(axF,[min(cAll(:),[],'omitnan')-20, max(cAll(:),[],'omitnan')+20]);
    end
    if ~isnan(peakY)
        if peakY > 0.7
            set(hClip,'String',sprintf('peak|y| %.2f — CLIP RISK, back off!', ...
                peakY),'ForegroundColor',[0.8 0 0]);
        else
            set(hClip,'String',sprintf('peak|y| %.2f (ok, < 0.7)', peakY), ...
                'ForegroundColor',[0 0.5 0]);
        end
    end
    itS = toc(itTic);  itTic = tic;
    drawnow limitrate;
end

%% ================= L-D: CLEANUP ========================================
release(tx); release(rx);
for w = 1:2
    fprintf('[LIVE] %-14s: %d OK / %d missed, running BER %.3g over %d bits\n', ...
        name{w}, nOK(w), nMiss(w), errTot(w)/max(bitTot(w),1), bitTot(w));
end
out = struct('name',{name},'nOK',nOK,'nMiss',nMiss,'errTot',errTot, ...
    'bitTot',bitTot,'evm',evm,'cfo',cfo,'iters',u,'P',P);
if P.snapshot && ishandle(fig)
    fdir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'figures');
    if ~exist(fdir, 'dir'), mkdir(fdir); end
    png = fullfile(fdir, sprintf('panel_demo_%s.png', ...
        char(datetime('now','Format','yyyyMMdd_HHmmss'))));
    exportgraphics(fig,png,'Resolution',150);
    fprintf('[LIVE] snapshot: %s\n', png);
end

end

function gaincb(s, fig, t, key, cap)
v = min(round(s.Value*4)/4, cap);
setappdata(fig, key, v); set(t, 'String', sprintf('%.1f', v));
end

function xp = padz(x, L)
xp = [x; zeros(L - numel(x), 1)];
end
