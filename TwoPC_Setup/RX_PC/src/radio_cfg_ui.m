%% =========================================================================
%  FILE:     radio_cfg_ui.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    Run-time radio settings strip: [Bandwidth] and [RF0 / RF1] popups.
%    Like the Scan strip it never touches the radio: a change is posted as
%    appdata(fig,'cfgReq') = struct('fs',..,'rf',..) and the entry
%    script's loop re-opens the radio with it. Both settings must be the
%    same on the TX and the RX PC (bandwidth) -- the RF choice is local.
%
%  INPUTS:
%    fig  : figure handle
%    pos  : [x y w h] normalized position of the strip
%    R    : x310_profile struct (.fsOpts .rfNames)
%    bwF  : occupied bandwidth / fs of the waveform ((1+beta)/M)
%    fs0  : initial sample rate (must be in R.fsOpts)
%    rf0  : initial RF ('RF0' | 'RF1')
%  OUTPUTS:
%    h : struct -- .bw .rf (popup handles)
%
%  DEPENDENCIES:
%    none
% =========================================================================
function h = radio_cfg_ui(fig, pos, R, bwF, fs0, rf0)

x = pos(1);  y = pos(2);  w = pos(3);  hh = pos(4);
lbl = arrayfun(@(f) sprintf('%s  (%g MS/s)', bwStr(bwF*f), f/1e6), ...
    R.fsOpts, 'UniformOutput', false);
setappdata(fig, 'cfgReq', []);

uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[x y 0.18*w 0.8*hh],'String','Bandwidth:', ...
    'HorizontalAlignment','right','BackgroundColor','w','FontWeight','bold');
h.bw = uicontrol(fig,'Style','popupmenu','Units','normalized', ...
    'Position',[x+0.19*w y 0.37*w hh],'String',lbl, ...
    'Value',find(R.fsOpts == fs0, 1), ...
    'TooltipString','occupied bandwidth (sample rate); must match the other PC');
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[x+0.57*w y 0.10*w 0.8*hh],'String','RF:', ...
    'HorizontalAlignment','right','BackgroundColor','w','FontWeight','bold');
h.rf = uicontrol(fig,'Style','popupmenu','Units','normalized', ...
    'Position',[x+0.68*w y 0.32*w hh],'String',R.rfNames, ...
    'Value',find(strcmp(R.rfNames, rf0), 1), ...
    'TooltipString','RF0 = daughterboard slot A, RF1 = slot B');

post = @(~,~) setappdata(fig, 'cfgReq', struct( ...
    'fs', R.fsOpts(h.bw.Value), 'rf', R.rfNames{h.rf.Value}));
h.bw.Callback = post;
h.rf.Callback = post;

end

function s = bwStr(b)
if b >= 1e6, s = sprintf('%g MHz', b/1e6); else, s = sprintf('%g kHz', b/1e3); end
end
