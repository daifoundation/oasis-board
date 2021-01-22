// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.7.6;
pragma abicoder v2;

// export DAPP_SOLC_VERSION=0.7.6
// nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_7_6

interface ERC20 {
    function transferFrom(address, address, uint) external returns (bool);
}

contract Board {

    struct Order {
        address baseTkn;
        address quoteTkn;
        uint baseDecimals;
        bool buying;
        address owner;
        uint expires;
        uint baseAmt;
        uint price;
    }

    event Make(uint id, Order order);
    event Take(uint id, uint baseAmt, uint quoteAmt);
    event Cancel(uint id);

    uint private nextId = 1;

    mapping (uint => bytes32) public orders;

    uint constant TTL = 14 * 24 * 60 * 60;

    function make(Order memory o) public returns (uint id) {
        o.expires = min(block.timestamp, min(o.expires, block.timestamp + TTL));
        id = nextId++;
        orders[id] = getHash(o);
        emit Make(id, o);
    }

    function take(uint id, uint baseAmt, Order memory o) public {
        require(orders[id] == getHash(o));
        require(o.expires > block.timestamp, 'board/expired');
        require(baseAmt <= o.baseAmt, 'board/base-too-big');

        uint quoteAmt = quote(baseAmt, o.price, o.baseDecimals);

        if(o.buying) {
            safeTransferFrom(ERC20(o.quoteTkn), o.owner, msg.sender, quoteAmt);
            safeTransferFrom(ERC20(o.baseAmt), msg.sender, o.owner, baseAmt);
        } else {
            safeTransferFrom(ERC20(o.quoteTkn), msg.sender, o.owner, quoteAmt);
            safeTransferFrom(ERC20(o.baseAmt), o.owner, msg.sender, baseAmt);
        }

        if(baseAmt < o.baseAmt) {
            o.baseAmt = o.baseAmt - baseAmt;
            orders[id] = getHash(o);
        } else {
            delete orders[id];
        }

        emit Take(id, baseAmt, quoteAmt);
    }

    function cancel(uint id, Order memory o) public {
        require(orders[id] == getHash(o));
        require(o.expires >= block.timestamp || o.owner == msg.sender);
        delete orders[id];
        emit Cancel(id);
    }

    function safeTransferFrom(ERC20 token, address from, address to, uint amount) private {
        uint256 size;
        assembly { size := extcodesize(token) }
        require(size > 0, "board/not-a-contract");

        bytes memory data = abi.encodeWithSelector(ERC20(token).transferFrom.selector, from, to, amount);
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "board/token-call-failed");
        if (returndata.length > 0) { // Return data is optional
            require(abi.decode(returndata, (bool)), "board/transferFrom failed");
        }
    }

    function getHash(Order memory o) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            o.baseTkn, o.quoteTkn, o.baseDecimals, o.buying, o.owner, o.expires, o.baseAmt, o.price
        ));
    }

    function quote(uint base, uint price, uint baseDecimals) private pure returns (uint q) {
        q = (base * price) / 10 ** uint(baseDecimals); //TODO: rounding
    }

    function min(uint a, uint b) private pure returns (uint) {
        return a < b ? a : b;
    }
}
