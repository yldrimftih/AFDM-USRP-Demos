%% =========================================================================
%  FILE:     x310_profile.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    Hardware limits of an Ettus X300/X310 with the given daughterboard:
%    master clock rate, gain range and step, tunable frequency range. The
%    entry scripts clamp every user-set gain limit to these values and
%    check the carrier against the daughterboard's frequency range.
%
%  INPUTS:
%    dboard : 'CBX-120' (default) | 'UBX-160' | 'SBX-120'
%  OUTPUTS:
%    R : struct -- .dboard .mcr .txGain .rxGain ([min max] dB) .gainStep
%        .fRange ([min max] Hz) .platforms (accepted findsdru platforms)
%        .fsOpts (selectable sample rates [S/s]; each divides mcr)
%        .rfNames ({'RF0','RF1'} = ChannelMapping 1 / 2 = slot A / B)
%
%  DEPENDENCIES:
%    none
% =========================================================================
function R = x310_profile(dboard)

if nargin < 1 || isempty(dboard), dboard = 'CBX-120'; end
switch upper(dboard)
    case 'CBX-120', fRange = [1.2e9 6e9];
    case 'UBX-160', fRange = [10e6  6e9];
    case 'SBX-120', fRange = [400e6 4.4e9];
    otherwise
        error('x310_profile: unknown daughterboard ''%s'' (CBX-120, UBX-160, SBX-120)', ...
            dboard);
end

% 200 MHz is the X310 default master clock; 184.32 MHz does not divide
% the offered sample rates, so it is not used.
% Sample rates offered in the GUI. The waveform is defined in samples
% (5 samples/chip), so the occupied bandwidth is 0.27*fs: 135 kHz ...
% 2.7 MHz. 10 MS/s (40 MB/s) is well inside 1 GbE.
R = struct('dboard',upper(dboard), 'mcr',200e6, ...
    'txGain',[0 31.5], 'rxGain',[0 31.5], 'gainStep',0.5, ...
    'fRange',fRange, 'platforms',{{'X310','X300'}}, ...
    'fsOpts',[0.5 1 2 5 10]*1e6, 'rfNames',{{'RF0','RF1'}});

end
