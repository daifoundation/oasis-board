pragma solidity ^0.6.7;

interface ERC20 {
    function transferFrom(address, address, uint) external returns (bool);
}

contract Board {

    uint private lastId = 1;

    struct Order {
        bool     buying;
        address  owner;
        uint     expires;
        uint     baseAmt;
        uint     price;
    }

    mapping (uint => Order) public orders;

    uint constant TTL = 14 * 24 * 60 * 60;

    function getId(address baseTkn, address quoteTkn, uint baseDecimals, uint serial) public pure returns (uint) {
        return uint(keccak256(abi.encodePacked(baseTkn, quoteTkn, baseDecimals, serial)));
    }

    function quote(uint base, uint price, uint baseDecimals) internal pure returns (uint q) {
        q = (base * price) / 10 ** uint(baseDecimals);
        require((q * 10 ** uint(baseDecimals)) / price == base, 'board/quote-overflow');
    }

    function make(
        address baseTkn, address quoteTkn, uint baseDecimals, bool buying, uint baseAmt, uint price
    ) public returns (uint serial) {
        serial = lastId++;
        Order storage o = orders[getId(baseTkn, quoteTkn, baseDecimals, serial)];
        o.buying = buying;
        o.baseAmt = baseAmt;
        o.price = price;
        o.owner = msg.sender;
        o.expires = block.timestamp + TTL;
    }

    function take(
        address baseTkn, address quoteTkn, uint baseDecimals, uint serial, uint baseAmt
    ) public {
        uint id = getId(baseTkn, quoteTkn, baseDecimals, serial);
        Order storage o = orders[id];

        require(o.expires > block.timestamp, 'board/expired');
        require(baseAmt <= o.baseAmt, 'board/base-too-big');

        uint quoteAmt = quote(baseAmt, o.price, baseDecimals);

        // TODO: safe transfer!
        if(o.buying) {
            ERC20(quoteTkn).transferFrom(o.owner, msg.sender, quoteAmt);
            ERC20(baseAmt).transferFrom(msg.sender, o.owner, baseAmt);
        } else {
            ERC20(quoteTkn).transferFrom(msg.sender, o.owner, quoteAmt);
            ERC20(baseAmt).transferFrom(o.owner, msg.sender, baseAmt);
        }

        if(o.baseAmt < baseAmt) {
            o.baseAmt = o.baseAmt - baseAmt;
        } else {
            delete orders[id];
        }
    }

    function cancel(uint id) public {
        Order storage o = orders[id];
        require(o.expires >= block.timestamp || o.owner == msg.sender);
        delete orders[id];
    }
}
