%% =========================================================================
%  FILE:     tworadio_image_live.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Live image demo on ONE PC with TWO B210s. The image is split into
%    four quadrants; every quadrant is sent twice, once as comb-pilot
%    PS-OFDM and once as embedded-pilot PS-AFDM, so the two waveforms
%    carry identical bits over the same link and can be compared directly.
%    The panel shows the original, both equalised constellations, both
%    received images filling in quadrant by quadrant, and per-waveform
%    EVM / CFO / pixel-error / running BER. TX and RX gains are tunable
%    live, with an ADC clip canary. CLOSE THE WINDOW TO STOP.
%
%    Fixed 16-QAM: the pixel mapping is 4 bits per colour channel.
%
%  SAFETY:
%    Antenna link only, antennas >= 30 cm apart; txGain <= 80 asserted.
%    Cable loopback needs a 30 dB attenuator and txGain <= 55.
%
%  INPUTS:
%    P : struct -- .txSerial.rxSerial (B210 serials, required)
%        .imgFile ('dog.jpg') .fc (2.4e9) .txGain (58) .rxGain (56)
%        .pauseS (0, extra hold after each complete image)
%        .maxIter (Inf) .snapshot (save a panel PNG on exit)
%  OUTPUTS:
%    out : struct -- per-waveform totals (.nOK.nMiss .errTot .bitTot)
%
%  DEPENDENCIES:
%    img_load_quant, combofdm_params/build/rx,
%    stage5_params/afdm_build/afdm_rx
%    Communications Toolbox + USRP support package
% =========================================================================
function out = tworadio_image_live(P)

if nargin < 1, P = struct(); end
def = struct('txSerial','YOUR_TX_B210_SERIAL', ...
             'rxSerial','YOUR_RX_B210_SERIAL', ...
             'imgFile','dog.jpg', 'fc',2.4e9, 'txGain',58, 'rxGain',56, ...
             'pauseS',0, 'maxIter',Inf, 'snapshot',[]);
fn = fieldnames(def);
for i = 1:numel(fn)
    if ~isfield(P, fn{i}) || isempty(P.(fn{i})), P.(fn{i}) = def.(fn{i}); end
end
if isempty(P.snapshot), P.snapshot = isfinite(P.maxIter); end
assert(~contains([P.txSerial P.rxSerial],'YOUR_'), ['Set your two B210 ' ...
    'serial numbers in RUN_IMAGE_DEMO.m. Serials are listed by findsdru ' ...
    'in MATLAB or uhd_find_devices in a terminal.']);
assert(P.txGain <= 80, ['OTA safety: txGain %g > 80. Antenna link only, ' ...
    '>= 30 cm; never at cable loopback (<= 55 there).'], P.txGain);

%% ================= V-A: PARAMS, IMAGES, RADIOS ==========================
N = 256;
prmO = combofdm_params(N, 'matched');  prmO.useSTF = true;  prmO.Nsym = 24;
prmA = stage5_params(N, 'matched');    prmA.useSTF = true;  prmA.Nsym = 24;
prmO.NsymData = prmO.Nsym;  prmA.NsymData = prmA.Nsym;
assert(prmO.modOrder == 16 && prmA.modOrder == 16, ...
    'pixel mapping is 4 bpp: needs 16-QAM');
fs = prmA.fs;  M = prmA.M;  fOff = [240e3, 240e3];
Nd = numel(prmA.dataBins);
nBits = prmA.bps * Nd * prmA.Nsym;
side  = 42;  bpp = 12;  sideF = 2*side;
nImgB = side*side*bpp;
assert(nImgB <= nBits, 'quadrant exceeds frame budget');
qR = {1:side, 1:side, side+1:sideF, side+1:sideF};
qC = {1:side, side+1:sideF, 1:side, side+1:sideF};

