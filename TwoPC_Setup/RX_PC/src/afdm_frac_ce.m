%% =========================================================================
%  FILE:     afdm_frac_ce.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Fractional (off-grid) delay-Doppler channel estimation for AFDM from
%    the dedicated pilot symbol: matched-filter ambiguity surface over the
%    continuous (tau, nu) plane, parabolic refinement, successive
%    cancellation, and reconstruction of the (dense) effective channel.
%    Supersedes the integer-grid readout when paths are off-lattice.
%    With the receiver timing backoff prm.nBack the search grid covers
%    the shifted range [0, ellmax + nBack]; outputs are in the shifted
%    frame and the caller converts them to physical delays.
%  INPUTS:
%    yp  : N x 1 received pilot symbol (DAFT domain)
%    prm : stage4_params struct (.Nfft.c1 .c2 .p0 .Ap .fmax .ellmax .xi)
%    opt : optional overrides
%          .dTau (0.05) .dNu (0.05)  grid steps [chips / bins]
%          .maxPaths (4)             path cap
%          .kappa (2.0)              residual stop at kappa*N*sigma2
%          .sigma2 ([])              noise variance; [] -> estimated from
%                                    the median of the residual surface
%          .refine (true)            parabolic refinement
%          .orderSel ('bic')         model-order selection over the OMP
%                                    prefixes; 'none' = legacy stops only
%  OUTPUTS:
%    out : struct
%          .tau.nu .h      1 x P estimated fractional parameters + gains
%          .G               N x N effective channel (dense)
%          .sigma2          noise variance used/estimated
%          .S               nTau x nNu ambiguity surface (linear power)
%          .tauAx.nuAx     surface axes
%          .resid           final residual power
%          .nIter           paths extracted
%  DEPENDENCIES:
%     None (self-contained; mirrors afdm_mod
%                               conventions for A)
% =========================================================================
function out = afdm_frac_ce(yp, prm, opt)

if nargin < 3, opt = struct(); end
d = struct('dTau',0.05, 'dNu',0.05, 'maxPaths',4, 'kappa',2.0, ...
           'sigma2',[], 'refine',true, 'relFloor',1e-3, 'pulse','rc', ...
           'detThr',[], 'kernelSpan',4, 'orderSel','bic');
fn = fieldnames(d);
for i = 1:numel(fn)
    if ~isfield(opt,fn{i}) || isempty(opt.(fn{i})) && ~strcmp(fn{i},'sigma2')
        opt.(fn{i}) = d.(fn{i});
    end
end
if ~isfield(opt,'sigma2'), opt.sigma2 = []; end

yp = yp(:);
N  = prm.Nfft;
n  = (0:N-1).';
lam1 = exp(-2j*pi*prm.c1*(n.^2));      % same convention as afdm_mod
lam2 = exp(-2j*pi*prm.c2*(n.^2));

% pilot template: chips s0 = A^H Xp  (IDAFT of the pilot grid)
Xp = zeros(N,1);  Xp(prm.p0+1) = prm.Ap;
s0 = conj(lam1) .* (sqrt(N) * ifft(conj(lam2) .* Xp, N, 1));
S0 = fft(s0, N, 1);                    % cached chip-DFT for delay ramps

% Fractional-delay operator in the chip-DFT domain.
%  'rc'    : PHYSICAL. The air delay acts on the RRC-shaped waveform and the
%            RX matched filter re-samples at chip instants, so the effective
%            chip-domain response is the raised-cosine kernel sampled at
%            (m - tau). Its spectrum rolls off from (1-beta)/2 to (1+beta)/2
%            per chip, so it is NOT the ideal band-limited delay -- using the
%            ideal ramp biased a planted 2.40-chip physical delay to 1.81
%            (measured 2026-08-13). At integer tau the Nyquist property gives
%            p_RC(m) = delta_m, so the integer reduction is preserved exactly.
%  'ideal' : band-limited phase ramp (kept for comparison/ablation).
% kernelSpan bounds the RC interpolator's support.
% Default 4 (with the timing backoff): the deployed receiver
% needs nBack >= span and nBack + ellmax + span <= Ncp, and span 4 sits
% on the accuracy plateau -- re-measured at 60 dB,
% tau = 1.40/4.65: EVM 5.82/3.95/3.68/4.72 % at span 2/4/6/10. The interim
% default of 10 (set when span was cleared of causing the small-tau floor,
% which is acausal energy, not truncation) bought nothing and violates the
% backoff budget.
delay_dft = @(t) delay_kernel_dft(t, N, prm.beta, opt.kernelSpan, opt.pulse);

