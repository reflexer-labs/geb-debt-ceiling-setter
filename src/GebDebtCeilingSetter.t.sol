pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebDebtCeilingSetter.sol";

contract GebDebtCeilingSetterTest is DSTest {
    GebDebtCeilingSetter setter;

    function setUp() public {
        setter = new GebDebtCeilingSetter();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
