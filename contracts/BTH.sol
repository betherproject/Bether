pragma solidity ^0.4.11;

import "./zeppelin/token/StandardToken.sol";
import "./zeppelin/ownership/Shareable.sol";

/**
 * @title BTH
 * @notice BTC + ETH = BTH
 */

contract BTH is StandardToken, Shareable {
  using SafeMath for uint256;

  /*
   * Constants
   */
  string public constant name = "Bether";
  string public constant symbol = "BTH";
  uint256 public constant decimals = 18;
  string public version = "1.0";

  uint256 public constant INITIAL_SUBSIDY = 50 * 10**decimals;
  uint256 public constant HASH_RATE_MULTIPLIER = 1;

  /*
   * Events
   */
  event LogContribution(address indexed _miner, uint256 _value, uint256 _hashRate, uint256 _block, uint256 _halving);
  event LogClaimHalvingSubsidy(address indexed _miner, uint256 _block, uint256 _halving, uint256 _value);
  event LogRemainingHalvingSubsidy(uint256 _halving, uint256 _value);
  event LogPause(bytes32 indexed _hash);
  event LogUnPause(bytes32 indexed _hash);
  event LogBTHFoundationWalletChanged(address indexed _wallet);
  event LogPollCreated(bytes32 indexed _hash);
  event LogPollDeleted(bytes32 indexed _hash);
  event LogPollVoted(bytes32 indexed _hash, address indexed _miner, uint256 _hashRate);
  event LogPollApproved(bytes32 indexed _hash);

  /*
   * Storage vars
   */
  mapping (uint256 => HalvingHashRate) halvingsHashRate; // Holds the accumulated hash rate per halving
  mapping (uint256 => Subsidy) halvingsSubsidies; // Stores the remaining subsidy per halving
  mapping (address => Miner) miners; // Miners data
  mapping (bytes32 => Poll) polls; // Contract polls

  address public bthFoundationWallet;
  uint256 public subsidyHalvingInterval;
  uint256 public maxHalvings;
  uint256 public genesis;
  uint256 public totalHashRate;
  bool public paused;

  struct HalvingHashRate {
    bool carried; // Indicates that the previous hash rate have been added to the halving
    uint256 rate; // Hash rate of the halving
  }

  struct Miner {
    uint256 block; // Miner block, used to calculate in which halving is the miner
    uint256 totalHashRate; // Accumulated miner hash rate
    mapping (uint256 => MinerHashRate) hashRate;
  }

  struct MinerHashRate {
    bool carried;
    uint256 rate;
  }

  struct Subsidy {
    bool claimed;  // Flag that indicates that the subsidy has been claimed at least one time, just to
                   // compute the initial halving subsidy value
    uint256 value; // Remaining subsidy of a halving
  }

  struct Poll {
    bool exists;  // Indicates that the poll is created
    string title; // Title of the poll, it's the poll indentifier so it must be unique
    mapping (address => bool) votes; // Control who have voted
    uint8 percentage; // Percentage which determines if the poll has been approved
    uint256 hashRate; // Summed hash rate of all the voters
    bool approved; // True if the poll has been approved
    uint256 approvalBlock; // Block in which the poll was approved
    uint256 approvalHashRate; // Hash rate that caused the poll approval
    uint256 approvalTotalHashRate; // Total has rate in when the poll was approved
  }

  /*
   * Modifiers
   */
  modifier notBeforeGenesis() {
    require(block.number >= genesis);
    _;
  }

  modifier nonZero(uint256 _value) {
    require(_value > 0);
    _;
  }

  modifier nonZeroAddress(address _address) {
    require(_address != address(0));
    _;
  }

  modifier nonZeroValued() {
    require(msg.value != 0);
    _;
  }

  modifier nonZeroLength(address[] array) {
    require(array.length != 0);
    _;
  }

  modifier notPaused() {
    require(!paused);
    _;
  }

  modifier notGreaterThanCurrentBlock(uint256 _block) {
    require(_block <= currentBlock());
    _;
  }

  modifier isMiner(address _address) {
    require(miners[_address].block != 0);
    _;
  }

  modifier pollApproved(bytes32 _hash) {
    require(polls[_hash].approved);
    _;
  }

  /*
   * Public functions
   */

  /**
    @notice Contract constructor
    @param _bthFoundationMembers are the addresses that control the BTH contract
    @param _required number of members needed to execute management functions of the contract
    @param _bthFoundationWallet wallet that holds all the contract contributions
    @param _genesis block number in which the BTH contract will be active
    @param _subsidyHalvingInterval number of blocks which comprises a halving
    @param _maxHalvings number of halvings that will generate BTH
  **/
  function BTH(
    address[] _bthFoundationMembers,
    uint256 _required,
    address _bthFoundationWallet,
    uint256 _genesis,
    uint256 _subsidyHalvingInterval,
    uint256 _maxHalvings
  ) Shareable( _bthFoundationMembers, _required)
    nonZeroLength(_bthFoundationMembers)
    nonZero(_required)
    nonZeroAddress(_bthFoundationWallet)
    nonZero(_genesis)
    nonZero(_subsidyHalvingInterval)
    nonZero(_maxHalvings)
  {
    // Genesis block must be greater or equal than the current block
    if (_genesis < block.number) throw;

    bthFoundationWallet = _bthFoundationWallet;
    subsidyHalvingInterval = _subsidyHalvingInterval;
    maxHalvings = _maxHalvings;

    genesis = _genesis;
    totalSupply = 0;
    totalHashRate = 0;
    paused = false;
  }

  /**
    @notice Contract desctruction function
    @param _hash poll hash that authorizes the function call
  **/
  function kill(bytes32 _hash)
    external
    pollApproved(_hash)
    onlymanyowners(sha3(msg.data))
  {
    selfdestruct(bthFoundationWallet);
  }

  /**
    @notice Contract desctruction function with ethers redirection
    @param _hash poll hash that authorizes the function call
  **/
  function killTo(address _to, bytes32 _hash)
    external
    nonZeroAddress(_to)
    pollApproved(_hash)
    onlymanyowners(sha3(msg.data))
  {
    selfdestruct(_to);
  }

  /**
    @notice Pause the contract operations
    @param _hash poll hash that authorizes the pause
  **/
  function pause(bytes32 _hash)
    external
    pollApproved(_hash)
    onlymanyowners(sha3(msg.data))
    notBeforeGenesis
  {
    if (!paused) {
      paused = true;
      LogPause(_hash);
    }
  }

  /**
    @notice Unpause the contract operations
    @param _hash poll hash that authorizes the unpause
  **/
  function unPause(bytes32 _hash)
    external
    pollApproved(_hash)
    onlymanyowners(sha3(msg.data))
    notBeforeGenesis
  {
    if (paused) {
      paused = false;
      LogUnPause(_hash);
    }
  }

  /**
    @notice Set the bthFoundation wallet
    @param _wallet new wallet address
  **/
  function setBTHFoundationWallet(address _wallet)
    external
    onlymanyowners(sha3(msg.data))
    nonZeroAddress(_wallet)
  {
    bthFoundationWallet = _wallet;
    LogBTHFoundationWalletChanged(_wallet);
  }

  /**
    @notice Returns the current BTH block
    @return current bth block number
  **/
  function currentBlock()
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    return block.number.sub(genesis);
  }

   /**
    @notice Calculates the halving number of a given block
    @param _block block number
    @return the halving of the block
  **/
  function blockHalving(uint256 _block)
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    return _block.div(subsidyHalvingInterval);
  }

  /**
    @notice Calculate the offset of a given block
    @return the offset of the block in a halving
  **/
  function blockOffset(uint256 _block)
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    return _block % subsidyHalvingInterval;
  }

  /**
    @notice Determine the current halving number
    @return the current halving
  **/
  function currentHalving()
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    return blockHalving(currentBlock());
  }

  /**
    @notice Compute the starting block of a halving
    @return the initial halving block
  **/
  function halvingStartBlock(uint256 _halving)
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    return _halving.mul(subsidyHalvingInterval);
  }

  /**
    @notice Calculate the total subsidy of a block
    @param _block block number
    @return the total amount that will be shared with the miners
  **/
  function blockSubsidy(uint256 _block)
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    uint256 halvings = _block.div(subsidyHalvingInterval);

    if (halvings >= maxHalvings) return 0;

    uint256 subsidy = INITIAL_SUBSIDY >> halvings;

    return subsidy;
  }

  /**
    @notice Computes the subsidy of a full halving
    @param _halving halving
    @return the total amount that will be shared with the miners in this halving
  **/
  function halvingSubsidy(uint256 _halving)
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    uint256 startBlock = halvingStartBlock(_halving);

    return blockSubsidy(startBlock).mul(subsidyHalvingInterval);
  }

  /// @notice Fallback function which implements how miners participate in BTH
  function()
    payable
  {
    contribute(msg.sender);
  }

  /**
    @notice Contribute to the mining of BTH on behalf of another miner
    @param _miner address that will receive the subsidies
    @return true if success
  **/
  function proxiedContribution(address _miner)
    public
    payable
    returns (bool)
  {
    if (_miner == address(0)) {
      // In case the _miner parameter is invalid, redirect the asignment
      // to the transaction sender
      return contribute(msg.sender);
    } else {
      return contribute(_miner);
    }
  }

  /**
    @notice Contribute to the mining of BTH
    @param _miner address that will receive the subsidies
    @return true if success
  **/
  function contribute(address _miner)
    internal
    notBeforeGenesis
    nonZeroValued
    notPaused
    returns (bool)
  {
    uint256 block = currentBlock();
    uint256 halving = currentHalving();
    uint256 hashRate = HASH_RATE_MULTIPLIER.mul(msg.value);
    Miner miner = miners[_miner];

    // First of all use the contribute to synchronize the hash rate of the previous halvings
    if (halving != 0 && halving < maxHalvings) {
      uint256 I;
      uint256 n = 0;
      for (I = halving - 1; I > 0; I--) {
        if (!halvingsHashRate[I].carried) {
          n = n.add(1);
        } else {
          break;
        }
      }

      for (I = halving - n; I < halving; I++) {
        if (!halvingsHashRate[I].carried) {
          halvingsHashRate[I].carried = true;
          halvingsHashRate[I].rate = halvingsHashRate[I].rate.add(halvingsHashRate[I - 1].rate);
        }
      }
    }

    // Increase the halving hash rate accordingly, after maxHalvings the halvings hash rate are not needed and therefore not updated
    if (halving < maxHalvings) {
      halvingsHashRate[halving].rate = halvingsHashRate[halving].rate.add(hashRate);
    }

    // After updating the halving hash rate, do the miner contribution

    // If it's the very first time the miner participates in the BTH token, assign an initial block
    // This block is used with two porpouses:
    //    - To account in which halving the miner is
    //    - To know the offset inside the halving and allow only claimings after the miner offset
    if (miner.block == 0) {
      miner.block = block;
    }

    // Add this hash rate to the miner at the current halving
    miner.hashRate[halving].rate = miner.hashRate[halving].rate.add(hashRate);
    miner.totalHashRate = miner.totalHashRate.add(hashRate);

    // Increase the total hash rate
    totalHashRate = totalHashRate.add(hashRate);

    // Send contribution to the BTH foundation multisig wallet
    if (!bthFoundationWallet.send(msg.value)) {
      throw;
    }

    // Log the contribute call
    LogContribution(_miner, msg.value, hashRate, block, halving);

    return true;
  }

  /**
    @notice Miners subsidies must be claimed by the miners calling claimHalvingsSubsidies(_n)
    @param _n number of halvings to claim
    @return the total amount claimed and successfully assigned as BTH to the miner
  **/
  function claimHalvingsSubsidies(uint256 _n)
    public
    notBeforeGenesis
    notPaused
    isMiner(msg.sender)
    returns(uint256)
  {
    Miner miner = miners[msg.sender];
    uint256 start = blockHalving(miner.block);
    uint256 end = start.add(_n);

    if (end > currentHalving()) {
      return 0;
    }

    uint256 subsidy = 0;
    uint256 totalSubsidy = 0;
    uint256 unclaimed = 0;
    uint256 hashRate = 0;
    uint256 K;

    // Claim each unclaimed halving subsidy
    for(K = start; K < end && K < maxHalvings; K++) {
      // Check if the total hash rate has been carried, otherwise the current halving
      // hash rate needs to be updated carrying the total from the last carried
      HalvingHashRate halvingHashRate = halvingsHashRate[K];

      if (!halvingHashRate.carried) {
        halvingHashRate.carried = true;
        halvingHashRate.rate = halvingHashRate.rate.add(halvingsHashRate[K-1].rate);
      }

      // Accumulate the miner hash rate as all the contributions are accounted in the contribution
      // and needs to be summed up to reflect the accumulated value
      MinerHashRate minerHashRate = miner.hashRate[K];
      if (!minerHashRate.carried) {
        minerHashRate.carried = true;
        minerHashRate.rate = minerHashRate.rate.add(miner.hashRate[K-1].rate);
      }

      hashRate = minerHashRate.rate;

      if (hashRate != 0){
        // If the halving to claim is the last claimable, check the offsets
        if (K == currentHalving().sub(1)) {
          if (currentBlock() % subsidyHalvingInterval < miner.block % subsidyHalvingInterval) {
            // Finish the loop
            continue;
          }
        }

        Subsidy sub = halvingsSubsidies[K];

        if (!sub.claimed) {
          sub.claimed = true;
          sub.value = halvingSubsidy(K);
        }

        unclaimed = sub.value;
        subsidy = halvingSubsidy(K).mul(hashRate).div(halvingHashRate.rate);

        if (subsidy > unclaimed) {
          subsidy = unclaimed;
        }

        totalSubsidy = totalSubsidy.add(subsidy);
        sub.value = sub.value.sub(subsidy);

        LogClaimHalvingSubsidy(msg.sender, miner.block, K, subsidy);
        LogRemainingHalvingSubsidy(K, sub.value);
      }

      // Move the miner to the next halving
      miner.block = miner.block.add(subsidyHalvingInterval);
    }

    // If K is less than end, the loop exited because K < maxHalvings, so
    // move the miner end - K halvings
    if (K < end) {
      miner.block = miner.block.add(subsidyHalvingInterval.mul(end.sub(K)));
    }

    if (totalSubsidy != 0){
      balances[msg.sender] = balances[msg.sender].add(totalSubsidy);
      totalSupply = totalSupply.add(totalSubsidy);
    }

    return totalSubsidy;
  }

  /**
    @notice Compute the number of halvings claimable by the miner caller
    @return number of halvings that a miner is allowed to claim
  **/
  function claimableHalvings()
    public
    constant
    returns(uint256)
  {
    return claimableHalvingsOf(msg.sender);
  }


  /**
    @notice Computes the number of halvings claimable by the miner
    @return number of halvings that a miner is entitled claim
  **/
  function claimableHalvingsOf(address _miner)
    public
    constant
    notBeforeGenesis
    isMiner(_miner)
    returns(uint256)
  {
    Miner miner = miners[_miner];
    uint256 halving = currentHalving();
    uint256 minerHalving = blockHalving(miner.block);

    // Halvings can be claimed when they are finished
    if (minerHalving == halving) {
      return 0;
    } else {
      // Check the miner offset
      if (currentBlock() % subsidyHalvingInterval < miner.block % subsidyHalvingInterval) {
        // In this case the miner offset is behind the current block offset, so it must wait
        // till the block offset is greater or equal than his offset
        return halving.sub(minerHalving).sub(1);
      } else {
        return halving.sub(minerHalving);
      }
    }
  }

  /**
    @notice Claim all the unclaimed halving subsidies of a miner
    @return total amount of BTH assigned to the miner
  **/
  function claim()
    public
    notBeforeGenesis
    notPaused
    isMiner(msg.sender)
    returns(uint256)
  {
    return claimHalvingsSubsidies(claimableHalvings());
  }

  /**
    @notice ERC20 transfer function overridden to disable transfers when paused
  **/
  function transfer(address _to, uint _value)
    public
    notPaused
  {
    super.transfer(_to, _value);
  }

  /**
    @notice ERC20 transferFrom function overridden to disable transfers when paused
  **/
  function transferFrom(address _from, address _to, uint _value)
    public
    notPaused
  {
    super.transferFrom(_from, _to, _value);
  }

  // Poll functions

  /**
    @notice Create a new poll
    @param _title poll title
    @param _percentage percentage of hash rate that must vote to approve the poll
  **/
  function createPoll(string _title, uint8 _percentage)
    external
    onlymanyowners(sha3(msg.data))
  {
    bytes32 hash = sha3(_title);
    Poll poll = polls[hash];

    if (poll.exists) {
      throw;
    }

    if (_percentage < 1 || _percentage > 100) {
      throw;
    }

    poll.exists = true;
    poll.title = _title;
    poll.percentage = _percentage;
    poll.hashRate = 0;
    poll.approved = false;
    poll.approvalBlock = 0;
    poll.approvalHashRate = 0;
    poll.approvalTotalHashRate = 0;

    LogPollCreated(hash);
  }

  /**
    @notice Delete a poll
    @param _hash sha3 of the poll title, also arg of LogPollCreated event
  **/
  function deletePoll(bytes32 _hash)
    external
    onlymanyowners(sha3(msg.data))
  {
    Poll poll = polls[_hash];

    if (poll.exists) {
      delete polls[_hash];

      LogPollDeleted(_hash);
    }
  }

  /**
    @notice Retreive the poll data
    @param _hash sha3 of the poll title, also arg of LogPollCreated event
    @return an array with the poll data
  **/
  function getPoll(bytes32 _hash)
    external
    constant
    returns(bool, string, uint8, uint256, uint256, bool, uint256, uint256, uint256)
  {
    Poll poll = polls[_hash];

    return (poll.exists, poll.title, poll.percentage, poll.hashRate, totalHashRate,
      poll.approved, poll.approvalBlock, poll.approvalHashRate, poll.approvalTotalHashRate);
  }

  function vote(bytes32 _hash)
    external
    isMiner(msg.sender)
  {
    Poll poll = polls[_hash];

    if (poll.exists) {
      if (!poll.votes[msg.sender]) {
        // msg.sender has not yet voted
        Miner miner = miners[msg.sender];

        poll.votes[msg.sender] = true;
        poll.hashRate = poll.hashRate.add(miner.totalHashRate);

        // Log the vote
        LogPollVoted(_hash, msg.sender, miner.totalHashRate);

        // Check if the poll has succeeded
        if (!poll.approved) {
          if (poll.hashRate.mul(100).div(totalHashRate) >= poll.percentage) {
            poll.approved = true;

            poll.approvalBlock = block.number;
            poll.approvalHashRate = poll.hashRate;
            poll.approvalTotalHashRate = totalHashRate;

            LogPollApproved(_hash);
          }
        }
      }
    }
  }

  /*
   * Internal functions
   */


  /*
   * Web3 call functions
   */

  /**
    @notice Return the blocks per halving
    @return blocks per halving
  **/
  function getHalvingBlocks()
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    return subsidyHalvingInterval;
  }

  /**
    @notice Return the block in which the miner is
    @return the last block number mined by the miner
  **/
  function getMinerBlock()
    public
    constant
    returns(uint256)
  {
    return getBlockOf(msg.sender);
  }

  /**
    @notice Return the block in which the miner is
    @return the last block number mined by the miner
  **/
  function getBlockOf(address _miner)
    public
    constant
    notBeforeGenesis
    isMiner(_miner)
    returns(uint256)
  {
    return miners[_miner].block;
  }

  /**
    @notice Return the miner halving (starting halving or last claimed)
    @return last claimed or starting halving of the miner
  **/
  function getHalvingOf(address _miner)
    public
    constant
    notBeforeGenesis
    isMiner(_miner)
    returns(uint256)
  {
    return blockHalving(miners[_miner].block);
  }

  /**
    @notice Return the miner halving (starting halving or last claimed)
    @return last claimed or starting halving of the miner
  **/
  function getMinerHalving()
    public
    constant
    returns(uint256)
  {
    return getHalvingOf(msg.sender);
  }

  /**
    @notice Total hash rate of a miner in a halving
    @param _miner address of the miner
    @return miner total accumulated hash rate
  **/
  function getMinerHalvingHashRateOf(address _miner)
    public
    constant
    notBeforeGenesis
    isMiner(_miner)
    returns(uint256)
  {
    Miner miner = miners[_miner];
    uint256 halving = getMinerHalving();
    MinerHashRate hashRate = miner.hashRate[halving];

    if (halving == 0) {
      return  hashRate.rate;
    } else {
      if (!hashRate.carried) {
        return hashRate.rate.add(miner.hashRate[halving - 1].rate);
      } else {
        return hashRate.rate;
      }
    }
  }

  /**
    @notice Total hash rate of a miner in a halving
    @return miner total accumulated hash rate
  **/
  function getMinerHalvingHashRate()
    public
    constant
    returns(uint256)
  {
    return getMinerHalvingHashRateOf(msg.sender);
  }

  /**
    @notice Compute the miner halvings offset
    @param _miner address of the miner
    @return miner halving offset
  **/
  function getMinerOffsetOf(address _miner)
    public
    constant
    notBeforeGenesis
    isMiner(_miner)
    returns(uint256)
  {
    return blockOffset(miners[_miner].block);
  }

  /**
    @notice Compute the miner halvings offset
    @return miner halving offset
  **/
  function getMinerOffset()
    public
    constant
    returns(uint256)
  {
    return getMinerOffsetOf(msg.sender);
  }

  /**
    @notice Calculate the hash rate of a miner in a halving
    @dev Take into account that the rate can be uncarried
    @param _halving number of halving
    @return (carried, rate) a tuple with the rate and if the value has been carried from previous halvings
  **/
  function getHashRateOf(address _miner, uint256 _halving)
    public
    constant
    notBeforeGenesis
    isMiner(_miner)
    returns(bool, uint256)
  {
    require(_halving <= currentHalving());

    Miner miner = miners[_miner];
    MinerHashRate hashRate = miner.hashRate[_halving];

    return (hashRate.carried, hashRate.rate);
  }

  /**
    @notice Calculate the halving hash rate of a miner
    @dev Take into account that the rate can be uncarried
    @param _miner address of the miner
    @return (carried, rate) a tuple with the rate and if the value has been carried from previous halvings
  **/
  function getHashRateOfCurrentHalving(address _miner)
    public
    constant
    returns(bool, uint256)
  {
    return getHashRateOf(_miner, currentHalving());
  }

  /**
    @notice Calculate the halving hash rate of a miner
    @dev Take into account that the rate can be uncarried
    @param _halving numer of the miner halving
    @return (carried, rate) a tuple with the rate and if the value has been carried from previous halvings
  **/
  function getMinerHashRate(uint256 _halving)
    public
    constant
    returns(bool, uint256)
  {
    return getHashRateOf(msg.sender, _halving);
  }

  /**
    @notice Calculate the halving hash rate of a miner
    @dev Take into account that the rate can be uncarried
    @return (carried, rate) a tuple with the rate and if the value has been carried from previous halvings
  **/
  function getMinerHashRateCurrentHalving()
    public
    constant
    returns(bool, uint256)
  {
    return getHashRateOf(msg.sender, currentHalving());
  }

  /**
    @notice Total hash rate of a miner
    @return miner total accumulated hash rate
  **/
  function getTotalHashRateOf(address _miner)
    public
    constant
    notBeforeGenesis
    isMiner(_miner)
    returns(uint256)
  {
    return miners[_miner].totalHashRate;
  }

  /**
    @notice Total hash rate of a miner
    @return miner total accumulated hash rate
  **/
  function getTotalHashRate()
    public
    constant
    returns(uint256)
  {
    return getTotalHashRateOf(msg.sender);
  }

  /**
    @notice Computes the remaining subsidy pending of being claimed for a given halving
    @param _halving number of halving
    @return the remaining subsidy of a halving
  **/
  function getUnclaimedHalvingSubsidy(uint256 _halving)
    public
    constant
    notBeforeGenesis
    returns(uint256)
  {
    require(_halving < currentHalving());

    if (!halvingsSubsidies[_halving].claimed) {
      // In the case that the halving subsidy hasn't been instantiated
      // (.claimed is false) return the full halving subsidy
      return halvingSubsidy(_halving);
    } else {
      // Otherwise return the remaining halving subsidy
      halvingsSubsidies[_halving].value;
    }
  }
}