% source image: center-cropped and resampled to sideF x sideF, then
% quantized to 4 bits per colour channel (the transmitted lattice)
root    = fileparts(fileparts(mfilename('fullpath')));
imgPath = fullfile(root, P.imgFile);
assert(exist(imgPath,'file') == 2, 'image not found: %s', imgPath);
img0 = img_load_quant(imgPath, sideF);
quad0 = img0(qR{1}, qC{1}, :);
assert(isequal(bits2img(img2bits(quad0), side), quad0), ...
    'bit<->pixel round trip failed');

% structural PN scrambler (seed 45): payload-independent TX power
rs = RandStream('mt19937ar', 'Seed', 45);
pn = randi(rs, [0 1], nBits, 1);

name = {'PS-OFDM comb', 'PS-AFDM EPA'};
col  = [0.466 0.674 0.188; 0.850 0.325 0.098];
bldf = {@combofdm_build, @stage5_afdm_build};
rxf  = {@combofdm_rx,    @stage5_afdm_rx};
prms = {prmO, prmA};
nRF  = @(x,f) x .* exp(1j*2*pi*f*(0:numel(x)-1).'/fs);

mcr = 16e6;
tx = comm.SDRuTransmitter('Platform','B210','SerialNum',P.txSerial, ...
    'CenterFrequency',P.fc,'MasterClockRate',mcr, ...
    'InterpolationFactor',mcr/fs,'Gain',P.txGain,'ChannelMapping',1);
rx = comm.SDRuReceiver('Platform','B210','SerialNum',P.rxSerial, ...
    'CenterFrequency',P.fc,'MasterClockRate',mcr, ...
    'DecimationFactor',mcr/fs,'Gain',P.rxGain,'ChannelMapping',1, ...
    'SamplesPerFrame',375000,'OutputDataType','double', ...
    'EnableBurstMode',true,'NumFramesInBurst',1);

fprintf('[IMGL] === IMAGE DEMO LIVE (%s): close the window to stop ===\n', ...
    P.imgFile);

%% ================= V-B: FIGURE + CONTROLS ==============================
fig = figure('Position',[10 60 1500 800],'Color','w', ...
    'Name','IMAGE LIVE — close window to stop');
tl = tiledlayout(fig,2,4,'TileSpacing','compact','Padding','compact');
tl.OuterPosition = [0 0.055 1 0.945];      % reserve strip for controls
title(tl, sprintf(['LIVE IMAGE OVER THE MATCHED LINK: %s vs %s — ' ...
    'RGB 4:4:4, uncoded — demo by Dr. Hyeon Seok Rou'], ...
    name{1}, name{2}), 'FontWeight','bold','FontSize',12);
FS = 9;

axOrig = nexttile(1,[2 1]);
image(axOrig, double(img0)/15); axis(axOrig,'image');
set(axOrig,'XTick',[],'YTick',[],'FontSize',FS);
title(axOrig,{sprintf('ORIGINAL: %s', P.imgFile), ...
    sprintf('%dx%d px RGB 4:4:4 = %d bits = 4 frames', ...
    sideF, sideF, 4*nImgB)}, 'FontSize',FS+1);

hC = gobjects(1,2);  hIm = gobjects(1,2);  axIm = gobjects(1,2);
hMt = gobjects(1,2);
for w = 1:2
    ax = nexttile(2 + (w-1)*4);
    hC(w) = plot(ax,nan,nan,'.','Color',col(w,:),'MarkerSize',3);
    grid(ax,'on'); set(ax,'DataAspectRatio',[1 1 1],'FontSize',FS);
    axis(ax,[-1.8 1.8 -1.8 1.8]);
    xlabel(ax,'I'); ylabel(ax,'Q');
    if strcmp(prmO.eqMode,'mmse'), eqO = 'per-bin MMSE + trunc CE';
    else, eqO = 'per-symbol ZF'; end
    eqn = {eqO,'per-symbol MMSE'};
    title(ax,sprintf('%s: equalized (%s)', name{w}, eqn{w}),'FontSize',FS+1);

    axIm(w) = nexttile(3 + (w-1)*4);
    hIm(w) = image(axIm(w), zeros(sideF,sideF,3)); axis(axIm(w),'image');
    set(axIm(w),'XTick',[],'YTick',[],'FontSize',FS);
    title(axIm(w),sprintf('%s: received', name{w}),'FontSize',FS+1);

    ax = nexttile(4 + (w-1)*4); axis(ax,'off');
    hMt(w) = text(ax,0,0.98,'starting...','FontName','FixedWidth', ...
        'FontSize',FS,'VerticalAlignment','top');
end

% --- control strip -------------------------------------------------------
setappdata(fig,'txGain',P.txGain);
setappdata(fig,'rxGain',P.rxGain);
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.14 0.028 0.16 0.020],'String', ...
    'TX gain (58 stressed / 70 clean, max 80)','HorizontalAlignment','left', ...
    'BackgroundColor','w');
