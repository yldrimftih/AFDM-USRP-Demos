%% =========================================================================
%  FILE:     bits2img420.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Inverse pixel mapping for the webcam demo: bit vector -> RGB image.
%    Unpacks Y|Cb|Cr 4-bit planes, mid-rise dequantization, nearest-
%    neighbor chroma upsampling, inverse full-range BT.601.
%  INPUTS:
%    b    : column vector, 6*S^2 bits in {0,1} (double or logical)
%    S    : luma canvas side (even)
%  OUTPUTS:
%    rgb    : uint8 SxSx3, full-range 0..255
%    planes : struct .Yq, .Cbq, .Crq (quantized-lattice view, uint8 0..15)
% =========================================================================
function [rgb, planes] = bits2img420(b, S)

assert(numel(b) == 6*S^2 && mod(S,2) == 0, ...
    'bits2img420: expected %d bits for S=%d, got %d', 6*S^2, S, numel(b));

% 1. unpack + split
v  = bit2int(reshape(double(b(:)), 4, []), 4);
nY = S^2;  nC = (S/2)^2;
planes = struct( ...
    'Yq',  uint8(reshape(v(1:nY),            S,   S)), ...
    'Cbq', uint8(reshape(v(nY+(1:nC)),       S/2, S/2)), ...
    'Crq', uint8(reshape(v(nY+nC+(1:nC)),    S/2, S/2)));

% 2. mid-rise dequant, 3. chroma upsample
Y  = 16*double(planes.Yq) + 8;
up = @(P) kron(16*double(P) + 8, ones(2));
Cb = up(planes.Cbq);  Cr = up(planes.Crq);

% 4. inverse BT.601, clip
R = Y + 1.402*(Cr - 128);
G = Y - 0.344*(Cb - 128) - 0.714*(Cr - 128);
B = Y + 1.772*(Cb - 128);
rgb = uint8(min(max(cat(3, R, G, B), 0), 255));
end
