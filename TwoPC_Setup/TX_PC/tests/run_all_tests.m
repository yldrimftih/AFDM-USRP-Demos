%% =========================================================================
%  FILE:     run_all_tests.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
%  AUTHORS:  Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
% --------------------------------------------------------------------------
%  PURPOSE:
%    Test runner: discovers tests/test_*.m, runs each, prints [PASS]/[FAIL],
%    errors out (non-zero exit under -batch) on any failure.
%  INPUTS:
%     none
%  OUTPUTS:
%    none (console + error on failure)
%  DEPENDENCIES:
%    tests/test_*.m
% =========================================================================
function run_all_tests

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'src'));

files = dir(fullfile(here, 'test_*.m'));
nPass = 0; nFail = 0;

for k = 1:numel(files)
    [~, name] = fileparts(files(k).name);
    try
        feval(name);
        fprintf('[PASS] %s\n', name);
        nPass = nPass + 1;
    catch e
        fprintf('[FAIL] %s: %s\n', name, e.message);
        nFail = nFail + 1;
    end
end

fprintf('=== %d passed, %d failed ===\n', nPass, nFail);
if nFail > 0
    error('run_all_tests:failures', '%d test(s) failed.', nFail);
end

end
