%% =========================================================================
%  FILE:     combofdm_params.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Single source of truth for the comb-pilot PS-OFDM frame: interleaved
%    pilots in EVERY symbol and per-symbol channel estimation, the OFDM
%    counterpart of the embedded-pilot (EPA) PS-AFDM frame.
%  INPUTS:
%    N       : 64 or 256 (default 64)
%    profile : 'native' (default, prior behaviour bit-exact) or
%              'matched' (N = 256 only)
%  OUTPUTS:
%    prm : struct — sampling/preamble/STF as stage5_params, c1 = c2 = 0,
%          .pilotStep.pilotBins .nullBins .dataBins (0-based) .nBack .Nsym
% =========================================================================
function prm = combofdm_params(N, profile)

if nargin < 1 || isempty(N), N = 64; end
if nargin < 2 || isempty(profile), profile = 'native'; end
assert(any(N == [64 256]), 'combofdm_params: N must be 64 or 256');
assert(any(strcmp(profile, {'native','matched'})), ...
    'combofdm_params: profile must be ''native'' or ''matched''');
assert(~strcmp(profile,'matched') || N == 256, ...
    'matched profile: N = 256 only');

% sampling + preamble + STF: identical to stage5_params (sample-level)
prm.fs    = 1e6;
prm.M     = 5;
prm.beta  = 0.35;
prm.span  = 10;                      % preamble RRC span (sync front end)
prm.Nzc   = 139;
prm.u     = 25;
prm.gd    = prm.span * prm.M / 2;
prm.useSTF  = false;
prm.stfNzc  = 16;
prm.stfU    = 7;
prm.stfNrep = 10;
prm.stfLs   = prm.stfNzc * prm.M;

% OFDM core (matched framework)
prm.Nfft = N;
prm.Ncp  = 16;
prm.c1   = 0;
prm.c2   = 0;
if strcmp(profile, 'matched')        % window discipline = EPA matched
    prm.ellmax = 3;  prm.nBack = 2;  prm.kernelSpan = 2;
    prm.pilotStep = 8;               % Np = 32 (comb unchanged)
elseif N == 64
    prm.ellmax = 2;  prm.nBack = 2;  prm.kernelSpan = 2;
    prm.pilotStep = 4;               % Np = 16 >= 2+2+2+1... see assert
else
    prm.ellmax = 4;  prm.nBack = 4;  prm.kernelSpan = 4;
    prm.pilotStep = 8;               % Np = 32
end
prm.profile = profile;
Np = N / prm.pilotStep;
% alias-free comb: causal tap support (after backoff) must fit the window
assert(prm.nBack + prm.ellmax + prm.kernelSpan + 1 <= Np, ...
    'comb too sparse for the channel support');
prm.pilotBins = (0 : prm.pilotStep : N-1).';          % 0-based
% matched profile: null |Z| - Np = 3 data bins so both waveforms carry
% exactly 221 data + 35 non-data REs per symbol.
% PLACEMENT: bins 125-127 sit at the +band edge (97.7-99.2 kHz of the
% 100 kHz chip Nyquist), so the notch merges into the RRC transition
% band. First choice 253-255 (= -3..-1 bins) carved a visible ~2 kHz
% dip at BAND CENTER in the measured spectra -- moved. Not pilots
% (120/128 are); nulls stay zero in the build and are excluded from
% dataBins, so CE/equalizer/demap never see them.
if strcmp(profile, 'matched')
    prm.nullBins = (125:127).';
else
    prm.nullBins = zeros(0,1);
end
prm.dataBins  = setdiff((0:N-1).', [prm.pilotBins; prm.nullBins]);

% receiver standard practice: tap-support
% truncation (CE noise x S/Np = 8/32 = -6 dB) + per-bin MMSE label.
% Matched profile ON; native/legacy OFF -> prior behaviour bit-exact.
prm.ceTrunc = strcmp(profile, 'matched');
if strcmp(profile, 'matched'), prm.eqMode = 'mmse'; else, prm.eqMode = 'zf'; end

prm.Nsym     = 9;                    % every symbol: comb + data
prm.NsymData = prm.Nsym;

prm.modType  = 'qam';
prm.modOrder = 16;
prm.bps      = log2(prm.modOrder);

end
