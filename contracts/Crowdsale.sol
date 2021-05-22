pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./owner/Operator.sol";

interface CrowdsaleERC20 {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint256);
}

contract Crowdsale is Operator {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address public coo;
    address public usdt;

    uint256 public startTime;
    uint256 public endTime;
    
    uint256 public _totalSupply;
    mapping(address => uint256) private _balances;
    uint256 public maxSupply;
    uint256 public accountMaxCrow;
    
    constructor(address _coo, address _usdt, uint256 _startTime, uint256 _endTime, uint256 _maxSupply) public {
        require(_endTime > _startTime, "_endTime > _startTime");
        startTime = _startTime;
        endTime = _endTime;
        coo = _coo;
        usdt = _usdt;
        maxSupply = _maxSupply;
        accountMaxCrow = 1000 * (10 ** CrowdsaleERC20(usdt).decimals());
    }
    
    function crow(uint256 amount) public checkTime checkBanlance(msg.sender) {
        /// 募资金额 > 0
        require(amount > 0, "amount must > 0");
        /// 不超过总募资金额
        require(_totalSupply.add(amount) <= maxSupply, "supply overwrit");
        /// USDT精度
        uint256 usdtUint = CrowdsaleERC20(usdt).decimals();
        /// 单人募资金额不超过 1000 USDT
        require(_balances[msg.sender].add(amount) <= accountMaxCrow, "one account max crow usdt");
        /// 总量增加
        _totalSupply = _totalSupply.add(amount);
        /// 记录余额
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        /// USDT授权转账
        IERC20(usdt).safeTransferFrom(msg.sender, address(this), amount);
        /// 计算COO金额
        uint256 cooAmount = amount.mul(CrowdsaleERC20(coo).decimals()).div(usdtUint);
        /// COO转账
        IERC20(coo).safeTransfer(msg.sender, cooAmount);
    }
    
    modifier checkTime() {
        require(block.timestamp <= endTime, "did end");
        require(block.timestamp >= startTime, "not start");
        _;
    }
    
    modifier checkBanlance(address account) {
        require(CrowdsaleERC20(coo).balanceOf(account) >= 3 * 10**18, "coo balance must >= 3");
        _;
    }

    function withdraw(address to) public onlyOperator {
        require(block.timestamp > endTime, "not end");
        require(_totalSupply > 0, "totlaSupple must > 0");
        IERC20(usdt).safeTransfer(to, _totalSupply);
        _totalSupply = 0;
    }
    
    function getStartTime() public view returns (uint256) {
        return startTime;
    }
    
    function getEndTime() public view returns (uint256) {
        return endTime;
    }
    
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function setAccountMaxCrow(uint256 newMax) public onlyOperator {
        accountMaxCrow = newMax;
    }
}