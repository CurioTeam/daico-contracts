pragma solidity ^0.5.3;

/**
 * @title CurioDaicoPool interface
 */
interface ICurioDaicoPool {
  function setTokenSaleContract(address _tokenSaleAddr) external;

  function startProject() external;

  function withdraw(uint256 _amount) external;

  function raiseTap(uint256 tapMultiplierRate) external;

  function selfDestruction() external;

  function refund(uint256 tokenAmount) external;

  function getReleasedBalance() external view returns(uint256);

  function getAvailableBalance() external view returns(uint256);

  function isStateInitializing() external view returns(bool);

  function isStateProjectInProgress() external view returns(bool);

  function isStateDestructed() external view returns(bool);

  event TapHistory(uint256 new_tap);
  event WithdrawalHistory(string token, uint256 amount);
  event Refund(address receiver, uint256 amount);
}
