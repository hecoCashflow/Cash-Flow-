pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IOracle.sol";
import "./interfaces/IBoardroom.sol";
import "./interfaces/IBasisAsset.sol";
import "./lib/Babylonian.sol";
import "./lib/FixedPoint.sol";
import "./lib/Safe112.sol";
import "./owner/Operator.sol";
import "./utils/Epoch.sol";
import "./utils/ContractGuard.sol";

interface IERC20Decimals {
    function decimals() external pure returns (uint256);
}

/**
 * @title Basis Cash Treasury contract
 * @notice Monetary policy logic to adjust supplies of basis cash assets
 * @author Summer Smith & Rick Sanchez
 */
contract Treasury is ContractGuard, Epoch {
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using Safe112 for uint112;

    /* ========== STATE VARIABLES ========== */

    // ========== FLAGS
    bool public migrated = false;
    bool public initialized = false;

    // ========== CORE
    address public fund;
    address public cash;
    address public bond;
    address public share;
    address public boardroom;

    address public bondOracle;
    address public cashOracle;

    // ========== PARAMS
    uint256 public cashPriceOne;
    uint256 public cashPriceCeiling;
    uint256 public cashPriceFloor;
    uint256 public bondDepletionFloor;
    uint256 private accumulatedSeigniorage = 0;
    uint256 public fundAllocationRate = 10; // %
    uint256 public cashMateDecimals = 18;
    uint256 public rebaseBondRate = 1;

    // 上次蒸发的币种
    bool public lastRebaseIsCash;
    // 上次rebase的cash量
    uint256 public lastRebaseSupply;
    // 上次rebase量
    uint256 public lastRebaseCashSupply;
    uint256 public lastRebaseBondSupply;
    // 上次rebase价格
    uint256 public lastRebaseCashPrice;
    uint256 public lastRebaseBondPrice;
    
    uint256 public maxRedeemCob;
    uint256 public maxRedeemCoc;
    // lei'ji累积
    uint256 public accumulatedReddeemCob;
    uint256 public accumulatedReddeemCoc;
    uint256 public redeemPeriod;
    uint256 public redeemStartTime;

    // 累积销毁,铸币
    uint256 public accumulatedSwapCocBurn;
    uint256 public accumulatedSwapCocMint;

    uint256 public accumulatedSwapCobBurn;
    uint256 public accumulatedSwapCobMint;

    // 累积Rebase量
    uint256 public accumulatedRebaseTotalCob;
    uint256 public accumulatedRebaseTotalCoc;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _cash,
        address _bond,
        address _share,
        address _bondOracle,
        address _seigniorageOracle,
        address _boardroom,
        address _fund,
        uint256 _period,
        uint256 _startTime
    ) public Epoch(_period, _startTime, 0) {
        cash = _cash;
        bond = _bond;
        share = _share;
        bondOracle = _bondOracle;
        cashOracle = _seigniorageOracle;

        boardroom = _boardroom;
        fund = _fund;

        // 单个价格
        cashPriceOne = 10**18;
        // CASH价格上限
        // cashPriceCeiling = uint256(105).mul(cashPriceOne).div(10**2); //$1.05
        // // 消费券下限
        // bondDepletionFloor = uint256(95).mul(cashPriceOne);
        
        redeemPeriod = 0;
        redeemStartTime = _startTime;
    }

    /* =================== Modifier =================== */

    modifier checkMigration {
        require(!migrated, "Treasury: migrated");

        _;
    }

    modifier checkOperator {
        require(
            IBasisAsset(cash).operator() == address(this) &&
                IBasisAsset(bond).operator() == address(this) &&
                IBasisAsset(share).operator() == address(this) &&
                Operator(boardroom).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // budget
    function getReserve() public view returns (uint256) {
        return accumulatedSeigniorage;
    }

    // oracle
    function getBondOraclePrice() public view returns (uint256) {
        // return _getCashPrice(bondOracle);
        try IOracle(bondOracle).consult(bond, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert("Treasury: failed to consult bond price from the oracle");
        }
    }

    function getSeigniorageOraclePrice() public view returns (uint256) {
        // return _getCashPrice(cashOracle);
        try IOracle(cashOracle).consult(cash, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert("Treasury: failed to consult cash price from the oracle");
        }
    }

    function _getCashPrice(address oracle) internal view returns (uint256) {
        try IOracle(oracle).consult(cash, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert("Treasury: failed to consult cash price from the oracle");
        }
    }

    function cocCobRate() public view returns (uint256) {
        uint256 cob = getBondOraclePrice();
        uint256 coc = getSeigniorageOraclePrice();
        require(cob != 0, "COB为0");
        return (coc * 10**cashMateDecimals) / cob;
    }

    /* ========== GOVERNANCE ========== */

    function initialize() public {
        initializeWithAddr(address(0));
    }

    function initializeWithAddr(address _old) public checkOperator {
        require(!initialized, "Treasury: initialized");

        // burn all of it's balance
        IBasisAsset(cash).burn(IERC20(cash).balanceOf(address(this)));

        // set accumulatedSeigniorage to it's balance
        // CASH 全部设置为铸币税, 这个是余额
        accumulatedSeigniorage = IERC20(cash).balanceOf(address(this));

        // fix price issue, decimals are not the same
        if (_old != address(0)) {
            cashPriceOne = Treasury(_old).cashPriceOne();
        } else {
            cashPriceOne = cocCobRate();
        }

        // address mateToken = IOracle(bondOracle).token1();
        // if (mateToken == cash) {
        //     mateToken = IOracle(bondOracle).token0();
        // }

        // if (mateToken != address(0)) {
        //     cashMateDecimals = IERC20Decimals(mateToken).decimals();
        // }

        cashPriceCeiling = uint256(120).mul(cashPriceOne).div(10**2);
        cashPriceFloor = uint256(95).mul(cashPriceOne).div(10**2);

        // bondDepletionFloor = uint256(1000).mul(cashPriceOne);

        // 上周期默认价格
        lastRebaseCashPrice = getBondOraclePrice();
        lastRebaseBondPrice = getSeigniorageOraclePrice();

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setCashPriceCeiling(uint256 val) public onlyOperator {
        cashPriceCeiling = val;
    }

    function setCashPriceFloor(uint256 val) public onlyOperator {
        cashPriceFloor = val;
    }

    function migrate(address target) public onlyOperator checkOperator {
        require(!migrated, "Treasury: migrated");

        // cash
        Operator(cash).transferOperator(target);
        Operator(cash).transferOwnership(target);
        IERC20(cash).transfer(target, IERC20(cash).balanceOf(address(this)));

        // bond
        Operator(bond).transferOperator(target);
        Operator(bond).transferOwnership(target);
        IERC20(bond).transfer(target, IERC20(bond).balanceOf(address(this)));

        // share
        Operator(share).transferOperator(target);
        Operator(share).transferOwnership(target);
        IERC20(share).transfer(target, IERC20(share).balanceOf(address(this)));

        migrated = true;
        emit Migration(target);
    }

    function setFund(address newFund) public onlyOperator {
        fund = newFund;
        emit ContributionPoolChanged(msg.sender, newFund);
    }

    function setFundAllocationRate(uint256 rate) public onlyOperator {
        fundAllocationRate = rate;
        emit ContributionPoolRateChanged(msg.sender, rate);
    }

    function setOracle(address _bondOracle, address _seigniorageOracle)
        public
        onlyOperator
    {
        bondOracle = _bondOracle;
        cashOracle = _seigniorageOracle;
    }

    function setBoardroom(address boardroom_) public onlyOperator {
        boardroom = boardroom_;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    // 更新铸币价格
    function _updateCashPrice() internal {
        try IOracle(bondOracle).update() {} catch {}
        try IOracle(cashOracle).update() {} catch {}
    }

    // 购买债券, 提高价格
    function buyBonds(uint256 amount)
        external
        onlyOneBlock
        checkMigration
        checkStartTime
        checkOperator
    {
        require(amount > 0, "Treasury: cannot purchase bonds with zero amount");
        require(accumulatedReddeemCoc.add(amount) <= maxRedeemCoc, "accumulatedReddeemCoc.add(amount) <= maxRedeemCoc");

        uint256 cashPrice = cocCobRate();
        // require(cashPrice == targetPrice, 'Treasury: cash price moved');
        require(
            cashPrice < cashPriceFloor, // price < $1
            "Treasury: cashPrice must < cashPriceFloor"
        );

        uint256 bondPrice = cashPrice;

        // 销毁CASH
        IBasisAsset(cash).burnFrom(msg.sender, amount);
        // 增债券
        IBasisAsset(bond).mint(
            msg.sender,
            amount
            // amount.mul(cashPriceOne).div(bondPrice)
        );
        // 更新价格
        _updateCashPrice();
        
        accumulatedReddeemCoc = accumulatedReddeemCoc.add(amount);
        
        accumulatedSwapCocBurn = accumulatedSwapCocBurn.add(amount);
        accumulatedSwapCobMint = accumulatedSwapCobMint.add(amount);

        emit BoughtBonds(msg.sender, amount);
    }
    
    function redeemEndTime() public view returns (uint256) {
        return redeemStartTime.add(redeemPeriod.mul(3600));
    }
    
    function resetConfig() public {
        require(redeemEndTime() <= now, "redeemEndTime() <= now");
        
        redeemPeriod = redeemPeriod.add(1);
        maxRedeemCob = IBasisAsset(bond).totalSupply().mul(10).div(100);
        maxRedeemCoc = IBasisAsset(cash).totalSupply().mul(10).div(100);
        accumulatedReddeemCob = 0;
        accumulatedReddeemCoc = 0;
    }

    // 赎回债券, 降低价格
    function redeemBonds(uint256 amount)
        external
        onlyOneBlock
        checkMigration
        checkStartTime
        checkOperator
    {
        require(amount > 0, "Treasury: cannot redeem bonds with zero amount");
        require(accumulatedReddeemCob.add(amount) <= maxRedeemCob, "accumulatedReddeemCob.add(amount) <= maxRedeemCob");

        // 获取CASH价格
        uint256 cashPrice = cocCobRate();
        // require(cashPrice == targetPrice, 'Treasury: cash price moved');
        require(
            cashPrice > cashPriceCeiling, // price > $1.05
            "Treasury: cashPrice > cashPriceCeiling"
        );

        // 如果赎回金额超过最大金额, 则直接选择全部赎回
        accumulatedSeigniorage = accumulatedSeigniorage.sub(
            Math.min(accumulatedSeigniorage, amount)
        );

        // bond 销毁金额
        IBasisAsset(bond).burnFrom(msg.sender, amount);

        // CASH 新增金额
        IBasisAsset(cash).mint(msg.sender, amount);
        
        //
        _updateCashPrice();
        
        accumulatedReddeemCob = accumulatedReddeemCob.add(amount);

        accumulatedSwapCobBurn = accumulatedSwapCobBurn.add(amount);
        accumulatedSwapCocMint = accumulatedSwapCocMint.add(amount);

        emit RedeemedBonds(msg.sender, amount);
    }

    // 分配铸币税
    function allocateSeigniorage()
        external
        onlyOneBlock
        checkMigration
        checkStartTime
        checkEpoch
        checkOperator
    {

        if (IBoardroom(boardroom).totalSupply() <= 0) {
            return;
        }

        _updateCashPrice();
        // CASH价格
        // uint256 cashPrice = _getCashPrice(seigniorageOracle);
        // uint256 bondPrice = getBondOraclePrice(bo)

        uint256 cob = getBondOraclePrice();
        uint256 coc = getSeigniorageOraclePrice();
        require(cob != 0, "COB为0");

        lastRebaseCashPrice = coc;
        lastRebaseBondPrice = cob;

        uint256 rate = (coc * 10**cashMateDecimals) / cob;
        uint256 cashSupply = IERC20(cash).totalSupply();

        // 不超过 1.1
        // if (cashPrice <= cashPriceCeiling) {
        //     return; // just advance epoch instead revert
        // }

        // accumulatedSeigniorage: 累积z
        // if (IERC20(cash).totalSupply() <= accumulatedSeigniorage) {
        //     return;
        // }

        if (rate > cashPriceCeiling) {
            uint256 gap =
                cashSupply.mul(rate.sub(uint256(1 * 10**cashMateDecimals))).div(
                    10**cashMateDecimals
                );

            if (gap > 0) {
                IERC20(cash).approve(boardroom, gap);
                IBasisAsset(cash).mint(address(this), gap);
                IBoardroom(boardroom).allocateSeigniorage(gap);

                lastRebaseIsCash = true;
                lastRebaseCashSupply = gap;

                accumulatedRebaseTotalCoc = accumulatedRebaseTotalCoc.add(gap);
            }
        } else if (rate < cashPriceFloor) {
            // 1%
            uint256 gap = cashSupply.mul(uint256(rebaseBondRate)).div(100);

            if (gap > 0) {
                IERC20(bond).approve(boardroom, gap);
                IBasisAsset(bond).mint(address(this), gap);
                IBoardroom(boardroom).allocateSeigniorageBond(gap);

                lastRebaseIsCash = false;
                lastRebaseBondSupply = gap;

                accumulatedRebaseTotalCob = accumulatedRebaseTotalCob.add(gap);
            }
        }

        // circulating supply
        // totalSupply -
        // uint256 cashSupply = IERC20(cash).totalSupply().sub(accumulatedSeigniorage);
        // uint256 percentage = cashPrice.sub(cashPriceOne);
        // uint256 seigniorage = cashSupply.mul(percentage).div(10**cashMateDecimals);
        // IBasisAsset(cash).mint(address(this), seigniorage);
        // accumulatedSeigniorage = accumulatedSeigniorage.add(seigniorage);
        // emit TreasuryFunded(now, seigniorage);
        // // ======================== BIP-3
        // // 提成 10%
        // uint256 fundReserve = seigniorage.mul(fundAllocationRate).div(100);
        // if (fundReserve > 0) {
        //     IERC20(cash).safeTransfer(fund, fundReserve);
        //     emit ContributionPoolFunded(now, fundReserve);
        // }

        // // boardroom
        // uint256 boardroomReserve = seigniorage.sub(fundReserve);
        // if (boardroomReserve > 0) {
        //     // 授权董事会
        //     IERC20(cash).safeApprove(boardroom, boardroomReserve);
        //     //
        //     IBoardroom(boardroom).allocateSeigniorage(boardroomReserve);
        //     emit BoardroomFunded(now, boardroomReserve);
        // }
    }

    function setRebaseBondRate(uint256 rate) public onlyOperator {
        require(rate != 0, "比例不能为0");
        rebaseBondRate = rate;
    }

    // GOV
    event Initialized(address indexed executor, uint256 at);
    event Migration(address indexed target);
    event ContributionPoolChanged(address indexed operator, address newFund);
    event ContributionPoolRateChanged(
        address indexed operator,
        uint256 newRate
    );

    // CORE
    event RedeemedBonds(address indexed from, uint256 amount);
    event BoughtBonds(address indexed from, uint256 amount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event ContributionPoolFunded(uint256 timestamp, uint256 seigniorage);
}
