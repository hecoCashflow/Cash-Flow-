pragma solidity ^0.6.0;

import "./COO.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface ICrowdsale {
    function balanceOf(address account) external view returns (uint256);
}

interface IAirDropERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract AirDrop is Operator {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
   
    struct RewardGetStatus {
        bool didJoinCrowdsale;
        bool cooCosLpTokenGt10;
        bool cooGt100;
        bool cocGt100;
        bool cobGt100;
        bool cosGt1;
    }
    
    address public coo;
    address public coc;
    address public cob;
    address public cos;
    address public cooCocLp;
    address public crowdsale;
    uint256 public startTime2;
    
    mapping(address => bool) rewardLogs1;
    mapping(address => RewardGetStatus) rewardLogs2;
    
    // bool public theSecondStageBegin = true;
    
    uint256 public _totalSupply1 = 15000 * 10**18;
    uint256 public _totalSupply2 = 35000 * 10**18;
    
    uint256 public oneReward = 5 * 10**18;
    
    constructor(address _coo, address _coc, address _cob, address _cos, address _cooCocLp, address _crowdsale, uint256 _startTime2) public {
        coo = _coo;
        coc = _coc;
        cob = _cob;
        cos = _cos;
        cooCocLp = _cooCocLp;
        crowdsale = _crowdsale;
        startTime2 = _startTime2;
    }
    
    function totalReward1() public view returns (uint256) {
        return oneReward;
    }
    
    function totalReward2() public view returns(uint256) {
        require(theSecondStageBegin(), "theSecondStageBegin is false");
        uint256 _total = 0;
        RewardGetStatus memory status = rewardLogs2[msg.sender];
        if (status.didJoinCrowdsale == false && checkDidJoinCrowdsale(msg.sender)) {
            _total = _total.add(oneReward);
        }
        if (status.cooCosLpTokenGt10 == false && checkCooCoCLpTokenGt10(msg.sender)) {
            _total = _total.add(oneReward);
        }
        if (status.cooGt100 == false && checkCooGt100(msg.sender)) {
            _total = _total.add(oneReward);
        }
        if (status.cocGt100 == false && checkCocGt100(msg.sender)) {
            _total = _total.add(oneReward);
        }
        if (status.cobGt100 == false && checkCobGt100(msg.sender)) {
            _total = _total.add(oneReward);
        }
        if (status.cosGt1 == false && checkCosGt1(msg.sender)) {
            _total = _total.add(oneReward);
        }
        return _total;
    }
    
    function exchangedReward1(address who) public onlyOperator {
        require(_totalSupply1 > oneReward, "_totalSupply1 > oneReward");
        require(rewardLogs1[who] == false, "you did get reward");
        _totalSupply1 = _totalSupply1.sub(oneReward);
        rewardLogs1[who] = true;
        IERC20(coo).safeTransfer(who, oneReward);
    }
    
    function statusExchangd1(address who) public view returns (bool) {
        return rewardLogs1[who];
    }
    
    function canExchangedReward1(address who) public view returns (bool) {
        return (_totalSupply1 > oneReward) && (statusExchangd1(who) == false);
    }
    
    function exchangedAllReward2() public {
        require(theSecondStageBegin(), "theSecondStageBegin is false");
        RewardGetStatus memory status = rewardLogs2[msg.sender];
        
        uint256 _total = 0;
        if (status.didJoinCrowdsale == false && checkDidJoinCrowdsale(msg.sender)) {
            status.didJoinCrowdsale = true;
            _total = _total.add(oneReward);
        }
        if (status.cooCosLpTokenGt10 == false && checkCooCoCLpTokenGt10(msg.sender)) {
            status.cooCosLpTokenGt10 = true;
            _total = _total.add(oneReward);
        }
        if (status.cooGt100 == false && checkCooGt100(msg.sender)) {
            status.cooGt100 = true;
            _total = _total.add(oneReward);
        }
        if (status.cocGt100 == false && checkCocGt100(msg.sender)) {
            status.cocGt100 = true;
            _total = _total.add(oneReward);
        }
        if (status.cobGt100 == false && checkCobGt100(msg.sender)) {
            status.cobGt100 = true;
            _total = _total.add(oneReward);
        }
        if (status.cosGt1 == false && checkCosGt1(msg.sender)) {
            status.cosGt1 = true;
            _total = _total.add(oneReward);
        }
        require(_total > 0, "total2 must gt 0");
        require(_totalSupply2 > _total, "_totalSupply2 bu gou le");
        
        _totalSupply2 = _totalSupply2.sub(_total);
        IERC20(coo).safeTransfer(msg.sender, _total);
        rewardLogs2[msg.sender] = status;
    }
    
    function theSecondStageBegin() public view returns (bool) {
        return block.timestamp >= startTime2;
    }
    
    function checkDidJoinCrowdsale(address who) public view returns (bool) {
        return ICrowdsale(crowdsale).balanceOf(who) > 0;
    }
    
    function checkCooCoCLpTokenGt10(address who) public view returns (bool) {
        return IAirDropERC20(cooCocLp).balanceOf(who) > 10 * 10**18;
    }
    
    function checkCooGt100(address who) public view returns (bool) {
        return IAirDropERC20(coo).balanceOf(who) > 100 * 10**18;
    }
    
    function checkCocGt100(address who) public view returns (bool) {
        return IAirDropERC20(coc).balanceOf(who) > 100 * 10**18;
    }
    
    function checkCobGt100(address who) public view returns (bool) {
        return IAirDropERC20(cob).balanceOf(who) > 100 * 10**18;
    }
    
    function checkCosGt1(address who) public view returns (bool) {
        return IAirDropERC20(cos).balanceOf(who) > 1 * 10**18;
    }
}
