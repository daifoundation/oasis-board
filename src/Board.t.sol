// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.0;

import "ds-test/test.sol";
import "./Board.sol";

contract ERC20Token {
    uint8   public decimals = 18;
    string  public symbol;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;

    constructor(string memory symbol_, uint8 decimals_) {
        symbol = symbol_;
        decimals = decimals_;
        balanceOf[msg.sender] = balanceOf[msg.sender] + 100000 ether;
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
        bool flexible_,
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
            expires: expires_,
            flexible: flexible_
        });
        id = board.make(o);
    }

    function make(
        bool buying_,
        ERC20Token baseTkn_, ERC20Token quoteTkn_,
        uint baseAmt_, uint price_,
        bool flexible_
    ) public returns (uint id, Order memory o) {
        return make(
            buying_, baseTkn_, quoteTkn_, baseAmt_, price_, flexible_, block.timestamp + 60 * 60
        );
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

   bool constant public ALL = false;
   bool constant public PARTIAL = true;

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
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, ALL);
        alice.cancel(id, o);
    }

    function testFailCancelOwnerOnly() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, ALL);
        bob.cancel(id, o);
    }

    function testCancelExpired() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, ALL);
        hevm.warp(block.timestamp + MINUTE() + 1);
        bob.cancel(id, o);
    }
}

contract TakeTest is BoardTest {
    function testTake() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, ALL);
        bob.take(id, 1 ether, o);
    }

    function testFailTakeFakePriceFails() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, ALL);
        o.price = o.price + 1;
        bob.take(id, 1 ether, o);
    }
}

contract AllOrNothingTakeTest is BoardTest {
    function testFailTakeAllOrNothing() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, ALL);
        bob.take(id, 0.5 ether, o);
    }
}

contract PartialTakeTest is BoardTest {
    function testTakePartial() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, PARTIAL);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
    }

    function testFailTakePartialCancel() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, PARTIAL);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        alice.cancel(id, o);
        bob.take(id, 0.5 ether, o);
    }

    function testFailTakeCantOvertakePartial() public {
        (uint id, Order memory o) = alice.make(BUY, tkn, dai, 1 ether, 10 ether, PARTIAL);
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
        o.baseAmt = o.baseAmt - 0.5 ether;
        bob.take(id, 0.5 ether, o);
    }
}