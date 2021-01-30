// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.0;

interface ERC20 {
    function transferFrom(address, address, uint) external returns (bool);
    function decimals() external returns (uint8);
}

struct Order {
    address baseTkn;
    address quoteTkn;
    uint8 baseDecimals;
    bool buying;
    address owner;
    uint expires;
    uint baseAmt;
    uint price;
    bool flexible;
}

contract Board {
    event Make(uint id, Order order);
    event Take(uint id, uint baseAmt, uint quoteAmt);
    event Cancel(uint id);

    uint private next = 1;

    mapping (uint => bytes32) public orders;

    uint constant TTL = 14 * 24 * 60 * 60;

    function make(Order calldata o) external returns (uint id) {
        require(o.expires > block.timestamp && o.expires < block.timestamp + TTL);
        require(o.owner == msg.sender);
        // o.expires = min(o.expires, block.timestamp + TTL);
        id = next++;
        orders[id] = getHash(o);
        emit Make(id, o);
    }

    function take(uint id, uint baseAmt, Order calldata o) external {
        require(orders[id] == getHash(o), 'board/wrong-hash');
        require(o.expires > block.timestamp, 'board/expired');
        require(baseAmt <= o.baseAmt, 'board/base-too-big');
        require(o.flexible || baseAmt == o.baseAmt, 'board/flexible-not-allowed');

        uint baseOne = 10 ** uint(o.baseDecimals);
        uint roundingCorrection = !o.buying ? baseOne / 2 : 0;
        uint quoteAmt = (baseAmt * o.price + roundingCorrection) / baseOne;

        if(o.buying) {
            safeTransferFrom(ERC20(o.quoteTkn), o.owner, msg.sender, quoteAmt);
            safeTransferFrom(ERC20(o.baseTkn), msg.sender, o.owner, baseAmt);
        } else {
            safeTransferFrom(ERC20(o.quoteTkn), msg.sender, o.owner, quoteAmt);
            safeTransferFrom(ERC20(o.baseTkn), o.owner, msg.sender, baseAmt);
        }

        if(baseAmt < o.baseAmt) {
            Order memory n = o;
            n.baseAmt = n.baseAmt - baseAmt;
            orders[id] = getHash(n);
        } else {
            delete orders[id];
        }

        emit Take(id, baseAmt, quoteAmt);
    }

    function cancel(uint id, Order calldata o) external {
        require(orders[id] == getHash(o), 'board/wrong-hash');
        require(o.expires < block.timestamp || o.owner == msg.sender, 'board/invalid-cancel');
        delete orders[id];
        emit Cancel(id);
    }

    function safeTransferFrom(ERC20 token, address from, address to, uint amount) private {
        uint256 size;
        assembly { size := extcodesize(token) }
        require(size > 0, "board/not-a-contract");

        bytes memory data = abi.encodeWithSelector(
            ERC20(token).transferFrom.selector, from, to, amount
        );
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "board/token-call-failed");
        if (returndata.length > 0) { // Return data is optional
            require(abi.decode(returndata, (bool)), "board/transferFrom failed");
        }
    }

    function getHash(Order memory o) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            o.baseTkn, o.quoteTkn, o.baseDecimals,
            o.buying, o.owner, o.expires, o.baseAmt,
            o.price, o.flexible
        ));
    }

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
