// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >= 0.8.0;

import "ds-test/test.sol";
import "./Board.sol";

contract ERC20Token {
    uint8   public decimals = 18;
    string  public symbol;

    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;

    constructor(string memory symbol_, uint8 decimals_) {
        symbol = symbol_;
        decimals = decimals_;
        balanceOf[msg.sender] = 100000 ether;
    }

    function transfer(address dst, uint wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public returns (bool)
    {
        require(balanceOf[src] >= wad, "erc20/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != type(uint).max) {
            require(allowance[src][msg.sender] >= wad, "erc20/insufficient-allowance");
            allowance[src][msg.sender] = allowance[src][msg.sender] - wad;
        }
        balanceOf[src] = balanceOf[src] - wad;
        balanceOf[dst] = balanceOf[dst] + wad;
        return true;
    }

    function approve(address usr, uint wad) external returns (bool) {
        allowance[msg.sender][usr] = wad;
        return true;
    }
}

contract BoardTester {
    Board board;
    mapping (uint => Order) public orders;

    uint constant TTL = 14 * 24 * 60 * 60;

    constructor(Board board_) {
        board = board_;
    }

    function make(
        bool buying_,
        ERC20Token baseTkn_, ERC20Token quoteTkn_,
        uint baseAmt_, uint price_,
        uint minBaseAmt_,
        uint expires_
    ) public returns (uint id, Order memory o) {
        o = Order( {
            baseTkn: address(baseTkn_),
            quoteTkn: address(quoteTkn_),
            baseDecimals: baseTkn_.decimals(),
            buying: buying_,
            owner: address(this),
            baseAmt: baseAmt_,
            price: price_,
            minBaseAmt: minBaseAmt_,
            expires: expires_
        });
        id = board.make(o);
    }

    function make(
        bool buying_,
        ERC20Token baseTkn_, ERC20Token quoteTkn_,
        uint baseAmt_, uint price_,
        uint minBaseAmt_
    ) public returns (uint id, Order memory o) {
        return make(
            buying_, baseTkn_, quoteTkn_, baseAmt_, price_, minBaseAmt_, block.timestamp + 60 * 60
        );
    }

    function make(
        bool buying_,
        ERC20Token baseTkn_, ERC20Token quoteTkn_,
        uint baseAmt_, uint price_
    ) public returns (uint id, Order memory o) {
        return make(buying_, baseTkn_, quoteTkn_, baseAmt_, price_, baseAmt_);
    }

    function take(uint id, uint baseAmt, Order memory o) public {
        board.take(id, baseAmt, o);
    }

    function cancel(uint id, Order memory o) public  {
        board.cancel(id, o);
    }

    function approve(ERC20Token tkn, address usr, uint wad) external {
        tkn.approve(usr, wad);
    }
}

interface Hevm {
    function warp(uint256) external;
}

contract BoardTest is DSTest {
    Board board;

    ERC20Token dai;
    ERC20Token tkn;

    BoardTester alice;
    BoardTester bob;

    bool constant public BUY = true;
    bool constant public SELL = false;

     // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    Hevm hevm;

    function setUp() public {
        dai = new ERC20Token('DAI', 18);
        tkn = new ERC20Token('TKN', 18);

        board = new Board();

        alice = new BoardTester(board);
        bob = new BoardTester(board);

        alice.approve(dai, address(board), type(uint).max);
        alice.approve(tkn, address(board), type(uint).max);
        bob.approve(dai, address(board), type(uint).max);
        bob.approve(tkn, address(board), type(uint).max);

        dai.transfer(address(alice), 100 ether);
        dai.transfer(address(bob), 100 ether);

        tkn.transfer(address(alice), 100 ether);
        tkn.transfer(address(bob), 100 ether);

        hevm = Hevm(address(CHEAT_CODE));
    }

    function MINUTE() internal view returns (uint) {
        return block.timestamp + 60 * 60;
    }
}

contract CancelTest is BoardTest {
    function testCancel() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether);
        assertTrue(board.orders(id) != 0);
        alice.cancel(id, o);
        assertEq(board.orders(id), 0);
    }

    function testFailCancelOwnerOnly() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether);
        bob.cancel(id, o);
    }

    function testCancelExpired() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether);
        hevm.warp(block.timestamp + MINUTE() + 1);
        bob.cancel(id, o);
    }
}

contract TakeTest is BoardTest {
    function testTakeBuy() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether);
        assertEq(dai.balanceOf(address(bob)), 100 ether);
        assertEq(dai.balanceOf(address(alice)), 100 ether);
        assertEq(tkn.balanceOf(address(bob)), 100 ether);
        assertEq(tkn.balanceOf(address(alice)), 100 ether);
        bob.take(id, 1 ether, o);
        assertEq(dai.balanceOf(address(bob)), 110 ether);
        assertEq(dai.balanceOf(address(alice)), 90 ether);
        assertEq(tkn.balanceOf(address(bob)), 99 ether);
        assertEq(tkn.balanceOf(address(alice)), 101 ether);
    }

    function testTakeSell() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether);
        bob.take(id, 1 ether, o);
        assertEq(dai.balanceOf(address(bob)), 90 ether);
        assertEq(dai.balanceOf(address(alice)), 110 ether);
        assertEq(tkn.balanceOf(address(bob)), 101 ether);
        assertEq(tkn.balanceOf(address(alice)), 99 ether);
    }

    function testFailCantTakeFakePrice() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether);
        o.price = o.price + 1;
        bob.take(id, 1 ether, o);
    }

    function testFailCantTakeFakeAmount() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether);
        o.price = o.baseAmt + 1;
        bob.take(id, 1 ether, o);
    }

    function testFailCantTakeMoreThanPossible() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether);
        bob.take(id, 2 ether, o);
    }
}

