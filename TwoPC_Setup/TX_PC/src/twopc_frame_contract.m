%% =========================================================================
%  FILE:     twopc_frame_contract.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Deterministic frame contract shared by the TX PC and the RX PC. Both
%    hosts run this file on the same image file and obtain bit-identical
%    parameters, payload bits, transmit frames and reference structs, so
%    the receiver regenerates its ground truth locally and no backchannel
%    between the two PCs is needed.
%
%    Frame geometry: matched profile N = 256, 16-QAM, 48 symbols per frame
%    -> 42,432 bits, which carries one 84x84 image (4:2:0, 42,336 bits)
%    plus 96 pad bits. The PS-AFDM section uses Zadoff-Chu root 34 and the
%    PS-OFDM section root 25, so each receiver locks onto its own burst
%    inside one shared capture. Payload is scrambled with a fixed PN
%    sequence (seed 46) so transmit power does not depend on image content.
%
%  INPUTS:
%    imgFile : image file name, default 'ku.jpg'. MUST be identical on
%              both PCs -- it defines the payload.
%    imgDir  : folder holding the image, default = parent of src/
%  OUTPUTS:
%    C : struct -- .prmO .prmA (params), .refO .refA (receiver references),
%        .xO .xA (baseband frames), .bits (scrambled payload), .pn,
%        .rgb (84x84x3 uint8, image as transmitted), .S, .nPad, .imgFile
%
%  DEPENDENCIES:
%    combofdm_params, stage5_params, combofdm_build, stage5_afdm_build,
%    img2bits420, bits2img420  |  imread (MATLAB core)
% =========================================================================
function C = twopc_frame_contract(imgFile, imgDir)

if nargin < 1 || isempty(imgFile), imgFile = 'ku.jpg'; end
if nargin < 2 || isempty(imgDir)
    imgDir = fileparts(fileparts(mfilename('fullpath')));
end
imgPath = fullfile(imgDir, imgFile);
assert(exist(imgPath, 'file') == 2, ...
    'twopc_frame_contract: image not found: %s', imgPath);

% 1. params -- matched profile, two-radio STF on, long frames, split roots
prmO = combofdm_params(256, 'matched');
prmA = stage5_params(256, 'matched');
prmO.useSTF = true;   prmA.useSTF = true;
prmO.Nsym = 48;  prmO.NsymData = 48;
prmA.Nsym = 48;  prmA.NsymData = 48;
prmA.u = 34;                          % AFDM section ZC root (OFDM keeps 25)
nBits = prmO.bps * numel(prmO.dataBins) * prmO.Nsym;
assert(nBits == prmA.bps * numel(prmA.dataBins) * prmA.Nsym, ...
    'matched frames must carry identical bit counts');

% 2. image -> 84x84 canvas (center crop + nearest neighbour, no toolbox)
S = 84;
assert(6*S^2 <= nBits, 'bit budget violated: %d > %d', 6*S^2, nBits);
raw = imread(imgPath);
if size(raw,3) == 1, raw = repmat(raw, 1, 1, 3); end
sz = [size(raw,1), size(raw,2)];  c = min(sz);
r0 = floor((sz(1)-c)/2);  c0 = floor((sz(2)-c)/2);
sq = raw(r0+(1:c), c0+(1:c), :);
ii = round(linspace(1, c, S));
img84 = sq(ii, ii, :);

% 3. bits: map, pad, scramble (fixed seed 46 -- part of the contract)
b    = img2bits420(img84);
nPad = nBits - numel(b);
rs   = RandStream('mt19937ar', 'Seed', 46);
pn   = randi(rs, [0 1], nBits, 1);
bits = double(xor([b; zeros(nPad,1)], pn));

% 4. frames
[xO, refO] = combofdm_build(bits, prmO);
[xA, refA] = stage5_afdm_build(bits, prmA);

C = struct('prmO',prmO, 'prmA',prmA, 'refO',refO, 'refA',refA, ...
    'xO',xO, 'xA',xA, 'bits',bits, 'pn',pn, ...
    'rgb',bits2img420(b, S), 'S',S, 'nPad',nPad, 'imgFile',imgFile);

end
