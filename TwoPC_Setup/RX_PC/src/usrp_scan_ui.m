%% =========================================================================
%  FILE:     usrp_scan_ui.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    Radio-selection strip for the entry scripts: [Scan] [device list]
%    [Connect] plus a status line. Scan runs usrp_scan; if exactly one
%    usable X310 is found it is selected automatically, otherwise the
%    user picks one from the list and presses Connect.
%
%    The strip never opens a radio itself. A selection is posted as
%    appdata(fig,'usrpReq') (a findsdru-style device struct) and the entry
%    script's loop opens it, so the radio object is only ever touched by
%    that loop. The loop reports back through ui.setStatus and stores the
%    address it holds in appdata(fig,'usrpIP').
%
%  INPUTS:
%    fig : figure handle
%    pos : [x y w h] normalized position of the strip
%    P   : entry-script params -- .scanIPs .autoScan .ipAddress
%    R   : x310_profile struct (accepted platforms)
%  OUTPUTS:
%    ui : struct -- .scan .list .conn .status (handles),
%         .setStatus(msg, level)  level 'ok' | 'warn' | 'err'
%
%  DEPENDENCIES:
%    usrp_scan
% =========================================================================
function ui = usrp_scan_ui(fig, pos, P, R)

x = pos(1);  y = pos(2);  w = pos(3);  hr = pos(4)/2;
ui.scan = uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[x y+hr 0.16*w hr],'String','Scan','FontWeight','bold', ...
    'TooltipString','search the network for X310 radios');
ui.list = uicontrol(fig,'Style','popupmenu','Units','normalized', ...
    'Position',[x+0.17*w y+hr 0.66*w hr],'String',{'(press Scan)'});
ui.conn = uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[x+0.84*w y+hr 0.16*w hr],'String','Connect', ...
    'TooltipString','connect to the radio selected in the list');
ui.status = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[x y w hr],'String','',  ...
    'HorizontalAlignment','left','BackgroundColor','w','FontWeight','bold');
ui.setStatus = @(msg, level) set(ui.status, 'String', msg, ...
    'ForegroundColor', levelColor(level));
ui.setStatus('no radio: press Scan', 'warn');

setappdata(fig,'usrpDevs',[]);
setappdata(fig,'usrpReq',[]);
setappdata(fig,'usrpIP','');
ui.scan.Callback = @(~,~) doScan(fig, ui, P, R);
ui.conn.Callback = @(~,~) doConnect(fig, ui);

if ~isempty(P.ipAddress)                    % explicit address: no scan
    setappdata(fig,'usrpReq', struct('Platform',R.platforms{1}, ...
        'IPAddress',P.ipAddress, 'SerialNum','', 'Status','Success'));
    ui.setStatus(sprintf('connecting to %s ...', P.ipAddress), 'warn');
elseif P.autoScan
    doScan(fig, ui, P, R);
end

end

% -------------------------------------------------------------------------
function doScan(fig, ui, P, R)
ui.setStatus('scanning the network for X310 radios ...', 'warn');
set([ui.scan ui.conn], 'Enable', 'off');  drawnow;
try
    devs = usrp_scan(P.scanIPs, R.platforms);
catch e
    set([ui.scan ui.conn], 'Enable', 'on');
    ui.setStatus(['scan failed: ' e.message], 'err');
    return;
end
set([ui.scan ui.conn], 'Enable', 'on');
if ~ishandle(fig), return; end
setappdata(fig,'usrpDevs',devs);
cur = getappdata(fig,'usrpIP');

if isempty(devs)
    set(ui.list, 'String', {'(no X310 found)'}, 'Value', 1);
    ui.setStatus(['no X310 found: check the Ethernet cable, this PC''s ' ...
        'address (e.g. 192.168.10.1/24 for the radio at 192.168.10.2) ' ...
        'and the firewall'], 'err');
    return;
end

lbl = cell(1, numel(devs));
for k = 1:numel(devs)
    st = devs(k).Status;
    if strcmp(devs(k).IPAddress, cur), st = 'connected'; end
    lbl{k} = sprintf('%s  %s  SN %s  [%s]', devs(k).Platform, ...
        devs(k).IPAddress, devs(k).SerialNum, st);
end
set(ui.list, 'String', lbl, 'Value', 1);

if numel(devs) == 1
    doConnect(fig, ui);                      % the only radio: take it
else
    ui.setStatus(sprintf(['%d radios found: pick one in the list and ' ...
        'press Connect'], numel(devs)), 'warn');
end
end

function doConnect(fig, ui)
devs = getappdata(fig,'usrpDevs');
if isempty(devs), ui.setStatus('no radio: press Scan', 'warn'); return; end
dev = devs(min(ui.list.Value, numel(devs)));
if strcmp(dev.IPAddress, getappdata(fig,'usrpIP'))
    ui.setStatus(sprintf('already connected to %s', dev.IPAddress), 'ok');
elseif ~strcmp(dev.Status, 'Success')
    ui.setStatus(statusHint(dev), 'err');
else
    setappdata(fig,'usrpReq',dev);
    ui.setStatus(sprintf('connecting to %s %s ...', dev.Platform, ...
        dev.IPAddress), 'warn');
end
end

function s = statusHint(dev)
switch dev.Status
    case 'Not compatible'
        s = sprintf(['%s: FPGA image does not match MATLAB''s UHD. Run ' ...
            'sdruload(''Device'',''x310'',''IPAddress'',''%s''), then ' ...
            'power-cycle the radio'], dev.IPAddress, dev.IPAddress);
    case 'Busy'
        s = sprintf(['%s is in use by another program or MATLAB ' ...
            'session: close it and Scan again'], dev.IPAddress);
    otherwise
        s = sprintf('%s: %s (see help findsdru)', dev.IPAddress, dev.Status);
end
end

function c = levelColor(level)
switch level
    case 'ok',   c = [0 0.5 0];
    case 'err',  c = [0.8 0 0];
    otherwise,   c = [0.75 0.4 0];
end
end
