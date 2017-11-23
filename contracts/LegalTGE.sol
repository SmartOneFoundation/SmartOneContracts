pragma solidity ^0.4.15;

import './LegalToken.sol';
import './parity/SMSVerification.sol';
import './zeppelin-solidity/contracts/ownership/Ownable.sol';
import './zeppelin-solidity/contracts/crowdsale/RefundVault.sol';
import './zeppelin-solidity/contracts/lifecycle/Pausable.sol';
import './zeppelin-solidity/contracts/math/SafeMath.sol';

/**
 * @title Legal TGE and Token contracts
 * @author Marco Oesch <marco.oesch@crea-soft.ch>
 */
contract LegalTGE is Ownable, Pausable {
  /**
  * The safe math library for safety math opertations provided by Zeppelin
  */
  using SafeMath for uint256;
  /** State machine
   * - PreparePreContribution: During this phase SmartOne adjust conversionRate and start/end date
   * - PreContribution: During this phase only registered users can contribute to the TGE and therefore receive a bonus until cap or end date is reached
   * - PrepareContribution: During this phase SmartOne adjusts conversionRate by the ETHUSD depreciation during PreContribution and change start and end date in case of an unforseen event 
   * - Contribution: During this all users can contribute until cap or end date is reached
   * - Auditing: SmartOne awaits recommendation by auditor and board of foundation will then finalize contribution or enable refunding
   * - Finalized: Token are released
   * - Refunding: Refunds can be claimed
   */
  enum States{PreparePreContribution, PreContribution, PrepareContribution, Contribution, Auditing, Finalized, Refunding}

  enum VerificationLevel { None, SMSVerified, KYCVerified }

 /**
  * Whenever the state of the contract changes, this event will be fired.
  */
  event LogStateChange(States _states);


  /**
  * This event is fired when a user has been successfully verified by the external KYC verification process
  */
  event LogKYCConfirmation(address sender);

  /**
  * Whenever a legalToken is assigned to this contract, this event will be fired.
  */
  event LogTokenAssigned(address sender, address newToken);

  /**
  * Every timed transition must be loged for auditing 
  */
  event LogTimedTransition(uint _now, States _newState);
  
  /**
  * This event is fired when PreContribution data is changed during the PreparePreContribution phase
  */
  event LogPreparePreContribution(address sender, uint conversionRate, uint startDate, uint endDate);

  /**
  * A user has transfered Ether and received unreleasead tokens in return
  */
  event LogContribution(address contributor, uint256 weiAmount, uint256 tokenAmount, VerificationLevel verificationLevel, States _state);

  /**
  * This event will be fired when SmartOne finalizes the TGE 
  */
  event LogFinalized(address sender);

  /**
  * This event will be fired when the auditor confirms the confirms regularity confirmity 
  */
  event LogRegularityConfirmation(address sender, bool _regularity, bytes32 _comment);
  
  /**
  * This event will be fired when refunding is enabled by the auditor 
  */
  event LogRefundsEnabled(address sender);

  /**
  * This event is fired when PreContribution data is changed during the PreparePreContribution phase
  */
  event LogPrepareContribution(address sender, uint conversionRate, uint startDate, uint endDate);

  /**
  * This refund vault used to hold funds while TGE is running.
  * Uses the default implementation provided by the OpenZeppelin community.
  */ 
  RefundVault public vault;

  /**
  * Defines the state of the conotribution process
  */
  States public state;

  /**
  * The token we are giving the contributors in return for their contributions
  */ 
  LegalToken public token;
  
  /**
  * The contract provided by Parity Tech (Gav Woods) to verify the mobile number during user registration
  */ 
  ProofOfSMS public proofOfSMS;

  /** 
  * The contribution (wei) will be forwarded to this address after the token has been finalized by the foundation board
  */
  address public multisigWallet;

  /** 
  * Maximum amount of wei this TGE can raise.
  */
  uint256 public tokenCap;

  /** 
  * The amount of wei a contributor has contributed. 
  * Used to check whether the total of contributions per user exceeds the max limit (depending on his verification level)
  */
  mapping (address => uint) public weiPerContributor;

  /** 
  * Minimum amount of tokens a contributor is able to buy
  */
  uint256 public minWeiPerContributor;

  /** 
  * Maximum amount of tokens an SMS verified user can contribute.
  */
  uint256 public maxWeiSMSVerified;

  /** 
  * Maximum amount of tokens an none-verified user can contribute.
  */
  uint256 public maxWeiUnverified;

  /* 
  * The number of token units a contributor receives per ETHER during pre-contribtion phase
  */ 
  uint public preSaleConversionRate;

  /* 
  * The UNIX timestamp (in seconds) defining when the pre-contribution phase will start
  */
  uint public preSaleStartDate;

  /* 
  * The UNIX timestamp (in seconds) defining when the TGE will end
  */
  uint public preSaleEndDate;

  /* 
  * The number of token units a contributor receives per ETHER during contribution phase
  */ 
  uint public saleConversionRate;

  /* 
  * The UNIX timestamp (in seconds) defining when the TGE will start
  */
  uint public saleStartDate;

  /* 
  * The UNIX timestamp (in seconds) defining when the TGE would end if cap will not be reached
  */
  uint public saleEndDate;

  /* 
  * The bonus a sms verified user will receive for a contribution during pre-contribution phase in base points
  */
  uint public smsVerifiedBonusBps;

  /* 
  * The bonus a kyc verified user will receive for a contribution during pre-contribution phase in base points
  */
  uint public kycVerifiedBonusBps;

  /**
  * Total percent of tokens minted to the team at the end of the sale as base points
  * 1BP -> 0.01%
  */
  uint public maxTeamBonusBps;

  /**
  * Only the foundation board is able to finalize the TGE.
  * Two of four members have to confirm the finalization. Therefore a multisig contract is used.
  */
  address public foundationBoard;

  /**
  * Only the KYC confirmation account is allowed to confirm a successfull KYC verification
  */
  address public kycConfirmer;

  /**
  * Once the contribution has ended an auditor will verify whether all regulations have been fullfilled
  */
  address public auditor;

  /**
  * The tokens for the insitutional investors will be allocated to this wallet
  */
  address public instContWallet;

  /**
  * This flag ist set by auditor before finalizing the TGE to indicate whether all regualtions have been fulfilled
  */
  bool public regulationsFulfilled;

  /**
  * The auditor can comment the confirmation (e.g. in case of deviations)
  */
  bytes32 public auditorComment;

  /**
  * The total number of institutional and public tokens sold during pre- and contribution phase
  */
  uint256 public tokensSold = 0;

  /*
  * The number of tokens pre allocated to insitutional contributors
  */
  uint public instContAllocatedTokens;

  /**
  * The amount of wei totally raised by the public TGE
  */
  uint256 public weiRaised = 0;

  /* 
  * The amount of wei raised during the preContribution phase 
  */
  uint256 public preSaleWeiRaised = 0;

  /*
  * How much wei we have given back to contributors.
  */
  uint256 public weiRefunded = 0;

  /*
  * The number of tokens allocated to the team when the TGE was finalized.
  * The calculation is based on the predefined maxTeamBonusBps
  */
  uint public teamBonusAllocatedTokens;

  /**
  * The number of contributors which have contributed to the TGE
  */
  uint public numberOfContributors = 0;

  /**
  * dictionary that maps addresses to contributors which have sucessfully been verified by the external KYC process 
  */
  mapping (address => bool) public kycRegisteredContributors;

  struct TeamBonus {
    address toAddress;
    uint64 tokenBps;
    uint64 cliffDate;
    uint64 vestingDate;
  }

  /*
  * Defines the percentage (base points) distribution of the team-allocated bonus rewards among members which will be vested ..
  * 1 Bp -> 0.01%
  */
  TeamBonus[] public teamBonuses;

  /**
   * @dev Check whether the TGE is currently in the state provided
   */

 function LegalTGE (address _foundationBoard, address _multisigWallet, address _instContWallet, uint256 _instContAllocatedTokens, uint256 _tokenCap, uint256 _smsVerifiedBonusBps, uint256 _kycVerifiedBonusBps, uint256 _maxTeamBonusBps, address _auditor, address _kycConfirmer, ProofOfSMS _proofOfSMS, RefundVault _vault) {
     // --------------------------------------------------------------------------------
    // -- Validate all variables which are not passed to the constructor first
    // --------------------------------------------------------------------------------
    // the address of the account used for auditing
    require(_foundationBoard != 0x0);
    
    // the address of the multisig must not be 'undefined'
    require(_multisigWallet != 0x0);

    // the address of the wallet for constitutional contributors must not be 'undefined'
    require(_instContWallet != 0x0);

    // the address of the account used for auditing
    require(_auditor != 0x0);
    
    // the address of the cap for this TGE must not be 'undefined'
    require(_tokenCap > 0); 

    // pre-contribution and contribution phases must not overlap
    // require(_preSaleStartDate <= _preSaleEndDate);

    multisigWallet = _multisigWallet;
    instContWallet = _instContWallet;
    instContAllocatedTokens = _instContAllocatedTokens;
    tokenCap = _tokenCap;
    smsVerifiedBonusBps = _smsVerifiedBonusBps;
    kycVerifiedBonusBps = _kycVerifiedBonusBps;
    maxTeamBonusBps = _maxTeamBonusBps;
    auditor = _auditor;
    foundationBoard = _foundationBoard;
    kycConfirmer = _kycConfirmer;
    proofOfSMS = _proofOfSMS;

    // --------------------------------------------------------------------------------
    // -- Initialize all variables which are not passed to the constructor first
    // --------------------------------------------------------------------------------
    state = States.PreparePreContribution;
    vault = _vault;
  }

  /** =============================================================================================================================
  * All logic related to the TGE contribution is currently placed below.
  * ============================================================================================================================= */

  function setMaxWeiForVerificationLevels(uint _minWeiPerContributor, uint _maxWeiUnverified, uint  _maxWeiSMSVerified) public onlyOwner inState(States.PreparePreContribution) {
    require(_minWeiPerContributor >= 0);
    require(_maxWeiUnverified > _minWeiPerContributor);
    require(_maxWeiSMSVerified > _minWeiPerContributor);

    // the minimum number of wei an unverified user can contribute
    minWeiPerContributor = _minWeiPerContributor;

    // the maximum number of wei an unverified user can contribute
    maxWeiUnverified = _maxWeiUnverified;

    // the maximum number of wei an SMS verified user can contribute    
    maxWeiSMSVerified = _maxWeiSMSVerified;
  }

  function setLegalToken(LegalToken _legalToken) public onlyOwner inState(States.PreparePreContribution) {
    token = _legalToken;
    if ( instContAllocatedTokens > 0 ) {
      // mint the pre allocated tokens for the institutional investors
      token.mint(instContWallet, instContAllocatedTokens);
      tokensSold += instContAllocatedTokens;
    }    
    LogTokenAssigned(msg.sender, _legalToken);
  }

  function validatePreContribution(uint _preSaleConversionRate, uint _preSaleStartDate, uint _preSaleEndDate) constant internal {
    // the pre-contribution conversion rate must not be 'undefined'
    require(_preSaleConversionRate >= 0);

    // the pre-contribution start date must not be in the past
    require(_preSaleStartDate >= now);

    // the pre-contribution start date must not be in the past
    require(_preSaleEndDate >= _preSaleStartDate);
  }

  function validateContribution(uint _saleConversionRate, uint _saleStartDate, uint _saleEndDate) constant internal {
    // the contribution conversion rate must not be 'undefined'
    require(_saleConversionRate >= 0);

    // the contribution start date must not be in the past
    require(_saleStartDate >= now);

    // the contribution end date must not be before start date 
    require(_saleEndDate >= _saleStartDate);
  }

  function isNowBefore(uint _date) constant internal returns (bool) {
    return ( now < _date );
  }

  function evalTransitionState() public returns (States) {
    // once the TGE is in state finalized or refunding, there is now way to transit to another state!
    if ( hasState(States.Finalized))
      return States.Finalized;
    if ( hasState(States.Refunding))
      return States.Refunding;
    if ( isCapReached()) 
      return States.Auditing;
    if ( isNowBefore(preSaleStartDate))
      return States.PreparePreContribution; 
    if ( isNowBefore(preSaleEndDate))
      return States.PreContribution;
    if ( isNowBefore(saleStartDate))  
      return States.PrepareContribution;
    if ( isNowBefore(saleEndDate))    
      return States.Contribution;
    return States.Auditing;
  }

  modifier stateTransitions() {
    States evaluatedState = evalTransitionState();
    setState(evaluatedState);
    _;
  }

  function hasState(States _state) constant private returns (bool) {
    return (state == _state);
  }

  function setState(States _state) private {
  	if ( _state != state ) {
      state = _state;
	  LogStateChange(state);
	  }
  }

  modifier inState(States  _state) {
    require(hasState(_state));
    _;
  }

  function updateState() public stateTransitions {
  }  
  
  /**
   * @dev Checks whether contract is in a state in which contributions will be accepted
   */
  modifier inPreOrContributionState() {
    require(hasState(States.PreContribution) || (hasState(States.Contribution)));
    _;
  }
  modifier inPrePrepareOrPreContributionState() {
    require(hasState(States.PreparePreContribution) || (hasState(States.PreContribution)));
    _;
  }

  modifier inPrepareState() {
    // we can relay on state since modifer since already evaluated by stateTransitions modifier
    require(hasState(States.PreparePreContribution) || (hasState(States.PrepareContribution)));
    _;
  }
  /** 
  * This modifier makes sure that not more tokens as specified can be allocated
  */
  modifier teamBonusLimit(uint64 _tokenBps) {
    uint teamBonusBps = 0; 
    for ( uint i = 0; i < teamBonuses.length; i++ ) {
      teamBonusBps = teamBonusBps.add(teamBonuses[i].tokenBps);
    }
    require(maxTeamBonusBps >= teamBonusBps);
    _;
  }

  /**
  * Allocates the team bonus with a specific vesting rule
  */
  function allocateTeamBonus(address _toAddress, uint64 _tokenBps, uint64 _cliffDate, uint64 _vestingDate) public onlyOwner teamBonusLimit(_tokenBps) inState(States.PreparePreContribution) {
    teamBonuses.push(TeamBonus(_toAddress, _tokenBps, _cliffDate, _vestingDate));
  }

  /**
  * This method can optional be called by the owner to adjust the conversionRate, startDate and endDate before contribution phase starts.
  * Pre-conditions:
  * - Caller is owner (deployer)
  * - TGE is in state PreContribution
  * Post-conditions:
  */
  function preparePreContribution(uint _preSaleConversionRate, uint _preSaleStartDate, uint _preSaleEndDate) public onlyOwner inState(States.PreparePreContribution) {
    validatePreContribution(_preSaleConversionRate, _preSaleStartDate, _preSaleEndDate);    
    preSaleConversionRate = _preSaleConversionRate;
    preSaleStartDate = _preSaleStartDate;
    preSaleEndDate = _preSaleEndDate;
    LogPreparePreContribution(msg.sender, preSaleConversionRate, preSaleStartDate, preSaleEndDate);
  }

  /**
  * This method can optional be called by the owner to adjust the conversionRate, startDate and endDate before pre contribution phase starts.
  * Pre-conditions:
  * - Caller is owner (deployer)
  * - Crowdsale is in state PreparePreContribution
  * Post-conditions:
  */
  function prepareContribution(uint _saleConversionRate, uint _saleStartDate, uint _saleEndDate) public onlyOwner inPrepareState {
    validateContribution(_saleConversionRate, _saleStartDate, _saleEndDate);
    saleConversionRate = _saleConversionRate;
    saleStartDate = _saleStartDate;
    saleEndDate = _saleEndDate;

    LogPrepareContribution(msg.sender, saleConversionRate, saleStartDate, saleEndDate);
  }

  // fallback function can be used to buy tokens
  function () payable public {
    contribute();  
  }
  function getWeiPerContributor(address _contributor) public constant returns (uint) {
  	return weiPerContributor[_contributor];
  }

  function contribute() whenNotPaused stateTransitions inPreOrContributionState public payable {
    require(msg.sender != 0x0);
    require(msg.value >= minWeiPerContributor);

    VerificationLevel verificationLevel = getVerificationLevel();
    
    // we only allow verified users to participate during pre-contribution phase
    require(hasState(States.Contribution) || verificationLevel > VerificationLevel.None);

    // we need to keep track of all contributions per user to limit total contributions
    weiPerContributor[msg.sender] = weiPerContributor[msg.sender].add(msg.value);

    // the total amount of ETH a KYC verified user can contribute is unlimited, so we do not need to check

    if ( verificationLevel == VerificationLevel.SMSVerified ) {
      // the total amount of ETH a non-KYC user can contribute is limited to maxWeiPerContributor
      require(weiPerContributor[msg.sender] <= maxWeiSMSVerified);
    }

    if ( verificationLevel == VerificationLevel.None ) {
      // the total amount of ETH a non-verified user can contribute is limited to maxWeiUnverified
      require(weiPerContributor[msg.sender] <= maxWeiUnverified);
    }

    if (hasState(States.PreContribution)) {
      preSaleWeiRaised = preSaleWeiRaised.add(msg.value);
    }

    weiRaised = weiRaised.add(msg.value);

    // calculate the token amount to be created
    uint256 tokenAmount = calculateTokenAmount(msg.value, verificationLevel);

    tokensSold = tokensSold.add(tokenAmount);

    if ( token.balanceOf(msg.sender) == 0 ) {
       numberOfContributors++;
    }

    if ( isCapReached()) {
      updateState();
    }

    token.mint(msg.sender, tokenAmount);

    forwardFunds();

    LogContribution(msg.sender, msg.value, tokenAmount, verificationLevel, state);    
  }

 
  function calculateTokenAmount(uint256 _weiAmount, VerificationLevel _verificationLevel) public constant returns (uint256) {
    uint256 conversionRate = saleConversionRate;
    if ( state == States.PreContribution) {
      conversionRate = preSaleConversionRate;
    }
    uint256 tokenAmount = _weiAmount.mul(conversionRate);
    
    // an anonymous user (Level-0) gets no bonus
    uint256 bonusTokenAmount = 0;

    if ( _verificationLevel == VerificationLevel.SMSVerified ) {
      // a SMS verified user (Level-1) gets a bonus
      bonusTokenAmount = tokenAmount.mul(smsVerifiedBonusBps).div(10000);
    } else if ( _verificationLevel == VerificationLevel.KYCVerified ) {
      // a KYC verified user (Level-2) gets the highest bonus
      bonusTokenAmount = tokenAmount.mul(kycVerifiedBonusBps).div(10000);
    }
    return tokenAmount.add(bonusTokenAmount);
  }

  function getVerificationLevel() constant public returns (VerificationLevel) {
    if (kycRegisteredContributors[msg.sender]) {
      return VerificationLevel.KYCVerified;
    } else if (proofOfSMS.certified(msg.sender)) {
      return VerificationLevel.SMSVerified;
    }
    return VerificationLevel.None;
  }

  modifier onlyKycConfirmer() {
    require(msg.sender == kycConfirmer);
    _;
  }

  function confirmKYC(address addressId) onlyKycConfirmer inPrePrepareOrPreContributionState() public returns (bool) {
    LogKYCConfirmation(msg.sender);
    return kycRegisteredContributors[addressId] = true;
  }

// =============================================================================================================================
// All functions related to the TGE cap come here
// =============================================================================================================================
  function isCapReached() constant internal returns (bool) {
    if (tokensSold >= tokenCap) {
      return true;
    }
    return false;
  }

// =============================================================================================================================
// Everything which is related tof the auditing process comes here.
// =============================================================================================================================
  /**
   * @dev Throws if called by any account other than the foundation board
   */
  modifier onlyFoundationBoard() {
    require(msg.sender == foundationBoard);
    _;
  }

  /**
   * @dev Throws if called by any account other than the auditor.
   */
  modifier onlyAuditor() {
    require(msg.sender == auditor);
    _;
  }
  
  /**
   * @dev Throws if auditor has not yet confirmed TGE
   */
  modifier auditorConfirmed() {
    require(auditorComment != 0x0);
    _;
  }

 /*
 * After the TGE reaches state 'auditing', the auditor will verify the legal and regulatory obligations 
 */
 function confirmLawfulness(bool _regulationsFulfilled, bytes32 _auditorComment) public onlyAuditor stateTransitions inState ( States.Auditing ) {
    regulationsFulfilled = _regulationsFulfilled;
    auditorComment = _auditorComment;
    LogRegularityConfirmation(msg.sender, _regulationsFulfilled, _auditorComment);
  }

  /**
   * After the auditor has verified the the legal and regulatory obligations of the TGE, the foundation board is able to finalize the TGE.
   * The finalization consists of the following steps:
   * - Transit state
   * - close the RefundVault and transfer funds to the foundation wallet
   * - release tokens (make transferable)
   * - enable scheduler for the inflation compensation
   * - Min the defined amount of token per team and make them vestable
   */
  function finalize() public onlyFoundationBoard stateTransitions inState ( States.Auditing ) auditorConfirmed {
    setState(States.Finalized);
    // Make token transferable otherwise the transfer call used when granting vesting to teams will be rejected.
    token.releaseTokenTransfer();
    
    // mint bonusus for 
    allocateTeamBonusTokens();

    // the funds can now be transfered to the multisig wallet of the foundation
    vault.close();

    // disable minting for the TGE (though tokens will still be minted to compensate an inflation period) 
    token.finishMinting();

    // now we can safely enable the shceduler for inflation compensation
    token.enableScheduler();

    // pass ownership from contract to SmartOne
    token.transferOwnership(owner);

    LogFinalized(msg.sender);
  }

  function enableRefunds() public onlyFoundationBoard stateTransitions inState ( States.Auditing ) auditorConfirmed {
    setState(States.Refunding);

    LogRefundsEnabled(msg.sender);

    // no need to trigger event here since this allready done in RefundVault (see event RefundsEnabled) 
    vault.enableRefunds(); 
  }
  

// =============================================================================================================================
// Postallocation Reward Tokens
// =============================================================================================================================
  
  /** 
  * Called once by TGE finalize() if the sale was success.
  */
  function allocateTeamBonusTokens() private {

    for (uint i = 0; i < teamBonuses.length; i++) {
      // How many % of tokens the team member receive as rewards
      uint _teamBonusTokens = (tokensSold.mul(teamBonuses[i].tokenBps)).div(10000);

      // mint new tokens for contributors
      token.mint(this, _teamBonusTokens);
      token.grantVestedTokens(teamBonuses[i].toAddress, _teamBonusTokens, uint64(now), teamBonuses[i].cliffDate, teamBonuses[i].vestingDate, false, false);
      teamBonusAllocatedTokens = teamBonusAllocatedTokens.add(_teamBonusTokens);
    }
  }

  // =============================================================================================================================
  // All functions related to Refunding can be found here. 
  // Uses some slightly modifed logic from https://github.com/OpenZeppelin/zeppelin-solidity/blob/master/contracts/crowdsale/RefundableTGE.sol
  // =============================================================================================================================

  /** We're overriding the fund forwarding from TGE.
  * In addition to sending the funds, we want to call
  * the RefundVault deposit function
  */
  function forwardFunds() internal {
    vault.deposit.value(msg.value)(msg.sender);
  }

  /**
  * If TGE was not successfull refunding process will be released by SmartOne
  */
  function claimRefund() public stateTransitions inState ( States.Refunding ) {
    // workaround since vault refund does not return refund value
    weiRefunded = weiRefunded.add(vault.deposited(msg.sender));
    vault.refund(msg.sender);
  }
}