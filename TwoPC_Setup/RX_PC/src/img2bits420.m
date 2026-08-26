%% =========================================================================
%  FILE:     img2bits420.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Forward pixel mapping for the webcam demo: RGB image -> bit vector at
%    6 bits/px average via BT.601 YCbCr, 4:2:0 chroma subsampling, 4-bit
%    quantization per plane sample. One 72x72 canvas fits one 64-QAM
%    matched AFDM frame (31,104 <= 31,824 bits).
%  INPUTS:
%    rgb : uint8 SxSx3, S even, full-range 0..255
%  OUTPUTS:
%    b      : double column vector, 6*S^2 bits in {0,1}
%    planes : struct .Yq (SxS), .Cbq, .Crq ((S/2)x(S/2)) uint8 0..15 --
%             quantized-lattice view for exactness testing
% =========================================================================
function [b, planes] = img2bits420(rgb)

S = size(rgb, 1);
assert(size(rgb,2) == S && size(rgb,3) == 3 && mod(S,2) == 0, ...
    'img2bits420: expected even-sided square RGB, got %dx%dx%d', ...
    size(rgb,1), size(rgb,2), size(rgb,3));
R = double(rgb(:,:,1)); G = double(rgb(:,:,2)); B = double(rgb(:,:,3));

% 1. full-range BT.601 (Eqs. wc-y, wc-c)
Y  = 0.299*R + 0.587*G + 0.114*B;
Cb = 128 + 0.564*(B - Y);
Cr = 128 + 0.713*(R - Y);

% 2. chroma 2x2 block mean (4:2:0)
blk = @(P) (P(1:2:end,1:2:end) + P(2:2:end,1:2:end) + ...
            P(1:2:end,2:2:end) + P(2:2:end,2:2:end)) / 4;
Cb = blk(Cb);  Cr = blk(Cr);

% 3. 4-bit quantization
q = @(P) uint8(min(max(floor(P/16), 0), 15));
planes = struct('Yq', q(Y), 'Cbq', q(Cb), 'Crq', q(Cr));

% 4. pack plane-major, sample-major, 4-bit MSB-first
v = double([planes.Yq(:); planes.Cbq(:); planes.Crq(:)]);
b = reshape(int2bit(v, 4), [], 1);
end
