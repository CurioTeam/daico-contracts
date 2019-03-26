pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/crowdsale/distribution/FinalizableCrowdsale.sol";
import "openzeppelin-solidity/contracts/crowdsale/validation/WhitelistCrowdsale.sol";
import "./ICurioDaicoPool.sol";

contract CurioTokenSale is FinalizableCrowdsale, WhitelistCrowdsale, Ownable {
  address public fundAddr;
  address payable public poolAddr;

  /**
   * Event for change fund address logging
   * @param newFundAddr new address of fund-contract
   */
  event ChangeFund(address newFundAddr);

  constructor(
    IERC20 _token,
    address payable _poolAddr,
    uint256 _rate,
    uint256 _openingTime,
    uint256 _closingTime,
    address _fundAddr
  )
  public
  Crowdsale(_rate, _poolAddr, _token)
  TimedCrowdsale(_openingTime, _closingTime)
  {
    require(_poolAddr != address(0));
    require(_fundAddr != address(0));

    poolAddr = _poolAddr;
    fundAddr = _fundAddr;
  }

  /**
   * @dev Set new fund address.
   * @param _newFundAddr New address where collected unsold tokens
   *  will be forwarded to after tokensale finalization
   */
  function setFund(address _newFundAddr) onlyOwner external {
    require(_newFundAddr != address(0));
    fundAddr = _newFundAddr;

    emit ChangeFund(_newFundAddr);
  }

  /// @dev It transfers all the funds it has.
  function finalization() internal {
    if(address(this).balance > 0){
      // Transfer Ether to DaicoPool
      poolAddr.transfer(address(this).balance);
    }

    uint256 unsoldTokensAmount = token().balanceOf(address(this));

    if(unsoldTokensAmount > 0) {
      // Transfer unsold tokens to Fund
      token().transfer(fundAddr, unsoldTokensAmount);
    }

    // Open tap in DaicoPool
    ICurioDaicoPool(poolAddr).startProject();
  }

  /// @dev Overrides _forwardFunds to do nothing.
  function _forwardFunds() internal {}
}
