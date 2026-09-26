%% =========================================================================
%  FILE:     usrp_scan.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    Finds the X300/X310 radios reachable from this PC. First a broadcast
%    discovery (findsdru); if that returns no X3xx, each address in
%    fallbackIPs is probed directly, which also finds a radio whose
%    broadcast reply is dropped by a firewall.
%
%  INPUTS:
%    fallbackIPs : cellstr of addresses to probe when the broadcast finds
%                  nothing (default: the X310 factory addresses)
%    platforms   : cellstr of accepted platforms (default {'X310','X300'})
%  OUTPUTS:
%    devs : struct array -- .Platform .IPAddress .SerialNum .Status
%           (Status 'Success' = free to use; see help findsdru for others)
%
%  DEPENDENCIES:
%    findsdru (Communications Toolbox Support Package for USRP Radio)
% =========================================================================
function devs = usrp_scan(fallbackIPs, platforms)

if nargin < 1 || isempty(fallbackIPs)
    fallbackIPs = {'192.168.10.2', '192.168.40.2', '192.168.30.2'};
end
if nargin < 2 || isempty(platforms), platforms = {'X310', 'X300'}; end

ws = warning('off', 'all');                 % findsdru warns per miss
cleanup = onCleanup(@() warning(ws));

devs = keep(findsdru('StatusOnly', false), platforms);
if isempty(devs)
    for k = 1:numel(fallbackIPs)
        devs = [devs, keep(findsdru(fallbackIPs{k}), platforms)]; %#ok<AGROW>
    end
end

end

function d = keep(a, platforms)
% only radios of an accepted platform that actually answered
d = struct('Platform',{}, 'IPAddress',{}, 'SerialNum',{}, 'Status',{});
for k = 1:numel(a)
    if any(strcmpi(a(k).Platform, platforms)) && ...
            ~any(strcmp(a(k).Status, {'Not responding', 'No devices found'}))
        d(end+1) = struct('Platform',upper(a(k).Platform), ... %#ok<AGROW>
            'IPAddress',a(k).IPAddress, 'SerialNum',a(k).SerialNum, ...
            'Status',a(k).Status);
    end
end
end