% Search grid. With a receiver timing backoff the channel is SEEN at
% tau + nBack, so the grid covers the shifted range [0, ellmax + nBack];
% the caller (stage4_afdm_rx) converts outputs back to physical delays.
% Without prm.nBack this reduces to the original [0, ellmax].
nBk = 0;
if isfield(prm,'nBack'), nBk = prm.nBack; end
tauAx = (0 : opt.dTau : prm.ellmax + nBk);
nuAx  = (-prm.fmax : opt.dNu : prm.fmax);
Dop   = exp(2j*pi * n * nuAx / N);     % N x nNu Doppler phases

% ---- ambiguity surface (normalized matched filter / GLRT) --------------
[C, nrm] = corr_surface(yp);
S = abs(C).^2 ./ (nrm(:).^2);        % nrm depends on tau only

% ---- stopping references ----------------------------------------------
% A caller-supplied sigma2 (the AFDM receiver has one from the non-path
% pilot bins) enables the noise-floor stop. With sigma2 = [] we must NOT
% guess it from the pilot symbol itself: the median of |yp|^2 is dominated
% by the spread pilot response, which over-estimates the noise by orders of
% magnitude and truncates the path search after one atom (measured
% 2026-08-13: a 2-path noiseless case returned 1 path). Instead fall back
% to relative rules and report a POST-FIT sigma2 = residual/N.
Pinit = sum(abs(yp).^2);

% ---- ORTHOGONAL matching pursuit ---------------------------------------
% Sequential (plain MP) subtraction biases each gain by the non-orthogonal
% overlap of the atoms, h1_hat = h1 + h2 (a1^H a2)/Ap^2, which leaves a
% residue big enough to misplace the next peak (measured 2026-08-13: a
% second path at tau=4.70 was reported at 0.36). Re-solving ALL gains
% jointly by least squares after each selection removes that bias.
% Detection gate: |Cn| is a unit-norm-atom correlation, so under noise only
% it is Rayleigh with variance sigma2. Requiring |Cn|^2 > 2 ln(nGrid) sigma2
% sets a per-surface false-alarm rate of ~1/nGrid. Without this gate a pure
% noise input still gets fitted: OMP adds near-collinear atoms whose joint
% LS coefficients then blow up (measured 2026-08-13: |h| = 4.25 on noise).
% Active only when sigma2 is known -- which the receiver always does (it
% estimates it from the non-path pilot bins).
if isempty(opt.detThr), opt.detThr = 2*log(numel(S)); end

