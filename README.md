# Bulletin Board

Simple bulletin board for security tokens.

General idea: do as little as necessary at the smart contract level, delegate as much as possible to the frontend.

Hence there is very limited functionality in the smart contract: only order sharing, and atomic token swap (with partial fills). Due to the facts that addresses can be whitelisted and that funds can be force transfered at any moment there is no token escrow. There is no guarantee that settlement will succeed.

The only assumption about security contract is that it is possible for board contract to administer transferFrom on behalf makers and takers ( allowance needs to be given for board contract address).

## Architecture

3 methods supported: `make`, `take`, `cancel`.

To save gas, instead of order, hash of order is stored in the smart contract. To operate on the order, order data needs to be provided in `take` and `cancel` calls. Hash stored in smart contract is used as a tamper protection.

Nonobvious consequence of above hash based gas saving approach is that practically only one operation on given order per block is possible. Partial taker needs to know current state of the order that she wants to interact with. So of two partial takes of given order only one will succeed. Which means that hash based approach makes sense for low traffic markets. Otherwise gas saved in makes will be consumend by failed takes.

To make order discovery possible on every operation [events](./src/Board.sol#L22) are emmited. Users are expected to reconstruct board state from contract history:
`board state` = `created orders` - `settled orders` - `canceled orders`

### Order model
Each order is given a unique id.

```
struct Order {
    address baseTkn;
    address quoteTkn;
    uint8 baseDecimals;
    bool buying;
    address owner;
    uint expires; // timestamp
    uint baseAmt;
    uint price;
    uint minBaseAmt;
}
```
See [src/Board.sol](src/Board.sol#L9).

Where:
- **baseTkn** - address of base token
- **quoteTkn** - address of quote token
- **baseDecimals** - decimals of base token
- **buying** - trade direction `true` = buy, `false` = sell
- **owner** - owner of the order, ie maker
- **expires** - order is valid until expiration date
- **baseAmt** - amount of base token
- **price** - price in quote currency
- **minBaseAmt** - minimum take amount

### Partial fills
If `minBaseAmt` < `baseAmount` then partial fills are allowed and take amount needs to meet following condition: `baseAmt >= o.minBaseAmt || baseAmt == o.baseAmt`.

### Rounding
Only quote amounts are rounded, never base. Potential loss related to rounding is always on taker's side.

See [examples in tests](./src/Board.t.sol#L312).

## API

### make
`function make(Order calldata o) external returns (uint id)`

Creates an order. Returns unique order id.

Order existence gives the board contract a right to manipulate order owner funds. Make method determines order ownership based on `msg.sender`. Alernatively signature based ownership model might be used, although it is not implemented.

### take
`function take(uint id, uint baseAmt, Order calldata o)`

Take `baseAmt` from order identified by `id`. Since no order data is stored in the sc, order data needs to be provided as extra argument `o`.

Settlement is not guaranteed. There are several reasons for why settlement might fail:
- allowance not set
- lack of funds
- transfer restrictions

All of this conditions are verified implicitly at the moment of settelment. If settlment fails transaction is reverted and order is left on the board. In order to provide good user experience frontends should filter out orders that does not meet above conditions and will fail during settlement.


### cancel
`function cancel(uint id, Order calldata o)`

Cancel order identified by `id`. Since no order data is stored in the sc, order data needs to be provided as extra argument `o`. Only order owners can cancel non expired orders.

## Gas usage
- **constructor** - [1,419,488](https://kovan.etherscan.io/tx/0xc4e6d2b251526343fc6c1ddb76d5c68e98075d5e33fd447ae3983b43ea0a0829)
- **make** - [61,300](https://kovan.etherscan.io/tx/0x5cdfe5c28906d098225d10d83edd407996374f562c079d39329b68bda2d67f1c)
- **make partial** - [61,324](https://kovan.etherscan.io/tx/0xfeb2953109dc685cdeee661484d91975eaaa31939da783837b44a9b866bf5632)
- **take all** - [64,258](https://kovan.etherscan.io/tx/0xd17dd9cf19e32365d424dc119e4a0f39f325eb726a9f9f3ec57354b829c0cea2)
- **take partial** - [83,828](https://kovan.etherscan.io/tx/0xa6ff121bfafc0b0d8485e88cac5f2ac019d3a9a45c80da709f557bb6e3b949fe)
- **cancel** - [21,100](https://kovan.etherscan.io/tx/0xd5102025fee9455c5491f069c841b7ea20c5ff7340e9b35b69a5b9318af5f2a7)

## Development notes
### Set solc version
```
export DAPP_SOLC_VERSION=0.8.0
```

### Install solc 0.8.0
```
nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_8_0
```
