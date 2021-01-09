pragma solidity 0.6.7;

import "ds-test/test.sol";

import "../mock/MockTreasury.sol";
import "../SingleDebtCeilingSetter,sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}
contract MockSAFEEngine {
    uint256 public globalDebtCeiling;

    struct CollateralType {
        // Total debt issued for this specific collateral type
        uint256 debtAmount;        // [wad]
        // Accumulator for interest accrued on this collateral type
        uint256 accumulatedRate;   // [ray]
        // Floor price at which a SAFE is allowed to generate debt
        uint256 safetyPrice;       // [ray]
        // Maximum amount of debt that can be generated with this collateral type
        uint256 debtCeiling;       // [rad]
        // Minimum amount of debt that must be generated by a SAFE using this collateral
        uint256 debtFloor;         // [rad]
        // Price at which a SAFE gets liquidated
        uint256 liquidationPrice;  // [ray]
    }
    // Data about each collateral type
    mapping (bytes32 => CollateralType) public collateralTypes;

    function modifyParameters(
        bytes32 parameter,
        uint256 data
    ) external {
        globalDebtCeiling = data;
    }
    function modifyParameters(
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    ) external {
        if (parameter == "safetyPrice") collateralTypes[collateralType].safetyPrice = data;
        else if (parameter == "accumulatedRate") collateralTypes[collateralType].accumulatedRate = data;
        else if (parameter == "debtCeiling") collateralTypes[collateralType].debtCeiling = data;
        else if (parameter == "debtAmount") collateralTypes[collateralType].debtAmount = data;
        else revert("SAFEEngine/modify-unrecognized-param");
    }
}

contract SingleDebtCeilingSetterTest is DSTest {
    Hevm hevm;

    MockTreasury treasury;
    MockSAFEEngine safeEngine;
    DSToken systemCoin;

    bytes32 collateralName = bytes32("ETH-A");
    uint256 baseUpdateCallerReward = 5 ether;
    uint256 maxUpdateCallerReward = 10 ether;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% per hour
    uint256 updateDelay = 1 hours;
    uint256 ceilingPercentageChange = 120;
    uint256 maxCollateralCeiling = 1000E27;
    uint256 minCollateralCeiling = 1E27;

    uint256 coinsToMint = 100E45;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        systemCoin = new DSToken("RAI", "RAI");
        treasury = new MockTreasury(address(systemCoin));
        safeEngine = new MockSAFEEngine();

        systemCoin.mint(address(treasury), coinsToMint);



        treasury.setTotalAllowance(address(rateSetter), uint(-1));
        treasury.setPerBlockAllowance(address(rateSetter), uint(-1));
    }

    function test_verify_deployment() public {

    }
    function test_modify_parameters() public {

    }
    function test_add_remove_manual_setters() public {

    }
    function testFail_add_remove_manual_setter_by_invalid_caller() public {

    }
    function test_getNextCeiling_current_ceiling_zero() public {

    }
    function test_getNextCeiling_current_ceiling_above_max() public {

    }
    function test_getNextCeiling_current_ceiling_max_uint() public {

    }
    function test_getNextCeiling_current_ceiling_increased() public {

    }
    function test_getNextCeiling_current_ceiling_decreased() public {

    }
    function test_getNextCeiling_multi_times() public {

    }
    function testFail_manual_update_twice_same_block() public {

    }
    function testFail_manual_update_invalid_caller() public {

    }
    function test_manual_update() public {

    }
    function test_multi_manual_update() public {

    }
    function test_manual_update_global_debt_max_uint() public {

    }
    function test_manual_update_global_debt_below_new_ceiling() public {

    }
    function test_manual_update_max_ceiling_change() public {

    }
    function testFail_auto_update_twice_same_block() public {

    }
    function test_auto_update() public {

    }
    function test_auto_update_base_reward_null() public {

    }
    function test_auto_update_twice_second_update_after_long_delay() public {

    }
    function test_multi_auto_update() public {

    }
    function test_auto_update_global_debt_max_uint() public {

    }
    function test_auto_update_global_debt_below_new_ceiling() public {

    }
    function test_auto_update_max_ceiling_change() public {

    }
    function test_auto_update_global_debt_zero() public {

    }
    function test_auto_update_collateral_current_ceiling_zero() public {

    }
    function test_auto_update_both_global_and_collateral_ceilings_zero() public {

    }
}
