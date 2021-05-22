pragma solidity ^0.6.0;

// File: @openzeppelin/contracts/math/Math.sol

import "@openzeppelin/contracts/math/Math.sol";

// File: @openzeppelin/contracts/math/SafeMath.sol

import "@openzeppelin/contracts/math/SafeMath.sol";

// File: @openzeppelin/contracts/utils/Address.sol

import "@openzeppelin/contracts/utils/Address.sol";

// File: @openzeppelin/contracts/token/ERC20/SafeERC20.sol

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// File: contracts/IRewardDistributionRecipient.sol

import "../interfaces/IRewardDistributionRecipient.sol";

contract TokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public token;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public payable virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        if (address(token) != address(0)) {
            token.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function withdraw(uint256 amount) public virtual {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        if (address(token) == address(0)) {
            safeTransferETH(msg.sender, amount);
        } else {
            token.safeTransfer(msg.sender, amount);
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }
}

interface IERC20Decimals {
    function decimals() external pure returns (uint256);
}

contract CashPool is TokenWrapper, IRewardDistributionRecipient {
    IERC20 public basisCash;
    uint256 public DURATION = 5 days; /// 挖矿周期
    uint256 public decimals = 18;
    uint256 public starttime;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public maximum;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public deposits;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(
        address basisCash_,
        address token_,
        uint256 starttime_
    ) public {
        require(basisCash_ != address(0),  "basisCash_ is a zero address");

        basisCash = IERC20(basisCash_);
        token = IERC20(token_);
        starttime = starttime_;
        if (token_ != address(0)) {
            decimals = IERC20Decimals(token_).decimals();
        }
        maximum = uint256(20000).mul(10**decimals);
    }

    modifier checkStart() {
        require(block.timestamp >= starttime, "CashPool: not start");
        _;
    }

    modifier updateReward(address account) {
        // 单位奖励
        rewardPerTokenStored = rewardPerToken();
        // 上次更新时间, 不超过结束时间
        lastUpdateTime = lastTimeRewardApplicable();
        // 非主币
        if (account != address(0)) {
            // 将临时奖励归档到累积奖励中
            rewards[account] = earned(account);
            // 
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function initialize(uint256 starttime_, uint256 maximum_) public onlyOwner {
        require(maximum_ != 0, "maximum_ is a zero");
        starttime = starttime_;
        maximum = maximum_;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }

        // 

        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount)
        public
        payable
        override
        updateReward(msg.sender)
        checkStart
    {
        if (address(token) == address(0)) {
            amount = msg.value;
        }
        require(amount > 0, "CashPool: Cannot stake 0");
        uint256 newDeposit = deposits[msg.sender].add(amount);
        require(
            newDeposit <= maximum,
            "CashPool: deposit amount exceeds maximum"
        );
        deposits[msg.sender] = newDeposit;
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stakeETH() public payable updateReward(msg.sender) checkStart {
        require(msg.value > 0, "CashPool: Cannot stake 0");
        require(address(token) == address(0), "CashPool: invalid token");
        uint256 newDeposit = deposits[msg.sender].add(msg.value);
        require(
            newDeposit <= maximum,
            "CashPool: deposit amount exceeds maximum"
        );
        deposits[msg.sender] = newDeposit;
        super.stake(msg.value);
        emit Staked(msg.sender, msg.value);
    }

    function withdraw(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, "CashPool: Cannot withdraw 0");
        deposits[msg.sender] = deposits[msg.sender].sub(amount);
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) checkStart {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            basisCash.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // 通知奖励数目
    function notifyRewardAmount(uint256 reward)
        external
        override
        onlyRewardDistribution
        updateReward(address(0))
    {

        if (block.timestamp > starttime) {
            if (block.timestamp >= periodFinish) {
                rewardRate = reward.div(DURATION);
            } else {
                // 在周期内剩余时间
                uint256 remaining = periodFinish.sub(block.timestamp);
                // 剩余时间 * 每秒奖励 = 周期剩余时间内奖励
                uint256 leftover = remaining.mul(rewardRate);
                // 剩余周期内添加奖励, 增加单位时间奖励
                rewardRate = reward.add(leftover).div(DURATION);
            }
            // 从当前时间重新开启新周期
            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp.add(DURATION);
            emit RewardAdded(reward);
        } else {
            /// 每秒奖励
            rewardRate = reward.div(DURATION);
            /// 记录更新时间
            lastUpdateTime = starttime;
            /// 结束时间
            periodFinish = starttime.add(DURATION);
            emit RewardAdded(reward);
        }
    }
}
