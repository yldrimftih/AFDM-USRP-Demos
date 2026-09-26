%% =========================================================================
%  FILE:     RUN_RX_PC.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    One-click launcher for the RX PC: runs SELFTEST (no radio needed),
%    then starts RX_PC_MAIN. Start RUN_TX_PC.m on the TX PC first, then
%    open this file and press Run, then press Scan in the window.
%
%  DEPENDENCIES:
%    SELFTEST.m, RX_PC_MAIN.m (same folder)
% =========================================================================

cd(fileparts(mfilename('fullpath')));

runSelftest = true;          % false: skip the install check

% Overrides for RX_PC_MAIN; leave empty to use its USER SETTINGS block.
% e.g.  rxP = struct('rxGain',15, 'rxGainMax',25, 'autoScan',true);
rxP = struct();

if runSelftest
    SELFTEST;
end
rxOut = RX_PC_MAIN(rxP);
