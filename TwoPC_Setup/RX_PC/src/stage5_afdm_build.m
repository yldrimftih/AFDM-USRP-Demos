%% =========================================================================
%  FILE:     stage5_afdm_build.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    TX-SIDE ONLY. Build the Stage 5 EPA frame: shaped double-ZC preamble
%    (+ optional STF) + AFDM chips where EVERY symbol carries an embedded
%    pilot bin, the exclusion-zone guard, and data on the remaining bins.
%  INPUTS:
%    bits : column, prm.bps * numel(prm.dataBins) * prm.Nsym payload bits
%    prm  : struct from stage5_params
%    targetPeak : scalar (default 0.5)
%  OUTPUTS:
%    x   : complex column frame (peak = targetPeak)
%    ref : struct — .preambleWave.Lp .Lr .scale .nSTF .dataSyms
%          (Nd x Nsym) .Xgrid.chipIdx (as stage4_afdm_build)
%  DEPENDENCIES:
%    src/afdm_mod.m, src/stf_chips.m
% =========================================================================
function [x, ref] = stage5_afdm_build(bits, prm, targetPeak)

if nargin < 3, targetPeak = 0.5; end
Nd    = numel(prm.dataBins);
nBits = prm.bps * Nd * prm.Nsym;
assert(numel(bits) == nBits, 'need %d payload bits', nBits);

% 1. Preamble + optional STF (identical to stage4_afdm_build)
n   = (0:prm.Nzc-1).';
zc  = exp(-1j*pi*prm.u*n.*(n+1)/prm.Nzc);
p   = rcosdesign(prm.beta, prm.span, prm.M, 'sqrt');
cSTF = [];  nSTF = 0;
if isfield(prm, 'useSTF') && prm.useSTF
    [cSTF, nSTF] = stf_chips(prm);
end
nSTFs = nSTF * prm.M;
pre = upfirdn([cSTF; zc; zc], p, prm.M);

% 2. Per-symbol EPA grids: pilot + zone zeros + data
switch prm.modType
    case 'qam'
        d = qammod(bits(:), prm.modOrder, 'InputType','bit', ...
                   'UnitAveragePower', true);
    case 'psk'
        d = pskmod(bit2int(reshape(bits(:), prm.bps, []), prm.bps).', ...
                   prm.modOrder, 0, 'gray');
    otherwise
        error('unknown modType %s', prm.modType);
end
D = reshape(d, Nd, prm.Nsym);
X = zeros(prm.Nfft, prm.Nsym);
X(prm.p0 + 1, :)       = prm.Ap;               % embedded pilot, every symbol
X(prm.dataBins + 1, :) = D;                    % zone stays zero (guard)

% 3. Chips -> pulse shaping
chips = afdm_mod(X, prm);
xo    = upfirdn(chips, p, prm.M);

% 4. Assemble + normalize (identical bookkeeping to stage4_afdm_build)
guard = zeros(prm.gd, 1);
xRaw  = [pre; guard; xo];
scale = targetPeak / max(abs(xRaw));
x     = scale * xRaw;

Lp = prm.Nzc * prm.M;
ref.preambleWave = x(nSTFs + (1 : 2*Lp + prm.span*prm.M));
ref.Lp       = Lp;
ref.Lr       = numel(ref.preambleWave);
ref.scale    = scale;
ref.nSTF     = nSTF;
ref.dataSyms = D;
ref.Xgrid    = X;
preLen      = numel(pre);
Nchip       = (prm.Nfft + prm.Ncp) * prm.Nsym;
ref.chipIdx = preLen + numel(guard) + 2*prm.gd - nSTFs ...
              + (0:Nchip-1).'*prm.M + 1;

end
