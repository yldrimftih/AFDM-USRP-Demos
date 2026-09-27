%% =========================================================================
%  FILE:     test_x310_profile.m
%  PROJECT:  PS-OFDM vs PS-AFDM live USRP demo  --  X310 port
% --------------------------------------------------------------------------
%  PURPOSE:
%    X310 hardware profile: the master clock divides the demo sample rate
%    into an integer rate change, the default carrier is inside every
%    supported daughterboard's range, and unknown boards are rejected.
%  INPUTS:
%    none
%  OUTPUTS:
%    none (errors on failure)
%  DEPENDENCIES:
%    x310_profile, combofdm_params
% =========================================================================
function test_x310_profile

fs = combofdm_params(256, 'matched').fs;
for db = {'CBX-120', 'UBX-160', 'SBX-120'}
    R = x310_profile(db{1});
    assert(mod(R.mcr, fs) == 0, '%s: mcr %g / fs %g not integer', db{1}, R.mcr, fs);
    assert(R.txGain(2) > R.txGain(1) && R.rxGain(2) > R.rxGain(1));
    assert(2.4e9 >= R.fRange(1) && 2.4e9 <= R.fRange(2), ...
        '%s: 2.4 GHz outside the tuning range', db{1});
    assert(any(strcmp(R.platforms, 'X310')));
    assert(all(mod(R.mcr, R.fsOpts) == 0), '%s: an offered fs does not divide mcr', db{1});
    assert(any(R.fsOpts == fs), '%s: default fs not offered', db{1});
    assert(isequal(R.rfNames, {'RF0','RF1'}));
end
assert(strcmp(x310_profile().dboard, 'CBX-120'), 'default board must be CBX-120');

threw = false;
try, x310_profile('WBX'); catch, threw = true; end
assert(threw, 'unknown daughterboard must error');

end
