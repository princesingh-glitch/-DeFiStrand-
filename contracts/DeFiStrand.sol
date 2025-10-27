
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title DeFiStrand
 * @dev A decentralized finance platform that weaves together multiple DeFi primitives
 * into interconnected strands for optimized yield generation and liquidity management
 */
contract Project is Ownable, ReentrancyGuard, Pausable {
    
    // Struct to represent a DeFi Strand
    struct Strand {
        string name;
        address creator;
        uint256 totalDeposited;
        uint256 totalYieldGenerated;
        uint256 createdAt;
        uint256 lastUpdateTime;
        bool isActive;
        uint8 riskLevel; // 1-10, where 10 is highest risk
    }
    
    // Struct to represent a user's position in a strand
    struct Position {
        uint256 depositAmount;
        uint256 depositTime;
        uint256 lastClaimTime;
        uint256 accruedYield;
        bool isActive;
    }
    
    // Struct for liquidity pool
    struct LiquidityPool {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalLiquidity;
        uint256 feePercentage; // In basis points (e.g., 30 = 0.3%)
    }
    
    // State variables
    mapping(uint256 => Strand) public strands;
    mapping(uint256 => mapping(address => Position)) public userPositions;
    mapping(uint256 => LiquidityPool) public liquidityPools;
    mapping(address => uint256[]) public userStrandIds;
    
    uint256 public strandCounter;
    uint256 public poolCounter;
    uint256 public constant MIN_DEPOSIT = 0.01 ether;
    uint256 public constant YIELD_RATE = 500; // 5% annual yield in basis points
    uint256 public totalValueLocked;
    
    // Events
    event StrandCreated(uint256 indexed strandId, string name, address indexed creator, uint8 riskLevel);
    event DepositMade(uint256 indexed strandId, address indexed user, uint256 amount);
    event YieldClaimed(uint256 indexed strandId, address indexed user, uint256 amount);
    event LiquidityAdded(uint256 indexed poolId, address indexed provider, uint256 amountA, uint256 amountB);
    event StrandDeactivated(uint256 indexed strandId);
    event EmergencyWithdrawal(address indexed user, uint256 amount);
    
    constructor() Ownable(msg.sender) {
        strandCounter = 0;
        poolCounter = 0;
        totalValueLocked = 0;
    }
    
    /**
     * @dev Creates a new DeFi Strand with specified parameters
     * @param _name Name of the strand
     * @param _riskLevel Risk level from 1-10
     * @return strandId The ID of the newly created strand
     */
    function createStrand(
        string memory _name,
        uint8 _riskLevel
    ) external whenNotPaused returns (uint256) {
        require(bytes(_name).length > 0 && bytes(_name).length <= 50, "Invalid strand name");
        require(_riskLevel >= 1 && _riskLevel <= 10, "Risk level must be between 1 and 10");
        
        strandCounter++;
        uint256 newStrandId = strandCounter;
        
        strands[newStrandId] = Strand({
            name: _name,
            creator: msg.sender,
            totalDeposited: 0,
            totalYieldGenerated: 0,
            createdAt: block.timestamp,
            lastUpdateTime: block.timestamp,
            isActive: true,
            riskLevel: _riskLevel
        });
        
        userStrandIds[msg.sender].push(newStrandId);
        
        emit StrandCreated(newStrandId, _name, msg.sender, _riskLevel);
        return newStrandId;
    }
    
    /**
     * @dev Deposits funds into a specific strand
     * @param _strandId ID of the strand to deposit into
     */
    function depositToStrand(uint256 _strandId) external payable nonReentrant whenNotPaused {
        require(_strandId > 0 && _strandId <= strandCounter, "Invalid strand ID");
        require(strands[_strandId].isActive, "Strand is not active");
        require(msg.value >= MIN_DEPOSIT, "Deposit amount too low");
        
        Strand storage strand = strands[_strandId];
        Position storage position = userPositions[_strandId][msg.sender];
        
        // If user has existing position, claim accrued yield first
        if (position.isActive && position.depositAmount > 0) {
            _calculateAndUpdateYield(_strandId, msg.sender);
        } else {
            // Initialize new position
            position.isActive = true;
            position.depositTime = block.timestamp;
            position.lastClaimTime = block.timestamp;
            userStrandIds[msg.sender].push(_strandId);
        }
        
        // Update position and strand
        position.depositAmount += msg.value;
        strand.totalDeposited += msg.value;
        strand.lastUpdateTime = block.timestamp;
        totalValueLocked += msg.value;
        
        emit DepositMade(_strandId, msg.sender, msg.value);
    }
    
    /**
     * @dev Claims accrued yield from a strand
     * @param _strandId ID of the strand to claim from
     * @return yieldAmount The amount of yield claimed
     */
    function claimYield(uint256 _strandId) external nonReentrant whenNotPaused returns (uint256) {
        require(_strandId > 0 && _strandId <= strandCounter, "Invalid strand ID");
        require(userPositions[_strandId][msg.sender].isActive, "No active position");
        
        _calculateAndUpdateYield(_strandId, msg.sender);
        
        Position storage position = userPositions[_strandId][msg.sender];
        uint256 yieldAmount = position.accruedYield;
        
        require(yieldAmount > 0, "No yield to claim");
        require(address(this).balance >= yieldAmount, "Insufficient contract balance");
        
        // Update position
        position.accruedYield = 0;
        position.lastClaimTime = block.timestamp;
        
        // Update strand
        strands[_strandId].totalYieldGenerated += yieldAmount;
        
        // Transfer yield
        (bool success, ) = payable(msg.sender).call{value: yieldAmount}("");
        require(success, "Yield transfer failed");
        
        emit YieldClaimed(_strandId, msg.sender, yieldAmount);
        return yieldAmount;
    }
    
    /**
     * @dev Internal function to calculate and update yield
     */
    function _calculateAndUpdateYield(uint256 _strandId, address _user) internal {
        Position storage position = userPositions[_strandId][_user];
        
        uint256 timeElapsed = block.timestamp - position.lastClaimTime;
        if (timeElapsed > 0 && position.depositAmount > 0) {
            // Calculate yield based on time elapsed and yield rate
            // Formula: (depositAmount * yieldRate * timeElapsed) / (365 days * 10000)
            uint256 yield = (position.depositAmount * YIELD_RATE * timeElapsed) / (365 days * 10000);
            
            // Apply risk multiplier
            uint8 riskLevel = strands[_strandId].riskLevel;
            yield = (yield * (100 + riskLevel * 10)) / 100;
            
            position.accruedYield += yield;
        }
    }
    
    /**
     * @dev Adds liquidity to create or enhance a liquidity pool
     * @param _tokenA Address of first token
     * @param _tokenB Address of second token
     * @param _amountA Amount of first token
     * @param _amountB Amount of second token
     * @return poolId The ID of the liquidity pool
     */
    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(_tokenA != address(0) && _tokenB != address(0), "Invalid token addresses");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_amountA > 0 && _amountB > 0, "Amounts must be greater than 0");
        
        poolCounter++;
        uint256 poolId = poolCounter;
        
        liquidityPools[poolId] = LiquidityPool({
            tokenA: _tokenA,
            tokenB: _tokenB,
            reserveA: _amountA,
            reserveB: _amountB,
            totalLiquidity: _amountA + _amountB,
            feePercentage: 30 // 0.3% fee
        });
        
        emit LiquidityAdded(poolId, msg.sender, _amountA, _amountB);
        return poolId;
    }
    
    /**
     * @dev Retrieves detailed information about a strand
     */
    function getStrandInfo(uint256 _strandId) external view returns (
        string memory name,
        address creator,
        uint256 totalDeposited,
        uint256 totalYieldGenerated,
        uint256 createdAt,
        bool isActive,
        uint8 riskLevel
    ) {
        require(_strandId > 0 && _strandId <= strandCounter, "Invalid strand ID");
        Strand memory strand = strands[_strandId];
        return (
            strand.name,
            strand.creator,
            strand.totalDeposited,
            strand.totalYieldGenerated,
            strand.createdAt,
            strand.isActive,
            strand.riskLevel
        );
    }
    
    /**
     * @dev Retrieves user's position in a specific strand
     */
    function getUserPosition(uint256 _strandId, address _user) external view returns (
        uint256 depositAmount,
        uint256 depositTime,
        uint256 lastClaimTime,
        uint256 accruedYield,
        bool isActive
    ) {
        Position memory position = userPositions[_strandId][_user];
        
        // Calculate current accrued yield without updating state
        uint256 currentYield = position.accruedYield;
        if (position.isActive && position.depositAmount > 0) {
            uint256 timeElapsed = block.timestamp - position.lastClaimTime;
            if (timeElapsed > 0) {
                uint256 additionalYield = (position.depositAmount * YIELD_RATE * timeElapsed) / (365 days * 10000);
                uint8 riskLevel = strands[_strandId].riskLevel;
                additionalYield = (additionalYield * (100 + riskLevel * 10)) / 100;
                currentYield += additionalYield;
            }
        }
        
        return (
            position.depositAmount,
            position.depositTime,
            position.lastClaimTime,
            currentYield,
            position.isActive
        );
    }
    
    /**
     * @dev Get all strand IDs associated with a user
     */
    function getUserStrands(address _user) external view returns (uint256[] memory) {
        return userStrandIds[_user];
    }
    
    /**
     * @dev Get liquidity pool information
     */
    function getLiquidityPool(uint256 _poolId) external view returns (
        address tokenA,
        address tokenB,
        uint256 reserveA,
        uint256 reserveB,
        uint256 totalLiquidity,
        uint256 feePercentage
    ) {
        require(_poolId > 0 && _poolId <= poolCounter, "Invalid pool ID");
        LiquidityPool memory pool = liquidityPools[_poolId];
        return (
            pool.tokenA,
            pool.tokenB,
            pool.reserveA,
            pool.reserveB,
            pool.totalLiquidity,
            pool.feePercentage
        );
    }
    
    /**
     * @dev Deactivates a strand (only creator can deactivate)
     */
    function deactivateStrand(uint256 _strandId) external {
        require(_strandId > 0 && _strandId <= strandCounter, "Invalid strand ID");
        require(strands[_strandId].creator == msg.sender || msg.sender == owner(), "Not authorized");
        require(strands[_strandId].isActive, "Strand already inactive");
        
        strands[_strandId].isActive = false;
        emit StrandDeactivated(_strandId);
    }
    
    /**
     * @dev Emergency withdrawal function
     */
    function emergencyWithdraw(uint256 _strandId) external nonReentrant {
        require(_strandId > 0 && _strandId <= strandCounter, "Invalid strand ID");
        Position storage position = userPositions[_strandId][msg.sender];
        require(position.isActive && position.depositAmount > 0, "No active position");
        
        uint256 withdrawAmount = position.depositAmount;
        
        // Reset position
        position.depositAmount = 0;
        position.isActive = false;
        position.accruedYield = 0;
        
        // Update strand and TVL
        strands[_strandId].totalDeposited -= withdrawAmount;
        totalValueLocked -= withdrawAmount;
        
        // Transfer funds
        (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
        require(success, "Withdrawal failed");
        
        emit EmergencyWithdrawal(msg.sender, withdrawAmount);
    }
    
    /**
     * @dev Pause contract (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause contract (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Get total number of strands created
     */
    function getTotalStrands() external view returns (uint256) {
        return strandCounter;
    }
    
    /**
     * @dev Get total value locked in the protocol
     */
    function getTotalValueLocked() external view returns (uint256) {
        return totalValueLocked;
    }
    
    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}
}