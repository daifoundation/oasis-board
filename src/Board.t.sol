// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.7.6;

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
