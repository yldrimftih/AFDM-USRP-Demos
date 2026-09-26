%% =========================================================================
%  FILE:     RUN_TX_PC.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    One-click launcher for the TX PC: runs SELFTEST (no radio needed),
%    then starts TX_PC_MAIN. Open this file and press Run, then press
%    Scan in the window that opens.
%
%  DEPENDENCIES:
%    SELFTEST.m, TX_PC_MAIN.m (same folder)
% =========================================================================

cd(fileparts(mfilename('fullpath')));

runSelftest = true;          % false: skip the install check

% Overrides for TX_PC_MAIN; leave empty to use its USER SETTINGS block.
% e.g.  txP = struct('txGain',25, 'txGainMax',28, 'autoScan',true);
txP = struct();

if runSelftest
    SELFTEST;
end
txOut = TX_PC_MAIN(txP);
