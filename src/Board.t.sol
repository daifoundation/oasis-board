pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./Board.sol";

contract BoardTest is DSTest {
    Board board;

    function setUp() public {
        board = new Board();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
