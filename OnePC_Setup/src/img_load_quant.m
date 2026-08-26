%% =========================================================================
%  FILE:     img_load_quant.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Load an image file and turn it into the transmitted lattice of the
%    image demo: center-crop to a square, nearest-neighbour resample to
%    side x side, quantize to 4 bits per colour channel. Deliberately
%    toolbox-free (no imresize), so only MATLAB core imread is needed.
%
%  INPUTS:
%    imgPath : full path to an image file readable by imread
%    side    : output side length in pixels
%  OUTPUTS:
%    img : side x side x 3 uint8, values 0..15 (4 bits per channel)
%
%  DEPENDENCIES:
%    imread (MATLAB core)
% =========================================================================
function img = img_load_quant(imgPath, side)

raw = imread(imgPath);
if size(raw,3) == 1, raw = repmat(raw, 1, 1, 3); end
sz = [size(raw,1), size(raw,2)];  c = min(sz);
r0 = floor((sz(1)-c)/2);  c0 = floor((sz(2)-c)/2);
sq = raw(r0+(1:c), c0+(1:c), :);                % center crop to a square
ii = round(linspace(1, c, side));               % nearest-neighbour resample
img = uint8(floor(double(sq(ii, ii, :))/16));   % 4 bits per channel

end
