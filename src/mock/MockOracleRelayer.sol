pragma solidity 0.6.7;

contract MockOracleRelayer {
    uint256 public redemptionRate;

    constructor() public {
        redemptionRate = 10 ** 27;
    }

    function modifyParameters(bytes32 parameter, uint256 value) external {
        redemptionRate = value;
    }
}
