%% =========================================================================
%  FILE:     combofdm_build.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    TX-SIDE ONLY. Build the comb-pilot PS-OFDM frame: shaped double-ZC
%    preamble (+ optional STF) + DFT chips where EVERY symbol carries the
%    interleaved pilot comb and data on the remaining bins.
%  INPUTS:
%    bits : column, prm.bps * numel(prm.dataBins) * prm.Nsym bits
%    prm  : struct from combofdm_params
%    targetPeak : scalar (default 0.5)
%  OUTPUTS:
%    x   : complex column frame (peak = targetPeak)
%    ref : struct — burst_sync interface + .dataSyms (Nd x Nsym) .Xgrid
%          .pilotSeq.chipIdx
%  DEPENDENCIES:
%    src/afdm_mod.m, src/stf_chips.m
% =========================================================================
function [x, ref] = combofdm_build(bits, prm, targetPeak)

if nargin < 3, targetPeak = 0.5; end
assert(prm.c1 == 0 && prm.c2 == 0, 'combofdm_build requires c1 = c2 = 0');
Nd    = numel(prm.dataBins);
nBits = prm.bps * Nd * prm.Nsym;
assert(numel(bits) == nBits, 'need %d payload bits', nBits);

% 1. Preamble + optional STF (identical to psofdm_build)
n   = (0:prm.Nzc-1).';
zc  = exp(-1j*pi*prm.u*n.*(n+1)/prm.Nzc);
p   = rcosdesign(prm.beta, prm.span, prm.M, 'sqrt');
cSTF = [];  nSTF = 0;
if isfield(prm, 'useSTF') && prm.useSTF
    [cSTF, nSTF] = stf_chips(prm);
end
nSTFs = nSTF * prm.M;
pre = upfirdn([cSTF; zc; zc], p, prm.M);

% 2. Comb pilots: unit-power QPSK, STRUCTURAL seed 44 (distinct from the
%    Stage-3 (42) and PS-OFDM full-band (43) streams)
rs = RandStream('mt19937ar', 'Seed', 44);
pilotSeq = exp(1j*(pi/4 + pi/2*randi(rs, [0 3], numel(prm.pilotBins), 1)));

% 3. Payload + per-symbol grids
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
X(prm.pilotBins + 1, :) = repmat(pilotSeq, 1, prm.Nsym);
X(prm.dataBins + 1, :)  = D;

% 4. IDFT chips -> pulse shaping; assemble + normalize
chips = afdm_mod(X, prm);
xo    = upfirdn(chips, p, prm.M);
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
ref.pilotSeq = pilotSeq;
preLen      = numel(pre);
Nchip       = (prm.Nfft + prm.Ncp) * prm.Nsym;
ref.chipIdx = preLen + numel(guard) + 2*prm.gd - nSTFs ...
              + (0:Nchip-1).'*prm.M + 1;

end
