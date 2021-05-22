pragma solidity ^0.6.12;
//pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./lib/Safe112.sol";
import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IBoardroom.sol";

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public share;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        share.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 directorShare = _balances[msg.sender];
        require(
            directorShare >= amount,
            "Boardroom: withdraw request greater than staked amount"
        );
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = directorShare.sub(amount);
        share.safeTransfer(msg.sender, amount);
    }
}

contract Boardroom is ShareWrapper, ContractGuard, Operator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using Safe112 for uint112;

    /* ========== DATA STRUCTURES ========== */
    struct Boardseat {
        // 最新的记录索引
        uint256 lastSnapshotIndex;
        // 总奖励
        uint256 rewardEarned;
    }

    struct BoardSnapshot {
        // 时间戳
        uint256 time;
        // 总奖励
        uint256 rewardReceived;
        // 单股奖励
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    IERC20 private cash;
    IERC20 private bond;

    // 董事成员
    mapping(address => Boardseat) private directors;
    // bond董事会
    mapping(address => Boardseat) private bondDirectors;
    // COC 记录
    BoardSnapshot[] private boardHistory;
    // COB 记录
    BoardSnapshot[] private bondBoardHistory;

    constructor(
        IERC20 _cash,
        IERC20 _share,
        IERC20 _bond
    ) public {
        cash = _cash;
        share = _share;
        bond = _bond;

        // 初始化Cash记录
        BoardSnapshot memory _cashSnap =
            BoardSnapshot({
                time: block.number,
                rewardReceived: 0,
                rewardPerShare: 0
            });
        boardHistory.push(_cashSnap);

        // 初始化Bond记录
        BoardSnapshot memory _bondSnap =
            BoardSnapshot({
                time: block.number,
                rewardReceived: 0,
                rewardPerShare: 0
            });
        bondBoardHistory.push(_bondSnap);
    }

    /* ========== Modifiers =============== */
    modifier directorExists {
        require(
            balanceOf(msg.sender) > 0,
            "Boardroom: The director does not exist"
        );
        _;
    }

    // 更新奖励
    modifier updateReward(address director) {
        // 确保地址不为空
        if (director != address(0)) {
            // 通过地址搜索董事成员, 更新并替换
            Boardseat memory seat = directors[director];
            seat.rewardEarned = earned(director);
            seat.lastSnapshotIndex = cashHistoryLastSnapshotIndex();
            directors[director] = seat;

            // 更新bond董事会信息
            Boardseat memory seat2 = bondDirectors[director];
            seat2.rewardEarned = bondEarned(director);
            seat2.lastSnapshotIndex = bondHistoryLastSnapshotIndex();
            bondDirectors[director] = seat2;
        }

        _;
    }

    // function totalSupply2() public view returns (uint256) {
    //     return totalSupply();
    // }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    // function latestSnapshotIndex() public view returns (uint256) {
    //     return boardHistory.length.sub(1);
    // }

    // function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
    //     return boardHistory[latestSnapshotIndex()];
    // }

    // 获取最新快照索引
    // function lastSnapshotIndexOf(BoardSnapshot[] memory history) public view returns (uint256) {
    //     return history.length.sub(1);
    // }

    // // 获取最新快照对象
    // function lastSnapshotOf(BoardSnapshot[] memory history) public view returns(uint256) {
    //     return history[lastSnapshotIndexOf(history)];
    // }
    

    function cashHistoryLastSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function cashHistoryLastSnapshot()
        internal
        view
        returns (BoardSnapshot memory)
    {
        return boardHistory[cashHistoryLastSnapshotIndex()];
    }

    function bondHistoryLastSnapshotIndex() public view returns (uint256) {
        return bondBoardHistory.length.sub(1);
    }

    function bondHistoryLastSnapshot()
        internal
        view
        returns (BoardSnapshot memory)
    {
        return bondBoardHistory[bondHistoryLastSnapshotIndex()];
    }

    function cashLastSnapshotInDirectors(address who)
        internal
        view
        returns (BoardSnapshot memory)
    {
        uint256 index = directors[who].lastSnapshotIndex;
        return boardHistory[index];
    }

    function bondLastSnapshotInDirectors(address who)
        internal
        view
        returns (BoardSnapshot memory)
    {
        uint256 index = bondDirectors[who].lastSnapshotIndex;
        return bondBoardHistory[index];
    }

    // 获取董事成员最后交易记录索引 idx
    // function getLastSnapshotIndexOf(address director)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     return directors[director].lastSnapshotIndex;
    // }

    // function lastSnapsshotIndexOfDirectors(
    //     address who,
    //     mapping(address => Boardseat) memory ds
    // ) public view returns (uint256) {
    //     return ds[who].lastSnapshotIndex;
    // }

    // function lastSnapsshotOfDirectors(
    //     address who,
    //     mapping(address => Boardseat) ds
    // ) public view returns (BoardSnapshot memory) {
    //     return ds[lastSnapsshotIndexOfDirectors(who, ds)];
    // }

    // 通过董事地址获取当前董事成员最后的交易记录
    // function getLastSnapshotOf(address director)
    //     internal
    //     view
    //     returns (BoardSnapshot memory)
    // {
    //     return boardHistory[getLastSnapshotIndexOf(director)];
    // }

    // =========== Director getters
    // 每股奖励
    // function rewardPerShare() public view returns (uint256) {
    //     return getLatestSnapshot().rewardPerShare;
    // }

    // // 获取应对的奖励
    function earned(address director) public view returns (uint256) {
        // 董事记录最后的奖励
        uint256 latestRPS = cashHistoryLastSnapshot().rewardPerShare;
        // 当前董事最后的奖励
        uint256 storedRPS =
            cashLastSnapshotInDirectors(director).rewardPerShare;

        // director * (lastert - stored) / 10^18 + 之前的奖励和
        return
            balanceOf(director).mul(latestRPS.sub(storedRPS)).div(1e18).add(
                directors[director].rewardEarned
            );
    }

    function bondEarned(address director) public view returns (uint256) {
        // 董事记录最后的奖励
        uint256 latestRPS = bondHistoryLastSnapshot().rewardPerShare;
        // 当前董事最后的奖励
        uint256 storedRPS =
            bondLastSnapshotInDirectors(director).rewardPerShare;

        return
            balanceOf(director).mul(latestRPS.sub(storedRPS)).div(1e18).add(
                directors[director].rewardEarned
            );
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount)
        public
        override
        onlyOneBlock
        updateReward(msg.sender)
    {
        require(amount > 0, "Boardroom: Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        onlyOneBlock
        directorExists
        updateReward(msg.sender)
    {
        require(amount > 0, "Boardroom: Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        claimReward();
        clainBondReward();
    }

    // 索要全部奖励
    function claimReward() public updateReward(msg.sender) {
        uint256 reward = directors[msg.sender].rewardEarned;
        if (reward > 0) {
            directors[msg.sender].rewardEarned = 0;
            cash.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function clainBondReward() public updateReward(msg.sender) {
        uint256 bondReward = bondDirectors[msg.sender].rewardEarned;
        if (bondReward > 0) {
            // 清空累积奖励
            bondDirectors[msg.sender].rewardEarned = 0;
            // 给自己转账
            bond.safeTransfer(msg.sender, bondReward);
            emit RewardPaid(msg.sender, bondReward);
        }
    } 

    //
    function allocateSeigniorage(uint256 amount)
        external
        onlyOneBlock
        onlyOperator
    {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(
            totalSupply() > 0,
            "Boardroom: Cannot allocate when totalSupply is 0"
        );
        
        // Create & add new snapshot
        // uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        // uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));
        BoardSnapshot memory newSnapshot =
            BoardSnapshot({
                time: block.number,
                rewardReceived: amount,
                rewardPerShare: cashHistoryLastSnapshot().rewardPerShare.add(
                    amount.mul(1e18).div(totalSupply())
                )
            });
        boardHistory.push(newSnapshot);
        cash.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardAdded(msg.sender, amount);
    }

    // Bond提取
    function allocateSeigniorageBond(uint256 amount)
        external
        onlyOneBlock
        onlyOperator
    {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(
            totalSupply() > 0,
            "Boardroom: Cannot allocate when totalSupply is 0"
        );

        BoardSnapshot memory _newBondSnap =
            BoardSnapshot({
                time: block.number,
                rewardReceived: amount,
                rewardPerShare: bondHistoryLastSnapshot().rewardPerShare.add(
                    amount.mul(1e18).div(totalSupply())
                )
            });
        bondBoardHistory.push(_newBondSnap);
        bond.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardAdded(msg.sender, amount);
    }
    

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
}