contract AllOrNothingTakeTest is BoardTest {
    function testFailTakeBuyAllOrNothing() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether);
        bob.take(id, 0.5 ether, o);
    }
    function testFailTakeSellAllOrNothing() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether);
        bob.take(id, 0.5 ether, o);
    }
}

contract PartialTakeBuyTest is BoardTest {


    function testTakeBuyPartial() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
        assertEq(dai.balanceOf(address(bob)), 110 ether);
        assertEq(dai.balanceOf(address(alice)), 90 ether);
        assertEq(tkn.balanceOf(address(bob)), 99 ether);
        assertEq(tkn.balanceOf(address(alice)), 101 ether);
    }

    function testFailMinBaseGtBase() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, 11 ether);
    }

    function testFailTakeBuyPartialCancel() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        alice.cancel(id, o);
        bob.take(id, 0.5 ether, o);
    }

    function testFailTakeBuyCantOvertakePartial() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
    }

    function testFailCantTakeBuyLessThanMin() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.4 ether, o);
    }

    function testCanTakeBuyLessThanMinIfLast() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.6 ether, o);
        o.baseAmt = o.baseAmt - 0.6 ether;
        bob.take(id, 0.4 ether, o);
    }
}

contract PartialTakeSellTest is BoardTest {
    function testTakeSellPartial() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
        assertEq(dai.balanceOf(address(bob)), 90 ether);
        assertEq(dai.balanceOf(address(alice)), 110 ether);
        assertEq(tkn.balanceOf(address(bob)), 101 ether);
        assertEq(tkn.balanceOf(address(alice)), 99 ether);
    }

    function testFailMinBaseGtBase() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether, 11 ether);
    }

    function testFailTakeSellPartialCancel() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        alice.cancel(id, o);
        bob.take(id, 0.5 ether, o);
    }

    function testFailTakeSellCantOvertakePartial() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
    }

    function testFailCantTakeSellLessThanMin() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.4 ether, o);
    }

    function testCanTakeSellLessThanMinIfLast() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether, 0.5 ether);
        bob.take(id, 0.6 ether, o);
        o.baseAmt = o.baseAmt - 0.6 ether;
        bob.take(id, 0.4 ether, o);
    }
}

contract RoundingTest is BoardTest {
    function testRoundingSell() public {
        (uint id, Order memory o) =
            alice.make(SELL, tkn, dai, 1 ether, 0.333333333333333333 ether, 1);
        uint daiBalance = dai.balanceOf(address(bob));
        bob.take(id, 0.1 ether, o);
        assertEq(daiBalance - dai.balanceOf(address(bob)), 0.033333333333333334 ether);
    }

    function testRoundingRoundSell() public {
        (uint id, Order memory o) =
            alice.make(SELL, tkn, dai, 1 ether, 10 ether, 1);
        uint daiBalance = dai.balanceOf(address(bob));
        bob.take(id, 0.1 ether, o);
        assertEq(daiBalance - dai.balanceOf(address(bob)), 1 ether);
    }

    function testRoundingBuy() public {
        (uint id, Order memory o) =
            alice.make(BUY, tkn, dai, 1 ether, 0.333333333333333333 ether, 1);
        uint daiBalance = dai.balanceOf(address(bob));
        bob.take(id, 0.1 ether, o);
        assertEq(dai.balanceOf(address(bob)) - daiBalance, 0.033333333333333333 ether);
    }

    function testRoundingRoundBuy() public {
        (uint id, Order memory o) =
            alice.make(BUY, tkn, dai, 1 ether, 10 ether, 1);
        uint daiBalance = dai.balanceOf(address(bob));
        bob.take(id, 0.1 ether, o);
        assertEq(dai.balanceOf(address(bob)) - daiBalance, 1 ether);
    }
}

contract ExpirationTest is BoardTest {
    function testFailTooSoon() public {
        alice.make(SELL, tkn, dai, 1 ether, 10 ether, 1, block.timestamp - 1);
    }
    function testFailTooLate() public {
        alice.make(SELL, tkn, dai, 1 ether, 10 ether, 1, block.timestamp + board.TTL() + 1);
    }

    function testTakeInTime() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether, 1, block.timestamp + 10);
        hevm.warp(block.timestamp + 5);
        bob.take(id, 0.5 ether, o);
    }

        function testFailCantTakeExpired() public {
        (uint id, Order memory o) = alice.make(SELL, tkn, dai, 1 ether, 10 ether, 1, block.timestamp + 10);
        hevm.warp(block.timestamp + 11);
        bob.take(id, 0.5 ether, o);
    }
}
