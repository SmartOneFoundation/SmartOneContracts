pragma solidity ^0.4.15;

import './LegalTGE.sol';

/**
 * @title Legal TGE Contract 
 * @dev This is the 
 */
contract LegalTGEMock is LegalTGE {
  function setTokenCap(uint256 _tokenCap) public onlyOwner {
    tokenCap = _tokenCap;
  }
}