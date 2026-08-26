%% =========================================================================
%  FILE:     stage5_params.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Single source of truth for the embedded-pilot (EPA) PS-AFDM frame,
%    with a per-symbol pilot. Two configurations selected by N: N = 64
%    "moderate" and N = 256 "comfortable", plus the 'matched' profile
%    (N = 256 only) whose guards are shrunk to an indoor channel so that
%    the frame resource-matches the comb-pilot PS-OFDM exactly (221 data
%    bins, pilot energy 32). Per-symbol channel estimation removes any
%    need for cross-symbol channel prediction.
%  INPUTS:
%    N       : 64 (default) or 256
%    profile : 'native' (default, prior behaviour bit-exact) or
%              'matched' (N = 256 only)
%  OUTPUTS:
%    prm : struct — sampling/preamble/STF as stage4_params, plus EPA:
%          .zoneLen.p0 .dataBins (0-based) .Ap .pilotFrac .kernelSpan
%          .roL (readout lattice bin list) .noiseBins (0-based)
% =========================================================================
function prm = stage5_params(N, profile)

if nargin < 1 || isempty(N), N = 64; end
if nargin < 2 || isempty(profile), profile = 'native'; end
assert(any(N == [64 256]), 'stage5_params: N must be 64 or 256');
assert(any(strcmp(profile, {'native','matched'})), ...
    'stage5_params: profile must be ''native'' or ''matched''');
assert(~strcmp(profile,'matched') || N == 256, ...
    'matched profile: N = 256 only (fmax = 1 zone >= 45%% at N = 64)');

% sampling + preamble + STF: identical to Stage 4 (sample-level, N-blind)
prm.fs    = 1e6;
prm.M     = 5;                       % chips at 200 kchip/s (band rule)
prm.beta  = 0.35;
prm.span  = 10;                      % preamble RRC span (sync front end)
prm.Nzc   = 139;
prm.u     = 25;
prm.gd    = prm.span * prm.M / 2;
prm.useSTF  = false;                 % two-radio scripts set true
prm.stfNzc  = 16;
prm.stfU    = 7;
prm.stfNrep = 10;
prm.stfLs   = prm.stfNzc * prm.M;

% EPA core (table)
prm.Nfft = N;
prm.Ncp  = 16;
if strcmp(profile, 'matched')        % N = 256, resource-matched to comb
    prm.fmax = 1;  prm.xi = 0;  prm.ellmax = 3;
    prm.nBack = 2;  prm.kernelSpan = 2;
elseif N == 64                       % "moderate"
    prm.fmax = 0;  prm.xi = 1;  prm.ellmax = 2;
    prm.nBack = 2;  prm.kernelSpan = 2;
else                                 % N = 256, "comfortable"
    prm.fmax = 1;  prm.xi = 1;  prm.ellmax = 4;
    prm.nBack = 4;  prm.kernelSpan = 4;
end
prm.profile = profile;
prm.c1 = (2*(prm.fmax + prm.xi) + 1) / (2*prm.Nfft);
prm.c2 = 1 / (2*pi*prm.Nfft);
assert(mod(2*prm.Nfft*prm.c1, 2) == 1, 'CPP == CP needs 2N*c1 odd');
assert(prm.nBack >= prm.kernelSpan && ...
       prm.nBack + prm.ellmax + prm.kernelSpan <= prm.Ncp, ...
       'backoff budget violated');

% exclusion zone Z = [0, zoneLen-1], pilot at p0, data on the rest
s    = 2*(prm.fmax + prm.xi) + 1;    % ridge strip
xif  = prm.fmax + prm.xi;
leff = prm.ellmax + prm.nBack;
qmax = s*leff + xif;
prm.zoneLen  = 2*s*leff + 4*xif + 1;
assert(prm.zoneLen < prm.Nfft, 'exclusion zone must leave data bins');
prm.p0       = qmax + xif;
prm.dataBins = (prm.zoneLen : prm.Nfft-1).';          % 0-based
% readout lattice (bins carrying pilot path energy) + zone noise bins
[lq, fq] = meshgrid(0:leff, -prm.fmax:prm.fmax);
prm.roL = mod(prm.p0 - (s*lq(:) - fq(:)), prm.Nfft);
assert(all(prm.roL < prm.zoneLen), 'readout lattice must lie inside Z');
% NOTE: the zone's non-readout bins are NOT noise-only (data shifted by
% q lands there legitimately); the receiver estimates noise from the
% pre-burst window instead (stage5_afdm_rx step 3a).

% pilot power: fraction rho of symbol power. SWEPT 2026-08-13 (0.05..0.40,
% 30 + 12 dB, tau = 0.40 channel): N = 256 flat-optimal at 0.15-0.20; the
% N = 64 config is pilot-limited at low SNR (5-point lattice, 35 data
% bins) with its knee at 0.30 (12 dB: EVM 18.7 -> 17.6 %, BER 5.3e-3;
% 30 dB: 6.43 -> 6.31 % -- better at BOTH).
% matched profile instead matches the COMB pilot energy exactly:
% Ap^2 = Np = 32 unit-power comb pilots -> rho = 32/253 (power match);
% data 221 / non-data 35 REs equal on both sides
% (comb nulls 3 bins), so data, pilot, and total energies match term by term.
Nd = numel(prm.dataBins);
if strcmp(profile, 'matched')
    NpComb = N / 8;                  % combofdm_params pilotStep = 8
    prm.pilotFrac = NpComb / (NpComb + Nd);
elseif N == 64
    prm.pilotFrac = 0.3;
else
    prm.pilotFrac = 0.2;
end
prm.Ap = sqrt(prm.pilotFrac/(1-prm.pilotFrac) * Nd);

% frame: EVERY symbol carries pilot + data (no dedicated pilot symbol)
prm.Nsym     = 9;                    % production airtime convention
prm.NsymData = prm.Nsym;             % all symbols carry data

% payload
prm.modType  = 'qam';
prm.modOrder = 16;
prm.bps      = log2(prm.modOrder);

end
