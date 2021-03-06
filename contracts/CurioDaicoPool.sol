pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./ICurioDaicoPool.sol";
import "./CurioDaicoVoting.sol";


contract CurioDaicoPool is ICurioDaicoPool, Ownable {
    using SafeMath for uint256;

    address public tokenSaleAddr;
    address public votingAddr;
    address public votingTokenAddr;
    uint256 public tap;
    uint256 public initialTap;
    uint256 public initialRelease;
    uint256 public releasedBalance;
    uint256 public withdrawnBalance;
    uint256 public lastUpdatedTime;
    uint256 public fundRaised;
    uint256 public closingRelease = 30 days;

    /* The unit of this variable is [10^-9 wei / token], intending to minimize rouding errors */
    uint256 public refundRateNano = 0;

    enum Status {
        Initializing,
        ProjectInProgress,
        Destructed
    }

    Status public status;

    event TapHistory(uint256 new_tap);
    event WithdrawalHistory(string token, uint256 amount);
    event Refund(address receiver, uint256 amount);

    modifier onlyTokenSaleContract {
        require(msg.sender == tokenSaleAddr);
        _;
    }

    modifier onlyVoting {
        require(msg.sender == votingAddr);
        _;
    }

    modifier poolInitializing {
        require(status == Status.Initializing);
        _;
    }

    modifier poolDestructed {
        require(status == Status.Destructed);
        _;
    }

    constructor(address _votingTokenAddr, uint256 tap_amount, uint256 _initialRelease) public {
        require(_votingTokenAddr != address(0));
        require(tap_amount > 0);

        initialTap = tap_amount;
        votingTokenAddr = _votingTokenAddr;
        status = Status.Initializing;
        initialRelease = _initialRelease;

        votingAddr = address(new CurioDaicoVoting(_votingTokenAddr, address(this)));
    }

    function () external payable {}

    function setTokenSaleContract(address _tokenSaleAddr) external {
        /* Can be set only once */
        require(tokenSaleAddr == address(0));
        require(_tokenSaleAddr != address(0));
        tokenSaleAddr = _tokenSaleAddr;
    }

    function startProject() external onlyTokenSaleContract {
        require(status == Status.Initializing);
        status = Status.ProjectInProgress;
        lastUpdatedTime = block.timestamp;
        releasedBalance = initialRelease;
        updateTap(initialTap);
        fundRaised = address(this).balance;
    }

    function withdraw(uint256 _amount) public onlyOwner {
        require(_amount > 0);
        uint256 amount = _amount;

        updateReleasedBalance();
        uint256 available_balance = getAvailableBalance();
        if (amount > available_balance) {
            amount = available_balance;
        }

        withdrawnBalance = withdrawnBalance.add(amount);
        msg.sender.transfer(amount);

        emit WithdrawalHistory("ETH", amount);
    }

    function raiseTap(uint256 tapMultiplierRate) external onlyVoting {
        updateReleasedBalance();
        updateTap(tap.mul(tapMultiplierRate).div(100));
    }

    function selfDestruction() external onlyVoting {
        status = Status.Destructed;
        updateReleasedBalance();
        releasedBalance = releasedBalance.add(closingRelease.mul(tap));
        updateTap(0);

        uint256 _totalSupply = IERC20(votingTokenAddr).totalSupply();
        refundRateNano = address(this).balance.sub(getAvailableBalance()).mul(10**9).div(_totalSupply);
    }

    function refund(uint256 tokenAmount) external poolDestructed {
        require(IERC20(votingTokenAddr).transferFrom(msg.sender, address(this), tokenAmount));

        uint256 refundingEther = tokenAmount.mul(refundRateNano).div(10**9);
        emit Refund(msg.sender, tokenAmount);
        msg.sender.transfer(refundingEther);
    }

    function getReleasedBalance() public view returns(uint256) {
        uint256 time_elapsed = block.timestamp.sub(lastUpdatedTime);
        return releasedBalance.add(time_elapsed.mul(tap));
    }

    function getAvailableBalance() public view returns(uint256) {
        uint256 available_balance = getReleasedBalance().sub(withdrawnBalance);

        if (available_balance > address(this).balance) {
            available_balance = address(this).balance;
        }

        return available_balance;
    }

    function isStateInitializing() public view returns(bool) {
        return (status == Status.Initializing);
    }

    function isStateProjectInProgress() public view returns(bool) {
        return (status == Status.ProjectInProgress);
    }

    function isStateDestructed() public view returns(bool) {
        return (status == Status.Destructed);
    }

    function updateReleasedBalance() internal {
        releasedBalance = getReleasedBalance();
        lastUpdatedTime = block.timestamp;
    }

    function updateTap(uint256 new_tap) private {
        tap = new_tap;
        emit TapHistory(new_tap);
    }
}