r = yp;  tauH = []; nuH = []; hH = [];  Aset = zeros(N,0);
rssHist = sum(abs(yp).^2);           % RSS trajectory, entry 1 = P = 0
for p = 1:opt.maxPaths
    if p > 1, [C, nrm] = corr_surface(r); end
    Cn = abs(C) ./ nrm(:);           % normalized metric drives the search
    if ~isempty(opt.sigma2) && max(Cn(:))^2 < opt.detThr*opt.sigma2
        break                        % nothing above the noise -> stop
    end
    [~, idx] = max(Cn(:));
    [it, in] = ind2sub(size(C), idx);
    t = tauAx(it);  v = nuAx(in);
    if opt.refine
        t = t + opt.dTau * parab(absrow(Cn, it, in, 1));
        v = v + opt.dNu  * parab(absrow(Cn, it, in, 2));
        t = min(max(t, tauAx(1)), tauAx(end));
        v = min(max(v, nuAx(1)),  nuAx(end));
    end
    a = pilot_resp(t, v);
    % collinearity guard: a new atom that the current set already spans
    % carries no information and would make the LS ill-conditioned
    if ~isempty(tauH)
        aPerp = a - Aset*(Aset\a);
        if norm(aPerp)/norm(a) < 0.1, break; end
    end
    Aset(:,end+1) = a;                                   %#ok<AGROW>
    tauH(end+1) = t;  nuH(end+1) = v;                    %#ok<AGROW>
    hH = (Aset \ yp).';                  % joint LS over the whole support
    % ---- cyclic position re-refinement -----------------------------------
    % Greedy peaks are POSITION-BIASED when atoms overlap: the first peak
    % sits on the superposition of both paths, and OMP's joint LS re-fits
    % GAINS but never positions. Measured 2026-08-12 (2-path 0/1.60 chips):
    % positions read 0.10/1.68, and the position error leaves a structured
    % residual 55x the per-bin noise floor that spurious atoms then
    % legitimately absorb -- defeating any model-order rule. Re-refining
    % each atom against the residual WITH THE OTHERS HELD (coordinate
    % descent on the matched-filter objective) removes the bias.
    if opt.refine && numel(tauH) > 1
        for sw = 1:6
            rssPrev = sum(abs(yp - Aset*hH(:)).^2);
            for p2 = 1:numel(tauH)
                oth = true(1, numel(tauH));  oth(p2) = false;
                rp  = yp - Aset(:,oth) * hH(oth).';
                [Cp, nrmp] = corr_surface(rp);
                Cpn = abs(Cp) ./ nrmp(:);
                % restrict to +-0.5 cell around the current position:
                % the global max of rp may be another path's residue
                win = abs(tauAx.' - tauH(p2)) <= 0.5 & ...
                      abs(nuAx    - nuH(p2))  <= 0.5;
                Cpn(~win) = 0;      % (0 not -Inf: keeps parab neighbours finite)
                [~, idx2] = max(Cpn(:));
                [it2, in2] = ind2sub(size(Cp), idx2);
                t2 = tauAx(it2) + opt.dTau * parab(absrow(Cpn, it2, in2, 1));
                v2 = nuAx(in2)  + opt.dNu  * parab(absrow(Cpn, it2, in2, 2));
                t2 = min(max(t2, tauAx(1)), tauAx(end));
                v2 = min(max(v2, nuAx(1)),  nuAx(end));
                tauH(p2) = t2;  nuH(p2) = v2;
                Aset(:,p2) = pilot_resp(t2, v2);
                hH = (Aset \ yp).';
            end
            if sum(abs(yp - Aset*hH(:)).^2) > 0.99*rssPrev, break; end
        end
    end
    r  = yp - Aset*hH(:);
    Pres = sum(abs(r).^2);
    rssHist(end+1) = Pres;                               %#ok<AGROW>
    % stop when (i) the residual reaches the known noise floor, or
    % (ii) the newest atom is negligible against the strongest, or
    % (iii) the fit is numerically exact
    if ~isempty(opt.sigma2) && Pres < opt.kappa*N*opt.sigma2, break; end
    if abs(hH(end))^2 < opt.relFloor * max(abs(hH).^2), break; end
    if Pres < 1e-8 * Pinit, break; end
end

% ---- model-order selection (information criterion over the OMP path) ----
% The detection gate + residual stops bound the search but OVER-SELECT:
% with the (correct) median sigma2 the residual stop rarely fires before
% maxPaths, and spurious atoms take small LS gains (measured 2026-08-12:
% P = 3-4 returned in 8/8 draws where exactly 2 were planted; a spurious
% atom sat at the grid edge and at negative physical delay). OMP is greedy
% and nested, so the RSS trajectory rssHist(P+1), P = 0..Pmax prices each
% prefix. The penalty must respect the SELECTION EVENT: every atom is the
% argmax over ~nGrid correlated candidates, so a pure-noise atom removes
% ~2 ln(nGrid) sigma2 of RSS (extreme value of chi2_2 over the surface) --
% a plain per-parameter BIC penalty (4 ln 2N ~ 19 ~ 2 ln nGrid at N = 64)
% sits exactly ON that boundary and rejects nothing (measured 2026-08-12:
% P stayed 4). With sigma2 known, the generalized IC
%   GIC(P) = RSS_P / sigma2 + P * 2 * detThr,       detThr = 2 ln nGrid,
% prices each atom at TWICE its worst-case noise contribution; a real path
% of relative gain |h| contributes |h|^2 ||a||^2 / sigma2 ~ |h|^2 N / sigma2
% (1440 sigma2 for |h| = 0.15 at 30 dB), so the margin is 1-2 orders of
% magnitude and weak true paths survive. (Stoica & Selen, IEEE SPM 2004,
% model-order selection survey; GIC with rho = 2*detThr.) Without sigma2
% fall back to the unknown-variance BIC over 2N real observations,
%   BIC(P) = 2N ln(RSS_P / 2N) + 4P ln(2N),
% which is self-calibrating but weak at small N (kept for the
% receiver-independent use case; the receiver always supplies sigma2).
% ---- physical-causality prune -------------------------------------------
% With a receiver backoff the physical delay is tauH - nBack, and no
% physical path can arrive earlier than the sync-locked first path minus
% timing jitter (< 0.1 chip). Atoms at physical tau < -0.5 are artifacts
% (they absorb position-error residue of the true atoms; measured
% 2026-08-12: |h| ~ 0.03 at physical -0.83). Keep at least the strongest.
if nBk > 0 && numel(tauH) > 1
    bad = (tauH - nBk) < -0.5;
    if all(bad), [~, ik] = max(abs(hH)); bad(ik) = false; end
    if any(bad)
        tauH = tauH(~bad);  nuH = nuH(~bad);  Aset = Aset(:,~bad);
        hH = (Aset \ yp).';
        r  = yp - Aset*hH(:);
        rssHist = rssHist(1:numel(tauH)+1);      % rebuilt below is nested no
        % more; recompute a consistent trajectory for the order rule
        for pp = 1:numel(tauH)
            hp = Aset(:,1:pp) \ yp;
            rssHist(pp+1) = sum(abs(yp - Aset(:,1:pp)*hp).^2);
        end
    end
end

if strcmpi(opt.orderSel, 'bic') && numel(tauH) > 1
    Pmax = numel(tauH);
    ic  = zeros(Pmax+1, 1);
    for pp = 0:Pmax
        if ~isempty(opt.sigma2)
            ic(pp+1) = rssHist(pp+1)/opt.sigma2 + pp * 2*opt.detThr;
        else
            ic(pp+1) = 2*N*log(max(rssHist(pp+1), eps)/(2*N)) + 4*pp*log(2*N);
        end
    end
    [~, ib] = min(ic);
    Psel = ib - 1;
    if Psel < Pmax && Psel >= 1
        tauH = tauH(1:Psel);  nuH = nuH(1:Psel);  Aset = Aset(:,1:Psel);
        hH = (Aset \ yp).';              % refit on the selected support
        r  = yp - Aset*hH(:);
    end
    % Psel == 0 is not honored here: the detection gate already vetoes
    % noise-only inputs, and the receiver contract guarantees >= 1 path.
end
if isempty(opt.sigma2)
    sigma2 = sum(abs(r).^2) / N;         % post-fit estimate
else
    sigma2 = opt.sigma2;
end

% ---- effective channel: per-path operators, then their sum -------------
% Gp is kept per path because a multi-path channel with DIFFERENT Dopplers
% is NOT static across the frame: each path's phase advances by
% 2*pi*nu_p*(N+Ncp)/N per symbol, so their RELATIVE phase -- and hence the
% effective channel -- changes symbol to symbol. A parametric estimate can
% predict that; a single G measured on the pilot cannot (measured
% 2026-08-13: a 2-path off-grid channel gave BER 0.45 with one static G
% even though the parameters were recovered to 0.003 cells).
Gp = cell(1, numel(tauH));
G  = zeros(N,N);
for p = 1:numel(tauH)
    Gp{p} = chan_op(tauH(p), nuH(p));
    G     = G + hH(p) * Gp{p};
end

out = struct('tau',tauH, 'nu',nuH, 'h',hH, 'G',G, 'Gp',{Gp}, 'sigma2',sigma2, ...
    'S',S, 'tauAx',tauAx, 'nuAx',nuAx, 'resid',sum(abs(r).^2), ...
    'nIter',numel(tauH), 'rssHist',rssHist);

% ===================== local functions ==================================
    function [C, nrm] = corr_surface(z)
        % a(tau,nu)^H z for every grid point (vectorized over nu) plus
        % ||a(tau,.)||, which is nu-independent: lam1/lam2/Dop are
        % unit-modulus and the DAFT is unitary, so ||a|| = ||delayed chips||
        C = zeros(numel(tauAx), numel(nuAx));
        nrm = zeros(numel(tauAx),1);
        for k = 1:numel(tauAx)
            st = ifft(S0 .* delay_dft(tauAx(k)), N, 1);
            nrm(k) = norm(st);
            u  = lam1 .* st;                       % pre-DAFT chirp
            V  = lam2 .* (fft(u .* Dop, N, 1) / sqrt(N));   % N x nNu
            C(k,:) = (V' * z).';                   % conj-transpose = a^H z
        end
    end

    function a = pilot_resp(t, v)
        st = ifft(S0 .* delay_dft(t), N, 1);
        a  = lam2 .* (fft(lam1 .* st .* exp(2j*pi*v*n/N), N, 1) / sqrt(N));
    end

    function Op = chan_op(t, v)
        % A D_v T_t A^H as an explicit N x N operator
        ramp = delay_dft(t);
        Op   = zeros(N,N);
        for c = 1:N
            e = zeros(N,1); e(c) = 1;
            sc = conj(lam1) .* (sqrt(N) * ifft(conj(lam2) .* e, N, 1)); % A^H e
            sc = ifft(fft(sc, N, 1) .* ramp, N, 1);                     % T_t
            sc = sc .* exp(2j*pi*v*n/N);                                % D_v
            Op(:,c) = lam2 .* (fft(lam1 .* sc, N, 1) / sqrt(N));        % A
        end
    end

    function v3 = absrow(C, it, in, dim)
        % |C| at the peak and its two neighbours along 'dim' (edge-safe)
        if dim == 1
            i0 = max(it-1,1); i2 = min(it+1,size(C,1));
            v3 = abs([C(i0,in), C(it,in), C(i2,in)]);
            if it == 1 || it == size(C,1), v3 = [1 1 1]*abs(C(it,in)); end
        else
            j0 = max(in-1,1); j2 = min(in+1,size(C,2));
            v3 = abs([C(it,j0), C(it,in), C(it,j2)]);
            if in == 1 || in == size(C,2), v3 = [1 1 1]*abs(C(it,in)); end
        end
    end
end

function dlt = parab(v3)
% sub-cell offset of a quadratic through three samples (0 if degenerate)
den = v3(1) - 2*v3(2) + v3(3);
if abs(den) < 1e-12
    dlt = 0;
else
    dlt = 0.5*(v3(1) - v3(3)) / den;
    dlt = min(max(dlt, -0.5), 0.5);
end
end

function Gf = delay_kernel_dft(tau, N, beta, span, kind)
% Chip-DFT-domain multiplier of the fractional-delay operator.
if strcmp(kind, 'ideal')
    Gf = exp(-2j*pi*tau*(0:N-1).'/N);
    return
end
% raised-cosine (TX RRC (*) RX RRC) sampled at m - tau, wrapped cyclically.
% The window must be centred ON tau, not on zero: a window (-span:span)
% misses the pulse entirely once tau > span (measured 2026-08-13: tau = 7
% with span 4 was read as 9.7).
m  = round(tau) + (-span:span).';
t  = m - tau;
p  = sinc(t) .* cos(pi*beta*t) ./ (1 - (2*beta*t).^2);
sing = abs(1 - (2*beta*t).^2) < 1e-9;          % t = +-1/(2 beta)
if any(sing)
    p(sing) = (pi/4) * sinc(1/(2*beta));
end
g = zeros(N,1);
idx = mod(m, N) + 1;                            % cyclic wrap
for k = 1:numel(idx), g(idx(k)) = g(idx(k)) + p(k); end
Gf = fft(g, N, 1);
end
