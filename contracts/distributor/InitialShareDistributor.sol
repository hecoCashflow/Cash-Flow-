pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IDistributor.sol";
import "../interfaces/IRewardDistributionRecipient.sol";

contract InitialShareDistributor is IDistributor {
    using SafeMath for uint256;

    event Distributed(address pool, uint256 cashAmount);
    event Withdrawal(address user, uint256 amount);

    bool public once = true;

    IERC20 public share;

    IRewardDistributionRecipient public LPPool1;
    uint256 public InitialBalance1;

    IRewardDistributionRecipient public LPPool2;
    uint256 public InitialBalance2;

    IRewardDistributionRecipient public LPPool3;
    uint256 public InitialBalance3;

    IRewardDistributionRecipient public LPPool4;
    uint256 public InitialBalance4;

    constructor(
        IERC20 _share,
        IRewardDistributionRecipient _LPPool1,
        uint256 _InitialBalance1,
        IRewardDistributionRecipient _LPPool2,
        uint256 _InitialBalance2,
        IRewardDistributionRecipient _LPPool3,
        uint256 _InitialBalance3,
        IRewardDistributionRecipient _LPPool4,
        uint256 _InitialBalance4
    ) public {
        share = _share;

        LPPool1 = _LPPool1;
        InitialBalance1 = _InitialBalance1;

        LPPool2 = _LPPool2;
        InitialBalance2 = _InitialBalance2;

        LPPool3 = _LPPool3;
        InitialBalance3 = _InitialBalance3;

        LPPool4 = _LPPool4;
        InitialBalance4 = _InitialBalance4;
    }

    function distribute() public override {
        require(
            once,
            "InitialShareDistributor: you cannot run this function twice"
        );

        // share.transfer(address(daibacLPPool), daibacInitialBalance);
        // daibacLPPool.notifyRewardAmount(daibacInitialBalance);
        // emit Distributed(address(daibacLPPool), daibacInitialBalance);

        // share.transfer(address(daibasLPPool), daibasInitialBalance);
        // daibasLPPool.notifyRewardAmount(daibasInitialBalance);
        // emit Distributed(address(daibasLPPool), daibasInitialBalance);

        // share.transfer(address(bas1Pool), bas1InitialBalance);
        // bas1Pool.notifyRewardAmount(bas1InitialBalance);
        // emit Distributed(address(bas1Pool), bas1InitialBalance);

        // share.transfer(address(bas2Pool), bas2InitialBalance);
        // bas1Pool.notifyRewardAmount(bas2InitialBalance);
        // emit Distributed(address(bas2Pool), bas2InitialBalance);

        share.transfer(address(LPPool1), InitialBalance1);
        LPPool1.notifyRewardAmount(InitialBalance1);
        emit Distributed(address(LPPool1), InitialBalance1);

        share.transfer(address(LPPool2), InitialBalance2);
        LPPool2.notifyRewardAmount(InitialBalance2);
        emit Distributed(address(LPPool2), InitialBalance2);

        share.transfer(address(LPPool3), InitialBalance3);
        LPPool3.notifyRewardAmount(InitialBalance3);
        emit Distributed(address(LPPool3), InitialBalance3);

        share.transfer(address(LPPool4), InitialBalance4);
        LPPool4.notifyRewardAmount(InitialBalance4);
        emit Distributed(address(LPPool4), InitialBalance4);

        once = false;
    }
}