sT = uicontrol(fig,'Style','slider','Units','normalized', ...
    'Position',[0.14 0.006 0.22 0.022],'Min',40,'Max',80, ...
    'Value',P.txGain,'SliderStep',[1 5]/40);
tT = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.365 0.006 0.035 0.022],'String',sprintf('%.1f',P.txGain), ...
    'BackgroundColor','w');
sT.Callback = @(s,~) gaincb(s, fig, tT, 'txGain', 80);
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.43 0.028 0.06 0.020],'String','RX gain', ...
    'HorizontalAlignment','left','BackgroundColor','w');
sR = uicontrol(fig,'Style','slider','Units','normalized', ...
    'Position',[0.43 0.006 0.22 0.022],'Min',20,'Max',76, ...
    'Value',P.rxGain,'SliderStep',[1 5]/56);
tR = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.655 0.006 0.035 0.022],'String',sprintf('%.1f',P.rxGain), ...
    'BackgroundColor','w');
sR.Callback = @(s,~) gaincb(s, fig, tR, 'rxGain', 76);
hClip = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.72 0.006 0.20 0.040],'String','peak|y| —', ...
    'HorizontalAlignment','left','BackgroundColor','w', ...
    'FontSize',10,'FontWeight','bold');

%% ================= V-C: ENDLESS LOOP ===================================
nOK = zeros(1,2);  nMiss = zeros(1,2);
errTot = zeros(1,2);  bitTot = zeros(1,2);
peakY = nan;  imTic = tic;  imS = nan;

% warm-up (TX transport rule: 18 + 35 + 2 ms = 55k <= ~61k tx buffer)
bitsW = xor([img2bits(quad0); randi([0 1], nBits-nImgB, 1)], pn);
xW = bldf{1}(double(bitsW), prms{1});
tx([zeros(round(0.018*fs),1); nRF(xW,fOff(1)); zeros(round(0.002*fs),1)]);
rx();

