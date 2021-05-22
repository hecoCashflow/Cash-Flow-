pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./owner/Operator.sol";

interface CrowdsaleERC20 {
    
    function balanceOf(address account) external view returns (uint256);
}

contract Vote is Operator {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address public coo;

    uint256 private _totalTickets;
    mapping(address => uint256) private _voteTickets;
    mapping(address => bool) private applications;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    
    uint256 lockedTime = 24 hours; //锁仓时间 TODO
    
    struct Transaction {
        uint256 timestamp;
        uint256 amount;
        bool withdrawn;
    }

    mapping (address=>Transaction[]) stakeLogs;
    
    constructor(address _coo) public {
        coo = _coo;
    }
    
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
      
    function buyTicket(uint256 number) public {
        require(number > 0, "must > 0");
        
        _totalTickets = _totalTickets.add(number);
        _voteTickets[msg.sender] = _voteTickets[msg.sender].add(number);
        
        uint256 amount = number;
        
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        IERC20(coo).safeTransferFrom(msg.sender, address(this), amount);

        Transaction memory newLogs = Transaction({
            timestamp: block.timestamp,
            amount: amount,
            withdrawn: false
        });
        stakeLogs[msg.sender].push(newLogs);        
    }
    
    function invokeTicket() public {
        require(_voteTickets[msg.sender] > 0, "votes is empty");
        require(applications[msg.sender], "no auth");
        _totalTickets = _totalTickets.sub(1);
        _voteTickets[msg.sender] = _voteTickets[msg.sender].sub(1);
    }
    
    function withdraw() public {
        uint256 total = 0;
        for (uint256 i = 0; i < stakeLogs[msg.sender].length; i++) {
            if (stakeLogs[msg.sender][i].timestamp + lockedTime <= block.timestamp) {
                if (stakeLogs[msg.sender][i].withdrawn == false) {
                    total = total.add(stakeLogs[msg.sender][i].amount);
                    stakeLogs[msg.sender][i].withdrawn = true;
                }
            }
        }
        
        require(total != 0, "avaliable stake == 0");

        _totalSupply = _totalSupply.sub(total);
        _balances[msg.sender] = _balances[msg.sender].sub(total);
        IERC20(coo).safeTransfer(msg.sender, total);
    }
    
    function unlockStaked(address account) public view returns(uint256) {
        uint256 total = 0;
        for(uint256 i = 0; i < stakeLogs[account].length; i++) {
            if (stakeLogs[account][i].timestamp + lockedTime <= block.timestamp) {
                if (stakeLogs[account][i].withdrawn == false) {
                    total = total.add(stakeLogs[account][i].amount);
                } 
            }
        }
        return total;
    }
    
    function approve(address who) public onlyOperator {
        applications[who] = true;
    }
    
    function unapprove(address who) public onlyOperator {
        applications[who] = false;
    }
    
    function totalTickets() public view returns (uint256) {
        return _totalTickets;
    }

    function voteTicketsOf(address account) public view returns (uint256) {
        return _voteTickets[account];
    }
    
    function isApprove(address who) public view returns (bool) {
        return applications[who];
    }
}