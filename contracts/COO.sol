pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol';
import './owner/Operator.sol';

contract COO is ERC20Burnable, Operator {
    /**
     * @notice Constructs the Basis Bond ERC-20 contract.
     */
    constructor() public ERC20('Cash Flow Equity', 'COO') {
        // _mint(msg.sender, 2 * 10**18); //修改初始铸币量 TODO
        _mint(msg.sender, 1000002 * 10**18);
    }

    /**
     * @notice Operator mints basis bonds to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of basis bonds to mint to
     * @return whether the process has been done
     */
    // function mint(address recipient_, uint256 amount_)
    //     public
    //     onlyOperator
    //     returns (bool)
    // {
    //     uint256 balanceBefore = balanceOf(recipient_);
    //     _mint(recipient_, amount_);
    //     uint256 balanceAfter = balanceOf(recipient_);

    //     return balanceAfter > balanceBefore;
    // }

    // function burn(uint256 amount) public override onlyOperator {
    //     super.burn(amount);
    // }

    // function burnFrom(address account, uint256 amount)
    //     public
    //     override
    //     onlyOperator
    // {
    //     super.burnFrom(account, amount);
    // }
}