u = 0;
imHatW = {zeros(sideF,sideF,3,'uint8'), zeros(sideF,sideF,3,'uint8')};
while u < P.maxIter && ishandle(fig)
    u = u + 1;

    % ---- live controls (once per complete image) ----
    gT = getappdata(fig,'txGain');  gR = getappdata(fig,'rxGain');
    if abs(tx.Gain - gT) > 1e-9, tx.Gain = min(gT, 80); end
    if abs(rx.Gain - gR) > 1e-9, rx.Gain = gR; end

    evmQ = nan(4,2);  cfoQ = nan(4,2);  pxeW = nan(1,2);
    for q = 1:4                                % one 42x42 quadrant per frame
        quad = img0(qR{q}, qC{q}, :);
        bits = double(xor([img2bits(quad); ...
                           randi([0 1], nBits-nImgB, 1)], pn));
        for w = 1:2
            [xw, ref] = bldf{w}(bits, prms{w});
            xPad = [zeros(round(0.018*fs),1); nRF(xw,fOff(w)); ...
                    zeros(round(0.002*fs),1)];
            tx(xPad);
            [y,len] = rx();
            det = false;
            if len > 0
                peakY = max(abs(y));
                yd = y .* exp(-1j*2*pi*fOff(w)*(0:numel(y)-1).'/fs);
                try
                    o = rxf{w}(yd, ref, prms{w});
                    if o.m > 0.6, det = true; end
                catch
                end
            end
            if ~det, nMiss(w) = nMiss(w)+1; continue; end
            nOK(w) = nOK(w)+1;
            nErr = sum(o.bitsHat ~= bits);
            errTot(w) = errTot(w)+nErr;  bitTot(w) = bitTot(w)+nBits;
            evmQ(q,w) = o.evmPct;  cfoQ(q,w) = o.cfoHz;
            bitsHat = double(xor(o.bitsHat > 0, pn));     % descramble
            imHatW{w}(qR{q}, qC{q}, :) = bits2img(bitsHat(1:nImgB), side);
            pxWrong = any(imHatW{w} ~= img0, 3);
            pxeW(w) = mean(pxWrong(:));

            set(hC(w),'XData',real(o.dEq(:)),'YData',imag(o.dEq(:)));
            set(hIm(w),'CData',double(imHatW{w})/15);
            title(axIm(w),sprintf('%s: received - %d px wrong (%.2f%%)', ...
                name{w}, nnz(pxWrong), 100*pxeW(w)),'FontSize',FS+1);
            set(hMt(w),'String',sprintf([ ...
                '%s\n\nimage %d, quadrant %d/4\n' ...
                'TXg %.1f / RXg %.1f\nframes OK/missed %d/%d\n\n' ...
                'EVM   %.1f %%\nSNR~  %.1f dB (-20log10 EVM)\n' ...
                'CFO   %+.0f Hz\npixel errs %.2f %%\n\n' ...
                'running BER %.2e\nbits %d\n\n~%.1f s / image'], ...
                name{w}, u, q, tx.Gain, rx.Gain, ...
                nOK(w), nMiss(w), evmQ(q,w), -20*log10(evmQ(q,w)/100), ...
                cfoQ(q,w), 100*pxeW(w), errTot(w)/max(bitTot(w),1), ...
                bitTot(w), imS));
        end
        if ~ishandle(fig), break; end
        drawnow limitrate;                     % progressive quadrant fill
    end
    if ~ishandle(fig), break; end
    if ~isnan(peakY)
        if peakY > 0.7
            set(hClip,'String',sprintf('peak|y| %.2f — CLIP RISK, back off!', ...
                peakY),'ForegroundColor',[0.8 0 0]);
        else
            set(hClip,'String',sprintf('peak|y| %.2f (ok, < 0.7)', peakY), ...
                'ForegroundColor',[0 0.5 0]);
        end
    end
    imS = toc(imTic);  imTic = tic;
    drawnow;
    if P.pauseS > 0, pause(P.pauseS); end
end

%% ================= V-D: CLEANUP ========================================
release(tx); release(rx);
for w = 1:2
    fprintf('[IMGL] %-12s: %d OK / %d missed, running BER %.2e over %d bits\n', ...
        name{w}, nOK(w), nMiss(w), errTot(w)/max(bitTot(w),1), bitTot(w));
end
out = struct('name',{name},'nOK',nOK,'nMiss',nMiss,'errTot',errTot, ...
    'bitTot',bitTot,'images',u,'P',P);
if P.snapshot && ishandle(fig)
    fdir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'figures');
    if ~exist(fdir, 'dir'), mkdir(fdir); end
    png = fullfile(fdir, sprintf('image_demo_%s.png', ...
        char(datetime('now','Format','yyyyMMdd_HHmmss'))));
    exportgraphics(fig,png,'Resolution',150);
    fprintf('[IMGL] snapshot: %s\n', png);
end

end

function gaincb(s, fig, t, key, cap)
v = min(round(s.Value*4)/4, cap);
setappdata(fig, key, v); set(t, 'String', sprintf('%.1f', v));
end

% ---- bit <-> pixel mapping: RGB 4:4:4, pixel-major -------------------
function b = img2bits(img)
v = double(reshape(permute(img, [3 1 2]), [], 1));   % R,G,B per pixel
b = reshape(int2bit(v, 4), [], 1);
end

function img = bits2img(b, side)
v = bit2int(reshape(b, 4, []), 4);
img = uint8(permute(reshape(v, 3, side, side), [2 3 1]));
end
