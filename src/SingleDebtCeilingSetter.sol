pragma solidity ^0.6.7;

abstract contract SAFEEngineLike {
    function modifyParameters(
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    ) external;
}
abstract contract StabilityFeeTreasuryLike {
    function getAllowance(address) virtual external view returns (uint, uint);
    function systemCoin() virtual external view returns (address);
    function pullFunds(address, address, uint) virtual external;
}

contract SingleDebtCeilingSetter {
    // --- Auth ---
    mapping (address => uint256) public authorizedAccounts;
    function addAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    function removeAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "SingleDebtCeilingSetter/account-not-authorized");
        _;
    }

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
    // Percentage change applied to the collateral's debt ceiling
    uint256 public ceilingPercentageChange;         // [hundred]
    // When the price feed was last updated
    uint256 public lastUpdateTime;                  // [timestamp]
    // Enforced gap between calls
    uint256 public updateDelay;                     // [seconds]
    // Starting reward for the feeReceiver of a updateRate call
    uint256 public baseUpdateCallerReward;          // [wad]
    // Max possible reward for the feeReceiver of a updateRate call
    uint256 public maxUpdateCallerReward;           // [wad]
    // Max delay taken into consideration when calculating the adjusted reward
    uint256 public maxRewardIncreaseDelay;          // [seconds]
    // Rate applied to baseUpdateCallerReward every extra second passed beyond updateDelay seconds since the last updateRate call
    uint256 public perSecondCallerRewardIncrease;   // [ray]
    // The collateral's name
    bytes32 public collateralName;

    // The SAFEEngine contract
    SAFEEngineLike public safeEngine;
    // The treasury contract
    StabilityFeeTreasuryLike public treasury;

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event AddManualSetter(address account);
    event RemoveManualSetter(address account);
    event ModifyParameters(
        bytes32 parameter,
        uint256 val
    );
    event ModifyParameters(
        bytes32 parameter,
        address addr
    );

    constructor(
      address safeEngine_,
      address treasury_,
      bytes32 collateralName_,
      uint256 baseUpdateCallerReward_,
      uint256 maxUpdateCallerReward_,
      uint256 perSecondCallerRewardIncrease_,
      uint256 updateDelay_,
      uint256 ceilingPercentageChange_,
      uint256 maxCollateralCeiling_
    ) public {
        require(safeEngine_ != address(0), "SingleDebtCeilingSetter/invalid-safe-engine");
        if (address(treasury_) != address(0)) {
          require(StabilityFeeTreasuryLike(treasury_).systemCoin() != address(0), "SingleDebtCeilingSetter/treasury-coin-not-set");
        }
        require(maxUpdateCallerReward_ >= baseUpdateCallerReward_, "SingleDebtCeilingSetter/invalid-max-caller-reward");
        require(perSecondCallerRewardIncrease_ >= RAY, "SingleDebtCeilingSetter/invalid-per-second-reward-increase");
        require(updateDelay_ > 0, "SingleDebtCeilingSetter");
        require(both(ceilingPercentageChange_ > HUNDRED, ceilingPercentageChange_ <= THOUSAND), "SingleDebtCeilingSetter/invalid-percentage-change");
        require(maxCollateralCeiling_ > 0, "SingleDebtCeilingSetter/invalid-max-ceiling");

        authorizedAccounts[msg.sender]  = 1;
        safeEngine                      = SAFEEngineLike(safeEngine_);
        treasury                        = StabilityFeeTreasuryLike(treasury_);
        collateralName                  = collateralName_;
        baseUpdateCallerReward          = baseUpdateCallerReward_;
        maxUpdateCallerReward           = maxUpdateCallerReward_;
        perSecondCallerRewardIncrease   = perSecondCallerRewardIncrease_;
        updateDelay                     = updateDelay_;
        ceilingPercentageChange         = ceilingPercentageChange_;
        maxCollateralCeiling            = maxCollateralCeiling_;
        maxRewardIncreaseDelay          = uint(-1);

        emit AddAuthorization(msg.sender);
        emit ModifyParameters("treasury", treasury_);
        emit ModifyParameters("baseUpdateCallerReward", baseUpdateCallerReward);
        emit ModifyParameters("maxUpdateCallerReward", maxUpdateCallerReward);
        emit ModifyParameters("perSecondCallerRewardIncrease", perSecondCallerRewardIncrease);
        emit ModifyParameters("updateDelay", updateDelay);
        emit ModifyParameters("ceilingPercentageChange", ceilingPercentageChange);
        emit ModifyParameters("maxCollateralCeiling", maxCollateralCeiling);
        emit ModifyParameters("maxRewardIncreaseDelay", maxRewardIncreaseDelay);
    }

    // --- Math ---
    uint256 constant HUNDRED  = 100;
    uint256 constant THOUSAND = 1000;
    uint256 constant RAY      = 10**27;

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
          maxCollateralCeiling = val;
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

    // --- Treasury ---
    /**
    * @notice This returns the stability fee treasury allowance for this contract by taking the minimum between the per block and the total allowances
    **/
    function treasuryAllowance() public view returns (uint256) {
        (uint total, uint perBlock) = treasury.getAllowance(address(this));
        return minimum(total, perBlock);
    }
    /*
    * @notice Get the SF reward that can be sent to the updateRate() caller right now
    */
    function getCallerReward() public view returns (uint256) {
        uint256 timeElapsed = (lastUpdateTime == 0) ? updateDelay : subtract(now, lastUpdateTime);
        if (timeElapsed < updateDelay) {
            return 0;
        }
        uint256 adjustedTime = subtract(timeElapsed, updateDelay);
        uint256 maxReward    = minimum(maxUpdateCallerReward, treasuryAllowance() / RAY);
        if (adjustedTime > maxRewardIncreaseDelay) {
            return maxReward;
        }
        uint256 baseReward   = baseUpdateCallerReward;
        if (adjustedTime > 0) {
            baseReward = rmultiply(rpower(perSecondCallerRewardIncrease, adjustedTime, RAY), baseReward);
        }
        if (baseReward > maxReward) {
            baseReward = maxReward;
        }
        return baseReward;
    }
    /**
    * @notice Send a stability fee reward to an address
    * @param proposedFeeReceiver The SF receiver
    * @param reward The system coin amount to send
    **/
    function rewardCaller(address proposedFeeReceiver, uint256 reward) internal {
        if (address(treasury) == proposedFeeReceiver) return;
        if (address(treasury) == address(0) || reward == 0) return;
        address finalFeeReceiver = (proposedFeeReceiver == address(0)) ? msg.sender : proposedFeeReceiver;
        try treasury.pullFunds(finalFeeReceiver, treasury.systemCoin(), reward) {}
        catch(bytes memory revertReason) {
            emit FailRewardCaller(revertReason, finalFeeReceiver, reward);
        }
    }

    
}
