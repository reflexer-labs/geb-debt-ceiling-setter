pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "../SingleSpotDebtCeilingSetter.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract SingleSpotDebtCeilingSetterGasProfiling is DSTest {
    Hevm hevm;

    DSToken systemCoin;
    SingleSpotDebtCeilingSetter ceilingSetter;
    uint setterUpdateDelay;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        // kovan 1.4.0
        systemCoin = DSToken(0x76b06a2f6dF6f0514e7BEC52a9AfB3f603b477CD);
        ceilingSetter = SingleSpotDebtCeilingSetter(0x2747c5eE7692717EE2B284749bC1062BEAdab85d);

        uint setterLastUpdateTime = ceilingSetter.lastUpdateTime();
        setterUpdateDelay = ceilingSetter.updateDelay();

        if (setterLastUpdateTime + setterUpdateDelay > now)
            hevm.warp(setterLastUpdateTime + setterUpdateDelay);
    }

    function test_auto_update_ceiling_gas() public {
        ceilingSetter.autoUpdateCeiling(address(0xabc));
    }

    function test_auto_update_ceiling_gas_multiple() public {
        uint gas;
        for (uint i = 0; i < 10; i++) {
            gas = gasleft();
            ceilingSetter.autoUpdateCeiling(address(0xabc));
            emit log_named_uint("Gas", gas - gasleft());
            hevm.warp(now + setterUpdateDelay);
        }
    }

}

// dapp test -vv -m test_auto_update_ceiling_gas --rpc-url https://parity0.kovan.makerfoundation.com:8545