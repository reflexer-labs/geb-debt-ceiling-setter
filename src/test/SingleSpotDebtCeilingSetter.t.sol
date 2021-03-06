pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "../mock/MockTreasury.sol";
import "../mock/MockOracleRelayer.sol";
import "../SingleSpotDebtCeilingSetter.sol";

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
        else if (parameter == "debtFloor") collateralTypes[collateralType].debtFloor = data;
        else revert("SAFEEngine/modify-unrecognized-param");
    }
}
contract User {
    function doAddAuthorization(SingleSpotDebtCeilingSetter setter, address usr) public {
        setter.addAuthorization(usr);
    }
    function doAddManualSetter(SingleSpotDebtCeilingSetter setter, address usr) public {
        setter.addManualSetter(usr);
    }
}

contract SingleSpotDebtCeilingSetterTest is DSTest {
    Hevm hevm;

    MockOracleRelayer oracleRelayer;
    MockTreasury treasury;
    MockSAFEEngine safeEngine;
    DSToken systemCoin;
    SingleSpotDebtCeilingSetter ceilingSetter;

    User user;

    bytes32 collateralName = bytes32("ETH-A");
    uint256 baseUpdateCallerReward = 5 ether;
    uint256 maxUpdateCallerReward = 10 ether;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% per hour
    uint256 updateDelay = 1 hours;
    uint256 ceilingPercentageChange = 120;
    uint256 maxCollateralCeiling = 1000E45;
    uint256 minCollateralCeiling = 1E45;

    uint256 coinsToMint = 100E45;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        systemCoin = new DSToken("RAI", "RAI");
        treasury = new MockTreasury(address(systemCoin));

        safeEngine = new MockSAFEEngine();
        safeEngine.modifyParameters(collateralName, "accumulatedRate", 1E27);

        oracleRelayer = new MockOracleRelayer();

        systemCoin.mint(address(treasury), coinsToMint);

        ceilingSetter = new SingleSpotDebtCeilingSetter(
            address(safeEngine),
            address(oracleRelayer),
            address(treasury),
            collateralName,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            updateDelay,
            ceilingPercentageChange,
            maxCollateralCeiling,
            minCollateralCeiling
        );

        treasury.setTotalAllowance(address(ceilingSetter), uint(-1));
        treasury.setPerBlockAllowance(address(ceilingSetter), uint(-1));

        user = new User();
    }

    function test_verify_deployment() public {
        assertEq(ceilingSetter.maxCollateralCeiling(), maxCollateralCeiling);
        assertEq(ceilingSetter.minCollateralCeiling(), minCollateralCeiling);
        assertEq(ceilingSetter.ceilingPercentageChange(), ceilingPercentageChange);
        assertEq(ceilingSetter.lastUpdateTime(), 0);
        assertEq(ceilingSetter.updateDelay(), updateDelay);
        assertEq(ceilingSetter.lastManualUpdateTime(), now);
        assertEq(ceilingSetter.collateralName(), collateralName);
        assertEq(ceilingSetter.baseUpdateCallerReward(), baseUpdateCallerReward);
        assertEq(ceilingSetter.maxUpdateCallerReward(), maxUpdateCallerReward);
        assertEq(ceilingSetter.maxRewardIncreaseDelay(), uint(-1));
        assertEq(ceilingSetter.perSecondCallerRewardIncrease(), perSecondCallerRewardIncrease);

        assertEq(ceilingSetter.authorizedAccounts(address(this)), 1);
        assertEq(ceilingSetter.manualSetters(address(this)), 1);

        assertEq(address(ceilingSetter.safeEngine()), address(safeEngine));
        assertEq(address(ceilingSetter.treasury()), address(treasury));
    }
    function test_modify_parameters() public {
        MockTreasury newTreasury = new MockTreasury(address(systemCoin));

        ceilingSetter.modifyParameters("treasury", address(newTreasury));
        ceilingSetter.modifyParameters("baseUpdateCallerReward", 1);
        ceilingSetter.modifyParameters("maxUpdateCallerReward", 2);
        ceilingSetter.modifyParameters("perSecondCallerRewardIncrease", 1E27 + 1);
        ceilingSetter.modifyParameters("maxRewardIncreaseDelay", 10 hours);
        ceilingSetter.modifyParameters("updateDelay", 2 hours);
        ceilingSetter.modifyParameters("maxCollateralCeiling", 99E45);
        ceilingSetter.modifyParameters("minCollateralCeiling", 5);
        ceilingSetter.modifyParameters("ceilingPercentageChange", 250);
        ceilingSetter.modifyParameters("lastUpdateTime", now + 6 hours);

        assertEq(address(ceilingSetter.treasury()), address(newTreasury));
        assertEq(ceilingSetter.maxCollateralCeiling(), 99E45);
        assertEq(ceilingSetter.minCollateralCeiling(), 5);
        assertEq(ceilingSetter.ceilingPercentageChange(), 250);
        assertEq(ceilingSetter.lastUpdateTime(), now + 6 hours);
        assertEq(ceilingSetter.updateDelay(), 2 hours);
        assertEq(ceilingSetter.lastManualUpdateTime(), now);
        assertEq(ceilingSetter.collateralName(), collateralName);
        assertEq(ceilingSetter.baseUpdateCallerReward(), 1);
        assertEq(ceilingSetter.maxUpdateCallerReward(), 2);
        assertEq(ceilingSetter.maxRewardIncreaseDelay(), 10 hours);
        assertEq(ceilingSetter.perSecondCallerRewardIncrease(), 1E27 + 1);
    }
    function test_add_remove_manual_setters() public {
        ceilingSetter.addManualSetter(address(0x1));
        assertEq(ceilingSetter.manualSetters(address(0x1)), 1);
        ceilingSetter.removeManualSetter(address(0x1));
        assertEq(ceilingSetter.manualSetters(address(0x1)), 0);
    }
    function testFail_manual_setter_add_new_manual_setter() public {
        ceilingSetter.addManualSetter(address(user));
        assertEq(ceilingSetter.manualSetters(address(user)), 1);
        user.doAddManualSetter(ceilingSetter, address(0x1));
    }
    function testFail_add_remove_manual_setter_by_invalid_caller() public {
        user.doAddAuthorization(ceilingSetter, address(0x1));
    }
    function test_getNextCeiling_current_collateral_ceiling_zero() public {
        assertEq(ceilingSetter.getNextCollateralCeiling(), minCollateralCeiling);
    }
    function test_getNextCeiling_collateral_ceiling_positive_debt_amount_null() public {
        safeEngine.modifyParameters(collateralName, "debtCeiling", 1);
        assertEq(ceilingSetter.getNextCollateralCeiling(), minCollateralCeiling);
    }
    function test_getNextCeiling_current_collateral_ceiling_above_max() public {
        safeEngine.modifyParameters(collateralName, "debtCeiling", maxCollateralCeiling + 1);
        safeEngine.modifyParameters(collateralName, "debtAmount", maxCollateralCeiling / 1e27 + 1);
        assertEq(ceilingSetter.getNextCollateralCeiling(), maxCollateralCeiling);
    }
    function testFail_getNextCeiling_current_collateral_ceiling_max_uint() public {
        safeEngine.modifyParameters(collateralName, "debtCeiling", uint(-1));
        safeEngine.modifyParameters(collateralName, "debtAmount", uint(-1));
        assertEq(ceilingSetter.getNextCollateralCeiling(), maxCollateralCeiling);
    }
    function test_getNextCeiling_current_collateral_ceiling_increased() public {
        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling / 1e27);

        (uint256 debtAmount, uint256 accumulatedRate, uint256 safetyPrice, uint256 currentDebtCeiling,,) = safeEngine.collateralTypes(collateralName);
        assertEq(debtAmount, minCollateralCeiling / 1e27);
        assertEq(accumulatedRate, 1E27);
        assertEq(safetyPrice, 0);
        assertEq(currentDebtCeiling, minCollateralCeiling);

        assertEq(minCollateralCeiling * ceilingPercentageChange / 100, 1.2E45);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 1.2E45);
    }
    function test_getNextCeiling_current_collateral_ceiling_decreased() public {
        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 2 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 2.4E45);
    }
    function test_getNextCeiling_current_collateral_ceiling_decreased_negative_rate() public {
        oracleRelayer.modifyParameters("redemptionRate", 1E27 - 5);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 2 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 2.4E45);
    }
    function test_getNextCeiling_current_collateral_ceiling_decreased_positive_rate() public {
        oracleRelayer.modifyParameters("redemptionRate", 1E27 + 5);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 2 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 2.4E45);
    }
    function test_getNextCeiling_floor_higher_than_ceiling_higher_than_computed() public {
        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling / 1e27);
        safeEngine.modifyParameters(collateralName, "debtFloor", minCollateralCeiling * 5);

        assertEq(ceilingSetter.getNextCollateralCeiling(), minCollateralCeiling * 5);
    }
    function test_getNextCeiling_floor_higher_than_ceiling_lower_than_computed() public {
        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling / 1e27);
        safeEngine.modifyParameters(collateralName, "debtFloor", minCollateralCeiling + 10);

        assertEq(ceilingSetter.getNextCollateralCeiling(), 1.2E45);
    }
    function test_getNextCeiling_current_collateral_ceiling_decreased_negative_rate_block_decrease() public {
        oracleRelayer.modifyParameters("redemptionRate", 1E27 - 5);
        ceilingSetter.modifyParameters("blockDecreaseWhenDevalue", 1);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 2 / 1e27);

        assertTrue(!ceilingSetter.allowsDecrease(1E27 - 5, minCollateralCeiling * 5, ceilingSetter.getRawUpdatedCeiling()));
        assertTrue(!ceilingSetter.allowsIncrease(1E27 - 5, minCollateralCeiling * 5, ceilingSetter.getRawUpdatedCeiling()));
        assertEq(ceilingSetter.getNextCollateralCeiling(), minCollateralCeiling * 5);
    }
    function test_getNextCeiling_current_collateral_ceiling_decreased_positive_rate_block_decrease() public {
        oracleRelayer.modifyParameters("redemptionRate", 1E27 + 5);
        ceilingSetter.modifyParameters("blockDecreaseWhenDevalue", 1);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 2 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 2.4E45);
    }
    function test_getNextCeiling_current_collateral_ceiling_decreased_negative_rate_block_increase() public {
        oracleRelayer.modifyParameters("redemptionRate", 1E27 - 5);
        ceilingSetter.modifyParameters("blockIncreaseWhenRevalue", 1);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 2 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 2.4E45);
    }
    function test_getNextCeiling_current_collateral_ceiling_decreased_positive_rate_block_increase() public {
        oracleRelayer.modifyParameters("redemptionRate", 1E27 + 5);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 2 / 1e27);
        ceilingSetter.modifyParameters("blockIncreaseWhenRevalue", 1);

        assertTrue(ceilingSetter.allowsDecrease(1E27 + 5, minCollateralCeiling * 5, ceilingSetter.getRawUpdatedCeiling()));
        assertTrue(!ceilingSetter.allowsIncrease(1E27 + 5, minCollateralCeiling * 5, ceilingSetter.getRawUpdatedCeiling()));
        assertEq(ceilingSetter.getNextCollateralCeiling(), 2.4E45);
    }
    function test_getNextCeiling_current_collateral_ceiling_increased_negative_rate() public {
        oracleRelayer.modifyParameters("redemptionRate", 1E27 - 5);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 9 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 10.8E45);
    }
    function test_getNextCeiling_current_collateral_ceiling_increased_positive_rate() public {
        oracleRelayer.modifyParameters("redemptionRate", 1E27 + 5);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 6E45);

        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 9 / 1e27);
        assertEq(ceilingSetter.getNextCollateralCeiling(), 10.8E45);
    }
    function testFail_manual_update_twice_same_block() public {
        hevm.warp(now + 1);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);

        ceilingSetter.addManualSetter(address(this));
        ceilingSetter.manualUpdateCeiling();

        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, 6E45);
        assertEq(debtAmount, minCollateralCeiling * 5 / 1e27);
        assertEq(safeEngine.globalDebtCeiling(), 6E45);
        assertEq(ceilingSetter.lastManualUpdateTime(), now);

        ceilingSetter.manualUpdateCeiling();
    }
    function testFail_manual_update_invalid_caller() public {
        hevm.warp(now + 1);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);

        assertEq(ceilingSetter.manualSetters(address(this)), 0);
        ceilingSetter.manualUpdateCeiling();
    }
    function test_manual_update() public {
        hevm.warp(now + 1);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);

        ceilingSetter.addManualSetter(address(this));
        ceilingSetter.manualUpdateCeiling();

        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, 6E45);
        assertEq(debtAmount, minCollateralCeiling * 5 / 1e27);
        assertEq(safeEngine.globalDebtCeiling(), 6E45);
        assertEq(ceilingSetter.lastManualUpdateTime(), now);
    }
    function test_multi_manual_update() public {
        // Scenario
        uint256[5] memory debtAmounts = [
          uint(minCollateralCeiling * 5), uint(minCollateralCeiling * 3), uint(minCollateralCeiling * 35 / 10), uint(minCollateralCeiling * 38 / 10), uint(minCollateralCeiling * 41 / 10)
        ];
        uint256[5] memory resultingCeilings = [
          uint(6E45), uint(3.6E45), uint(4.2E45), uint(4.56E45), uint(4.92E45)
        ];
        uint256 initialCeiling = minCollateralCeiling * 5;
        uint256 maxResultingGlobalCeiling = 6E45;

        // Setup
        safeEngine.modifyParameters(collateralName, "debtCeiling", initialCeiling);
        ceilingSetter.addManualSetter(address(this));
        uint256 debtAmount; uint256 currentDebtCeiling;

        // Run
        for (uint i = 0; i < debtAmounts.length; i++) {
            hevm.warp(now + 1);

            safeEngine.modifyParameters(collateralName, "debtAmount", debtAmounts[i] / 1E27);
            ceilingSetter.manualUpdateCeiling();

            (debtAmount, , , currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
            assertEq(currentDebtCeiling, resultingCeilings[i]);
            assertEq(debtAmount, debtAmounts[i] / 1E27);
            assertEq(safeEngine.globalDebtCeiling(), maxResultingGlobalCeiling);
            assertEq(ceilingSetter.lastManualUpdateTime(), now);
        }
    }
    function test_manual_update_global_debt_max_uint() public {
        safeEngine.modifyParameters("globalDebtCeiling", uint(-1));

        // Scenario
        uint256[5] memory debtAmounts = [
          uint(minCollateralCeiling * 5), uint(minCollateralCeiling * 3), uint(minCollateralCeiling * 35 / 10), uint(minCollateralCeiling * 38 / 10), uint(minCollateralCeiling * 41 / 10)
        ];
        uint256[5] memory resultingCeilings = [
          uint(6E45), uint(3.6E45), uint(4.2E45), uint(4.56E45), uint(4.92E45)
        ];
        uint256 initialCeiling = minCollateralCeiling * 5;

        // Setup
        safeEngine.modifyParameters(collateralName, "debtCeiling", initialCeiling);
        ceilingSetter.addManualSetter(address(this));
        uint256 debtAmount; uint256 currentDebtCeiling;

        // Run
        for (uint i = 0; i < debtAmounts.length; i++) {
            hevm.warp(now + 1);

            safeEngine.modifyParameters(collateralName, "debtAmount", debtAmounts[i] / 1E27);
            ceilingSetter.manualUpdateCeiling();

            (debtAmount, , , currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
            assertEq(currentDebtCeiling, resultingCeilings[i]);
            assertEq(debtAmount, debtAmounts[i] / 1E27);
            assertEq(safeEngine.globalDebtCeiling(), uint(-1));
            assertEq(ceilingSetter.lastManualUpdateTime(), now);
        }
    }
    function test_manual_update_global_debt_below_new_ceiling() public {
        hevm.warp(now + 1);
        ceilingSetter.addManualSetter(address(this));

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);

        ceilingSetter.manualUpdateCeiling();

        safeEngine.modifyParameters("globalDebtCeiling", safeEngine.globalDebtCeiling() / 3);

        hevm.warp(now + 1);
        ceilingSetter.manualUpdateCeiling();
        assertEq(safeEngine.globalDebtCeiling(), 6E45);
    }
    function test_manual_update_max_ceiling_change() public {
        hevm.warp(now + 1);
        ceilingSetter.addManualSetter(address(this));

        safeEngine.modifyParameters(collateralName, "debtCeiling", maxCollateralCeiling);
        safeEngine.modifyParameters(collateralName, "debtAmount", maxCollateralCeiling / 1e27);

        ceilingSetter.manualUpdateCeiling();
        assertEq(safeEngine.globalDebtCeiling(), maxCollateralCeiling);

        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, maxCollateralCeiling);
        assertEq(debtAmount, maxCollateralCeiling / 1e27);

        hevm.warp(now + 1);
        safeEngine.modifyParameters("globalDebtCeiling", uint(-1));

        ceilingSetter.manualUpdateCeiling();
        assertEq(safeEngine.globalDebtCeiling(), uint(-1));

        (debtAmount, , , currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, maxCollateralCeiling);
        assertEq(debtAmount, maxCollateralCeiling / 1e27);
    }
    function testFail_auto_update_twice_same_block() public {
        hevm.warp(now + 1);

        ceilingSetter.autoUpdateCeiling(address(0x1));
        ceilingSetter.autoUpdateCeiling(address(0x1));
    }
    function testFail_auto_update_before_lastUpdateTime() public {
        hevm.warp(now + 1);
        ceilingSetter.autoUpdateCeiling(address(0x1));

        hevm.warp(now + ceilingSetter.updateDelay() + 1);
        ceilingSetter.modifyParameters("lastUpdateTime", now + 7 days);
        ceilingSetter.autoUpdateCeiling(address(0x1));
    }
    function test_auto_update() public {
        hevm.warp(now + 1);
        ceilingSetter.autoUpdateCeiling(address(0x1));

        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, minCollateralCeiling);
        assertEq(debtAmount, 0);

        assertEq(safeEngine.globalDebtCeiling(), minCollateralCeiling);
        assertEq(ceilingSetter.lastUpdateTime(), now);
        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward);
    }
    function test_auto_update_base_reward_null() public {
        ceilingSetter.modifyParameters("baseUpdateCallerReward", 0);

        hevm.warp(now + 1);
        ceilingSetter.autoUpdateCeiling(address(0x1));

        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, minCollateralCeiling);
        assertEq(debtAmount, 0);

        assertEq(safeEngine.globalDebtCeiling(), minCollateralCeiling);
        assertEq(ceilingSetter.lastUpdateTime(), now);
        assertEq(systemCoin.balanceOf(address(0x1)), 0);
    }
    function test_auto_update_twice_second_update_after_long_delay() public {
        ceilingSetter.modifyParameters("maxRewardIncreaseDelay", 10 hours);

        hevm.warp(now + 1);
        ceilingSetter.autoUpdateCeiling(address(0x1));
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling / 1E27);

        hevm.warp(now + 365 days);
        ceilingSetter.autoUpdateCeiling(address(0x1));

        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, minCollateralCeiling * ceilingPercentageChange / 100);
        assertEq(debtAmount, minCollateralCeiling / 1E27);

        assertEq(safeEngine.globalDebtCeiling(), minCollateralCeiling * ceilingPercentageChange / 100);
        assertEq(ceilingSetter.lastUpdateTime(), now);
        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward + maxUpdateCallerReward);
    }
    function test_multi_auto_update() public {
        safeEngine.modifyParameters("globalDebtCeiling", uint(-1));

        // Scenario
        uint256[5] memory debtAmounts = [
          uint(minCollateralCeiling * 5), uint(minCollateralCeiling * 3), uint(minCollateralCeiling * 35 / 10), uint(minCollateralCeiling * 38 / 10), uint(minCollateralCeiling * 41 / 10)
        ];
        uint256[5] memory resultingCeilings = [
          uint(6E45), uint(3.6E45), uint(4.2E45), uint(4.56E45), uint(4.92E45)
        ];
        uint256 initialCeiling = minCollateralCeiling * 5;

        // Setup
        safeEngine.modifyParameters(collateralName, "debtCeiling", initialCeiling);
        uint256 debtAmount; uint256 currentDebtCeiling;
        hevm.warp(now + 1);

        // Run
        for (uint i = 0; i < debtAmounts.length; i++) {
            safeEngine.modifyParameters(collateralName, "debtAmount", debtAmounts[i] / 1E27);
            ceilingSetter.autoUpdateCeiling(address(0x1));

            (debtAmount, , , currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
            assertEq(currentDebtCeiling, resultingCeilings[i]);
            assertEq(debtAmount, debtAmounts[i] / 1E27);
            assertEq(safeEngine.globalDebtCeiling(), uint(-1));
            assertEq(ceilingSetter.lastUpdateTime(), now);

            hevm.warp(now + updateDelay);
        }

        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward * debtAmounts.length);
    }
    function test_multi_auto_update_both_blocks_active_null_rate() public {
        safeEngine.modifyParameters("globalDebtCeiling", uint(-1));
        ceilingSetter.modifyParameters("blockIncreaseWhenRevalue", 1);
        ceilingSetter.modifyParameters("blockDecreaseWhenDevalue", 1);

        // Scenario
        uint256[5] memory debtAmounts = [
          uint(minCollateralCeiling * 5), uint(minCollateralCeiling * 3), uint(minCollateralCeiling * 35 / 10), uint(minCollateralCeiling * 38 / 10), uint(minCollateralCeiling * 41 / 10)
        ];
        uint256[5] memory resultingCeilings = [
          uint(6E45), uint(3.6E45), uint(4.2E45), uint(4.56E45), uint(4.92E45)
        ];
        uint256 initialCeiling = minCollateralCeiling * 5;

        // Setup
        safeEngine.modifyParameters(collateralName, "debtCeiling", initialCeiling);
        uint256 debtAmount; uint256 currentDebtCeiling;
        hevm.warp(now + 1);

        // Run
        for (uint i = 0; i < debtAmounts.length; i++) {
            safeEngine.modifyParameters(collateralName, "debtAmount", debtAmounts[i] / 1E27);
            ceilingSetter.autoUpdateCeiling(address(0x1));

            (debtAmount, , , currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
            assertEq(currentDebtCeiling, resultingCeilings[i]);
            assertEq(debtAmount, debtAmounts[i] / 1E27);
            assertEq(safeEngine.globalDebtCeiling(), uint(-1));
            assertEq(ceilingSetter.lastUpdateTime(), now);

            hevm.warp(now + updateDelay);
        }

        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward * debtAmounts.length);
    }
    function test_multi_auto_update_both_blocks_active_variable_rate_one() public {
        safeEngine.modifyParameters("globalDebtCeiling", uint(-1));
        ceilingSetter.modifyParameters("blockIncreaseWhenRevalue", 1);
        ceilingSetter.modifyParameters("blockDecreaseWhenDevalue", 1);

        // Scenario
        uint256[5] memory redemptionRates = [
          uint(1E27), uint(1E27 + 5), uint(1E27 - 5), uint(1E27 - 5), uint(1E27 + 5)
        ];
        uint256[5] memory debtAmounts = [
          uint(minCollateralCeiling * 5), uint(minCollateralCeiling * 3), uint(minCollateralCeiling * 35 / 10), uint(minCollateralCeiling * 38 / 10), uint(minCollateralCeiling * 36 / 10)
        ];
        uint256[5] memory resultingCeilings = [
          uint(6E45), uint(3.6E45), uint(4.2E45), uint(4.56E45), uint(4.32E45)
        ];
        uint256 initialCeiling = minCollateralCeiling * 5;

        // Setup
        safeEngine.modifyParameters(collateralName, "debtCeiling", initialCeiling);
        uint256 debtAmount; uint256 currentDebtCeiling;
        hevm.warp(now + 1);

        // Run
        for (uint i = 0; i < debtAmounts.length; i++) {
            oracleRelayer.modifyParameters("redemptionRate", redemptionRates[i]);
            safeEngine.modifyParameters(collateralName, "debtAmount", debtAmounts[i] / 1E27);
            ceilingSetter.autoUpdateCeiling(address(0x1));

            (debtAmount, , , currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
            assertEq(currentDebtCeiling, resultingCeilings[i]);
            assertEq(debtAmount, debtAmounts[i] / 1E27);
            assertEq(safeEngine.globalDebtCeiling(), uint(-1));
            assertEq(ceilingSetter.lastUpdateTime(), now);

            hevm.warp(now + updateDelay);
        }

        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward * debtAmounts.length);
    }
    function test_multi_auto_update_both_blocks_active_variable_rate_two() public {
        safeEngine.modifyParameters("globalDebtCeiling", uint(-1));
        ceilingSetter.modifyParameters("blockIncreaseWhenRevalue", 1);
        ceilingSetter.modifyParameters("blockDecreaseWhenDevalue", 1);

        // Scenario
        uint256[5] memory redemptionRates = [
          uint(1E27), uint(1E27 - 5), uint(1E27 + 5), uint(1E27 + 5), uint(1E27 - 5)
        ];
        uint256[5] memory debtAmounts = [
          uint(minCollateralCeiling * 5), uint(minCollateralCeiling * 3), uint(minCollateralCeiling * 7), uint(minCollateralCeiling * 8), uint(minCollateralCeiling * 2)
        ];
        uint256[5] memory resultingCeilings = [
          uint(6E45), uint(6E45), uint(6E45), uint(6E45), uint(6E45)
        ];
        uint256 initialCeiling = minCollateralCeiling * 5;

        // Setup
        safeEngine.modifyParameters(collateralName, "debtCeiling", initialCeiling);
        uint256 debtAmount; uint256 currentDebtCeiling;
        hevm.warp(now + 1);

        // Run
        for (uint i = 0; i < debtAmounts.length; i++) {
            oracleRelayer.modifyParameters("redemptionRate", redemptionRates[i]);
            safeEngine.modifyParameters(collateralName, "debtAmount", debtAmounts[i] / 1E27);
            ceilingSetter.autoUpdateCeiling(address(0x1));

            (debtAmount, , , currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
            assertEq(currentDebtCeiling, resultingCeilings[i]);
            assertEq(debtAmount, debtAmounts[i] / 1E27);
            assertEq(safeEngine.globalDebtCeiling(), uint(-1));
            assertEq(ceilingSetter.lastUpdateTime(), now);

            hevm.warp(now + updateDelay);
        }

        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward * debtAmounts.length);
    }
    function test_auto_update_debt_amount_drops_to_zero_then_back_up() public {
        hevm.warp(now + 1);
        ceilingSetter.autoUpdateCeiling(address(0x1));
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling / 0.5E27);

        hevm.warp(now + updateDelay);
        ceilingSetter.autoUpdateCeiling(address(0x1));
        safeEngine.modifyParameters(collateralName, "debtAmount", 0);

        hevm.warp(now + updateDelay);
        ceilingSetter.autoUpdateCeiling(address(0x1));

        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, minCollateralCeiling);
        assertEq(debtAmount, 0);
        assertEq(safeEngine.globalDebtCeiling(), 2.4E45);
        assertEq(ceilingSetter.lastUpdateTime(), now);
        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward * 3);

        hevm.warp(now + updateDelay);
        safeEngine.modifyParameters(collateralName, "debtAmount", 1);
        ceilingSetter.autoUpdateCeiling(address(0x1));

        (debtAmount, , , currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, 1E45);
        assertEq(debtAmount, 1);
        assertEq(safeEngine.globalDebtCeiling(), 2.4E45);
        assertEq(ceilingSetter.lastUpdateTime(), now);
        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward * 4);
    }
    function test_auto_update_global_debt_max_uint() public {
        safeEngine.modifyParameters("globalDebtCeiling", uint(-1));

        hevm.warp(now + 1);
        ceilingSetter.autoUpdateCeiling(address(0x1));

        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, minCollateralCeiling);
        assertEq(debtAmount, 0);

        assertEq(safeEngine.globalDebtCeiling(), uint(-1));
        assertEq(ceilingSetter.lastUpdateTime(), now);
        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward);
    }
    function test_auto_update_global_debt_below_new_ceiling() public {
        hevm.warp(now + 1);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);

        ceilingSetter.autoUpdateCeiling(address(0x1));
        safeEngine.modifyParameters("globalDebtCeiling", safeEngine.globalDebtCeiling() / 3);

        hevm.warp(now + updateDelay);
        ceilingSetter.autoUpdateCeiling(address(0x1));
        assertEq(safeEngine.globalDebtCeiling(), 6E45);
        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward * 2);
    }
    function test_auto_update_max_ceiling_change() public {
        hevm.warp(now + 1);

        ceilingSetter.modifyParameters("ceilingPercentageChange", 1000);
        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);

        ceilingSetter.autoUpdateCeiling(address(0x1));
        (uint256 debtAmount, , , uint256 currentDebtCeiling, ,) = safeEngine.collateralTypes(collateralName);
        assertEq(currentDebtCeiling, 50E45);
        assertEq(debtAmount, minCollateralCeiling * 5 / 1e27);

        assertEq(safeEngine.globalDebtCeiling(), 50E45);
        assertEq(ceilingSetter.lastUpdateTime(), now);
        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward);
    }
    function test_auto_update_global_debt_zero() public {
        hevm.warp(now + 1);

        safeEngine.modifyParameters(collateralName, "debtCeiling", minCollateralCeiling * 5);
        safeEngine.modifyParameters(collateralName, "debtAmount", minCollateralCeiling * 5 / 1e27);

        ceilingSetter.autoUpdateCeiling(address(0x1));
        safeEngine.modifyParameters("globalDebtCeiling", 0);

        hevm.warp(now + updateDelay);
        ceilingSetter.autoUpdateCeiling(address(0x1));
        assertEq(safeEngine.globalDebtCeiling(), 6E45);
        assertEq(systemCoin.balanceOf(address(0x1)), baseUpdateCallerReward * 2);
    }
}
