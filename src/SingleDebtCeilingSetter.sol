pragma solidity ^0.6.7;

import "geb-treasury-reimbursement/IncreasingTreasuryReimbursement.sol";

abstract contract SAFEEngineLike {
    function collateralTypes(bytes32) virtual public view returns (
        uint256 debtAmount,        // [wad]
        uint256 accumulatedRate,   // [ray]
        uint256 safetyPrice,       // [ray]
        uint256 debtCeiling        // [rad]
    );
    function globalDebtCeiling() virtual public view returns (uint256);
    function modifyParameters(
        bytes32 parameter,
        uint256 data
    ) virtual external;
    function modifyParameters(
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    ) virtual external;
}

contract SingleDebtCeilingSetter is IncreasingTreasuryReimbursement {
    // --- Auth ---
    mapping (address => uint256) public manualSetters;
    function addManualSetter(address account) external isAuthorized {
        manualSetters[account] = 1;
        emit AddAuthorization(account);
    }
    function removeManualSetter(address account) external isAuthorized {
        manualSetters[account] = 0;
        emit RemoveAuthorization(account);
    }
    modifier isManualSetter {
        require(manualSetters[msg.sender] == 1, "SingleDebtCeilingSetter/not-manual-setter");
        _;
    }

    // --- Variables ---
    // The max amount of system coins that can be generated using this collateral type
    uint256 public maxCollateralCeiling;            // [rad]
    // The min amount of system coins that must be generated using this collateral type
    uint256 public minCollateralCeiling;            // [rad]
    // Percentage change applied to the collateral's debt ceiling
    uint256 public ceilingPercentageChange;         // [hundred]
    // When the price feed was last updated
    uint256 public lastUpdateTime;                  // [timestamp]
    // Enforced gap between calls
    uint256 public updateDelay;                     // [seconds]
    // Last timestamp of a manual update
    uint256 public lastManualUpdateTime;            // [seconds]
    // The collateral's name
    bytes32 public collateralName;

    // The SAFEEngine contract
    SAFEEngineLike public safeEngine;

    // --- Events ---
    event AddManualSetter(address account);
    event RemoveManualSetter(address account);
    event UpdateCeiling(uint256 nextCeiling);

    constructor(
      address safeEngine_,
      address treasury_,
      bytes32 collateralName_,
      uint256 baseUpdateCallerReward_,
      uint256 maxUpdateCallerReward_,
      uint256 perSecondCallerRewardIncrease_,
      uint256 updateDelay_,
      uint256 ceilingPercentageChange_,
      uint256 maxCollateralCeiling_,
      uint256 minCollateralCeiling_
    ) public IncreasingTreasuryReimbursement(treasury_, baseUpdateCallerReward_, maxUpdateCallerReward_, perSecondCallerRewardIncrease_) {
        require(safeEngine_ != address(0), "SingleDebtCeilingSetter/invalid-safe-engine");
        require(updateDelay_ > 0, "SingleDebtCeilingSetter/invalid-update-delay");
        require(both(ceilingPercentageChange_ > HUNDRED, ceilingPercentageChange_ <= THOUSAND), "SingleDebtCeilingSetter/invalid-percentage-change");
        require(minCollateralCeiling_ > 0, "SingleDebtCeilingSetter/invalid-min-ceiling");
        require(both(maxCollateralCeiling_ > 0, maxCollateralCeiling_ > minCollateralCeiling_), "SingleDebtCeilingSetter/invalid-max-ceiling");

        manualSetters[msg.sender] = 1;

        safeEngine                = SAFEEngineLike(safeEngine_);
        collateralName            = collateralName_;
        updateDelay               = updateDelay_;
        ceilingPercentageChange   = ceilingPercentageChange_;
        maxCollateralCeiling      = maxCollateralCeiling_;
        minCollateralCeiling      = minCollateralCeiling_;
        lastManualUpdateTime      = now;

        emit ModifyParameters("updateDelay", updateDelay);
        emit ModifyParameters("ceilingPercentageChange", ceilingPercentageChange);
        emit ModifyParameters("maxCollateralCeiling", maxCollateralCeiling);
        emit ModifyParameters("minCollateralCeiling", minCollateralCeiling);
    }

    // --- Math ---
    uint256 constant HUNDRED  = 100;
    uint256 constant THOUSAND = 1000;

    // --- Boolean Logic ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Management ---
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        if (parameter == "treasury") {
          require(StabilityFeeTreasuryLike(addr).systemCoin() != address(0), "SingleDebtCeilingSetter/treasury-coin-not-set");
          treasury = StabilityFeeTreasuryLike(addr);
        }
        else revert("SingleDebtCeilingSetter/modify-unrecognized-param");
        emit ModifyParameters(
          parameter,
          addr
        );
    }
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        if (parameter == "baseUpdateCallerReward") {
          require(val <= maxUpdateCallerReward, "SingleDebtCeilingSetter/invalid-base-caller-reward");
          baseUpdateCallerReward = val;
        }
        else if (parameter == "maxUpdateCallerReward") {
          require(val >= baseUpdateCallerReward, "SingleDebtCeilingSetter/invalid-max-caller-reward");
          maxUpdateCallerReward = val;
        }
        else if (parameter == "perSecondCallerRewardIncrease") {
          require(val >= RAY, "SingleDebtCeilingSetter/invalid-caller-reward-increase");
          perSecondCallerRewardIncrease = val;
        }
        else if (parameter == "maxRewardIncreaseDelay") {
          require(val > 0, "SingleDebtCeilingSetter/invalid-max-increase-delay");
          maxRewardIncreaseDelay = val;
        }
        else if (parameter == "updateDelay") {
          require(val >= 0, "SingleDebtCeilingSetter/invalid-call-gap-length");
          updateDelay = val;
        }
        else if (parameter == "maxCollateralCeiling") {
          require(both(maxCollateralCeiling > 0, maxCollateralCeiling > minCollateralCeiling), "SingleDebtCeilingSetter/invalid-max-ceiling");
          maxCollateralCeiling = val;
        }
        else if (parameter == "minCollateralCeiling") {
          require(minCollateralCeiling > 0, "SingleDebtCeilingSetter/invalid-min-ceiling");
          minCollateralCeiling = val;
        }
        else if (parameter == "ceilingPercentageChange") {
          require(both(val > HUNDRED, val <= THOUSAND), "SingleDebtCeilingSetter/invalid-percentage-change");
          ceilingPercentageChange = val;
        }
        else if (parameter == "lastUpdateTime") {
          require(val > now, "SingleDebtCeilingSetter/invalid-update-time");
          lastUpdateTime = val;
        }
        else revert("SingleDebtCeilingSetter/modify-unrecognized-param");
        emit ModifyParameters(
          parameter,
          val
        );
    }

    // --- Utils ---
    function setCeiling(uint256 nextDebtCeiling) internal {
        (uint256 debtAmount, uint256 accumulatedRate, uint256 safetyPrice, uint256 currentDebtCeiling) = safeEngine.collateralTypes(collateralName);

        if (safeEngine.globalDebtCeiling() < nextDebtCeiling) {
            safeEngine.modifyParameters("globalDebtCeiling", nextDebtCeiling);
        }

        if (currentDebtCeiling != nextDebtCeiling) {
            safeEngine.modifyParameters(collateralName, "debtCeiling", nextDebtCeiling);
            emit UpdateCeiling(nextDebtCeiling);
        }
    }

    // --- Auto Updates ---
    function autoUpdateCeiling(address feeReceiver) external {
        // Check that the update time is not in the future
        require(lastUpdateTime < now, "SingleDebtCeilingSetter/update-time-in-the-future");
        // Check delay between calls
        require(either(subtract(now, lastUpdateTime) >= updateDelay, lastUpdateTime == 0), "SingleDebtCeilingSetter/wait-more");

        // Get the caller's reward
        uint256 callerReward = getCallerReward(lastUpdateTime, updateDelay);
        // Update lastUpdateTime
        lastUpdateTime = now;

        // Get the next ceiling and set it
        uint256 nextCollateralCeiling = getNextCollateralCeiling();
        setCeiling(nextCollateralCeiling);

        // Pay the caller for updating the rate
        rewardCaller(feeReceiver, callerReward);
    }

    // --- Manual Updates ---
    function manualUpdateCeiling() external isManualSetter {
        require(now > lastManualUpdateTime, "SingleDebtCeilingSetter/cannot-update-twice-same-block");
        uint256 nextCollateralCeiling = getNextCollateralCeiling();
        lastManualUpdateTime = now;
        setCeiling(nextCollateralCeiling);
    }

    // --- Getters ---
    function getNextCollateralCeiling() public view returns (uint256) {
        (uint256 debtAmount, uint256 accumulatedRate, uint256 safetyPrice, uint256 currentDebtCeiling) = safeEngine.collateralTypes(collateralName);
        uint256 adjustedCurrentDebt = multiply(debtAmount, accumulatedRate);

        if (either(currentDebtCeiling < minCollateralCeiling, debtAmount == 0)) return minCollateralCeiling;
        else if (currentDebtCeiling >= maxCollateralCeiling) return maxCollateralCeiling;

        uint256 updatedCeiling = multiply(adjustedCurrentDebt, ceilingPercentageChange) / HUNDRED;

        if (updatedCeiling < minCollateralCeiling) return minCollateralCeiling;
        else if (updatedCeiling > maxCollateralCeiling) return maxCollateralCeiling;

        return updatedCeiling;
    }
}
