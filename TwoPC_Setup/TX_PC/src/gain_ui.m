%% =========================================================================
%  FILE:     gain_ui.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    Live gain control: a label, a slider over [gMin gMax] and an edit box
%    for typing an exact value. Values are snapped to the hardware gain
%    step and clamped to the range; the current value lives in
%    appdata(fig,key), which the entry script's loop applies to the radio.
%
%  INPUTS:
%    fig   : figure handle
%    pos   : [x y w h] normalized position (label on top, slider below)
%    label : label text
%    key   : appdata name holding the gain [dB]
%    range : [gMin gMax] dB, gMax > gMin
%    step  : gain step [dB]
%    g0    : initial gain [dB]
%  OUTPUTS:
%    h : struct -- .slider .edit (handles)
%
%  DEPENDENCIES:
%    none
% =========================================================================
function h = gain_ui(fig, pos, label, key, range, step, g0)

x = pos(1);  y = pos(2);  w = pos(3);  hr = pos(4)/2;
snap = @(v) min(max(round(v/step)*step, range(1)), range(2));
g0 = snap(g0);
setappdata(fig, key, g0);

uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[x y+hr w hr],'String',sprintf('%s  [%g ... %g dB]', ...
    label, range(1), range(2)),'HorizontalAlignment','left', ...
    'BackgroundColor','w');
h.slider = uicontrol(fig,'Style','slider','Units','normalized', ...
    'Position',[x y 0.80*w hr],'Min',range(1),'Max',range(2), ...
    'Value',g0,'SliderStep',min([step 5*step]/diff(range), 1));
h.edit = uicontrol(fig,'Style','edit','Units','normalized', ...
    'Position',[x+0.82*w y 0.18*w hr],'String',sprintf('%.1f',g0), ...
    'TooltipString','type a gain in dB and press Enter');

h.slider.Callback = @(s,~) apply(s.Value);
h.edit.Callback   = @(e,~) apply(str2double(e.String));

    function apply(v)
        if isnan(v), v = getappdata(fig, key); end
        v = snap(v);
        setappdata(fig, key, v);
        set(h.slider, 'Value', v);
        set(h.edit, 'String', sprintf('%.1f', v));
    end
end
