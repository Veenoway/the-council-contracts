// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CouncilPredictions
 * @notice Prediction market for The Council AI trading bots
 * @dev Users must hold the token to bet. Bots can bet but not on themselves.
 */
contract CouncilPredictions is Ownable, ReentrancyGuard {
    
    // ============================================================
    // ENUMS
    // ============================================================
    
    enum PredictionType {
        PRICE,      // Will token reach X price?
        BOT_ROI,    // Which bot will have highest ROI?
        VOLUME,     // Will volume reach X?
        CUSTOM      // Custom prediction
    }
    
    // ============================================================
    // STRUCTS
    // ============================================================
    
    struct Prediction {
        uint256 id;
        address tokenAddress;
        string question;
        PredictionType predictionType;
        uint256 endTime;
        uint256 resolveTime;
        uint256 prizePool;
        uint256 totalBets;
        uint8 numOptions;
        uint8 winningOption;
        bool resolved;
        bool cancelled;
        bool isTie;
        address creator;
    }
    
    struct Option {
        string label;
        uint256 totalStaked;
        uint256 numBettors;
    }
    
    struct Bet {
        uint256 predictionId;
        uint8 optionId;
        uint256 amount;
        bool claimed;
        uint256 timestamp;
    }
    
    struct PredictionView {
        uint256 id;
        address tokenAddress;
        string question;
        PredictionType predictionType;
        uint256 endTime;
        uint256 resolveTime;
        uint256 prizePool;
        uint256 totalBets;
        uint8 numOptions;
        uint8 winningOption;
        bool resolved;
        bool cancelled;
        bool isTie;
        address creator;
        uint256 createdAt;
        Option[] options;
    }
    
    struct UserStats {
        uint256 totalBets;
        uint256 totalStaked;
        uint256 totalWon;
        uint256 totalLost;
        uint256 activeBets;
        uint256 claimableBets;
    }
    
    struct BotInfo {
        string botId;       // "chad", "quantum", etc.
        uint8 optionId;     // Corresponding option in BOT_ROI predictions
        bool isActive;
    }
    
    // ============================================================
    // STATE
    // ============================================================
    
    uint256 public predictionCount;
    uint256 public minBetAmount = 0.1 ether;
    uint256 public maxBetAmount = 100 ether;
    uint256 public minTokenHolding = 1;
    uint256 public platformFee = 250;  // 2.5%
    uint256 public accumulatedFees;
    uint256 public totalVolumeAllTime;
    
    mapping(uint256 => Prediction) public predictions;
    mapping(uint256 => mapping(uint8 => Option)) public options;
    mapping(address => mapping(uint256 => Bet)) public userBets;
    mapping(uint256 => mapping(address => bool)) public hasBet;
    mapping(address => bool) public oracles;
    
    mapping(uint256 => uint256) public predictionCreatedAt;
    mapping(uint256 => address[]) public predictionBettors;
    mapping(address => uint256[]) public userPredictionIds;
    mapping(uint256 => uint8[]) public tiedWinningOptions;
    
    // Bot management
    mapping(address => BotInfo) public botWallets;      // wallet => bot info
    mapping(string => address) public botIdToWallet;    // botId => wallet
    address[] public registeredBots;
    
    // ============================================================
    // EVENTS
    // ============================================================
    
    event PredictionCreated(
        uint256 indexed predictionId,
        address indexed creator,
        address tokenAddress,
        string question,
        PredictionType predictionType,
        uint256 endTime,
        string[] optionLabels
    );
    
    event BetPlaced(
        uint256 indexed predictionId,
        address indexed user,
        uint8 optionId,
        uint256 amount,
        bool isBot
    );
    
    event PredictionResolved(
        uint256 indexed predictionId,
        uint8 winningOption,
        uint256 prizePool,
        bool isTie
    );
    
    event WinningsClaimed(
        uint256 indexed predictionId,
        address indexed user,
        uint256 amount
    );
    
    event PredictionCancelled(uint256 indexed predictionId);
    event RefundClaimed(uint256 indexed predictionId, address indexed user, uint256 amount);
    event BotRegistered(address indexed wallet, string botId);
    event BotUnregistered(address indexed wallet, string botId);
    event PoolSeeded(uint256 indexed predictionId, uint256 amount);
    event BetIncreased(uint256 indexed predictionId, address indexed user, uint8 optionId, uint256 addedAmount, uint256 totalAmount);
    
    // ============================================================
    // ERRORS
    // ============================================================
    
    error PredictionNotFound();
    error PredictionAlreadyResolved();
    error PredictionCancelled_();
    error BettingEnded();
    error InvalidOption();
    error BetTooSmall();
    error BetTooLarge();
    error AlreadyBet();
    error MustHoldToken();
    error BotCannotBetOnSelf();
    error NotOracle();
    error BettingStillOpen();
    error NotWinner();
    error AlreadyClaimed();
    error NoBetFound();
    error NotCancelled();
    error TransferFailed();
    
    // ============================================================
    // MODIFIERS
    // ============================================================
    
    modifier onlyOracle() {
        if (!oracles[msg.sender] && msg.sender != owner()) revert NotOracle();
        _;
    }
    
    modifier predictionExists(uint256 _predictionId) {
        if (_predictionId == 0 || _predictionId > predictionCount) revert PredictionNotFound();
        _;
    }
    
    // ============================================================
    // CONSTRUCTOR
    // ============================================================
    
    constructor() Ownable(msg.sender) {
        oracles[msg.sender] = true;
    }
    
    // ============================================================
    // BOT MANAGEMENT
    // ============================================================
    
    /**
     * @notice Register a bot wallet
     * @param _wallet Bot's wallet address
     * @param _botId Bot identifier ("chad", "quantum", etc.)
     * @param _optionId Corresponding option ID in BOT_ROI predictions
     */
    function registerBot(address _wallet, string calldata _botId, uint8 _optionId) external onlyOwner {
        require(_wallet != address(0), "Invalid wallet");
        require(bytes(_botId).length > 0, "Invalid botId");
        
        botWallets[_wallet] = BotInfo({
            botId: _botId,
            optionId: _optionId,
            isActive: true
        });
        
        botIdToWallet[_botId] = _wallet;
        registeredBots.push(_wallet);
        
        emit BotRegistered(_wallet, _botId);
    }
    
    /**
     * @notice Unregister a bot
     */
    function unregisterBot(address _wallet) external onlyOwner {
        BotInfo storage bot = botWallets[_wallet];
        require(bot.isActive, "Bot not registered");
        
        string memory botId = bot.botId;
        bot.isActive = false;
        delete botIdToWallet[botId];
        
        emit BotUnregistered(_wallet, botId);
    }
    
    /**
     * @notice Check if address is a registered bot
     */
    function isBot(address _wallet) public view returns (bool) {
        return botWallets[_wallet].isActive;
    }
    
    /**
     * @notice Get bot's option ID for BOT_ROI predictions
     */
    function getBotOptionId(address _wallet) public view returns (uint8) {
        return botWallets[_wallet].optionId;
    }
    
    // ============================================================
    // CORE FUNCTIONS
    // ============================================================
    
    /**
     * @notice Create a new prediction market
     * @dev Can optionally seed the pool with initial liquidity (split evenly across options)
     */
    function createPrediction(
        address _tokenAddress,
        string calldata _question,
        PredictionType _type,
        uint256 _duration,
        string[] calldata _optionLabels
    ) external payable returns (uint256) {
        require(_tokenAddress != address(0), "Invalid token address");
        require(bytes(_question).length > 0, "Question cannot be empty");
        require(_duration >= 1 hours, "Duration too short");
        require(_duration <= 30 days, "Duration too long");
        require(_optionLabels.length >= 2, "Need at least 2 options");
        require(_optionLabels.length <= 10, "Too many options");
        
        predictionCount++;
        uint256 predictionId = predictionCount;
        
        // Calculate initial seed per option (if any MON sent)
        uint256 seedPerOption = msg.value / _optionLabels.length;
        uint256 initialPool = seedPerOption * _optionLabels.length; // Handle rounding
        
        predictions[predictionId] = Prediction({
            id: predictionId,
            tokenAddress: _tokenAddress,
            question: _question,
            predictionType: _type,
            endTime: block.timestamp + _duration,
            resolveTime: 0,
            prizePool: initialPool,
            totalBets: 0,
            numOptions: uint8(_optionLabels.length),
            winningOption: 0,
            resolved: false,
            cancelled: false,
            isTie: false,
            creator: msg.sender
        });
        
        predictionCreatedAt[predictionId] = block.timestamp;
        
        for (uint8 i = 0; i < _optionLabels.length; i++) {
            options[predictionId][i + 1] = Option({
                label: _optionLabels[i],
                totalStaked: seedPerOption,  // Seed each option
                numBettors: 0
            });
        }
        
        emit PredictionCreated(
            predictionId,
            msg.sender,
            _tokenAddress,
            _question,
            _type,
            block.timestamp + _duration,
            _optionLabels
        );
        
        if (msg.value > 0) {
            emit PoolSeeded(predictionId, msg.value);
        }
        
        return predictionId;
    }
    
    /**
     * @notice Place a bet on a prediction (or add to existing bet)
     * @dev Bots cannot bet on themselves in BOT_ROI predictions
     * @dev Users can add to their existing bet on the same option
     */
    function placeBet(
        uint256 _predictionId,
        uint8 _optionId
    ) external payable nonReentrant predictionExists(_predictionId) {
        Prediction storage prediction = predictions[_predictionId];
        
        if (prediction.resolved) revert PredictionAlreadyResolved();
        if (prediction.cancelled) revert PredictionCancelled_();
        if (block.timestamp >= prediction.endTime) revert BettingEnded();
        if (_optionId == 0 || _optionId > prediction.numOptions) revert InvalidOption();
        if (msg.value < minBetAmount) revert BetTooSmall();
        if (msg.value > maxBetAmount) revert BetTooLarge();
        
        bool isBotBetting = isBot(msg.sender);
        
        // Bot restriction: cannot bet on self in BOT_ROI predictions
        if (isBotBetting && prediction.predictionType == PredictionType.BOT_ROI) {
            uint8 botOption = getBotOptionId(msg.sender);
            if (_optionId == botOption) revert BotCannotBetOnSelf();
        }
        
        // Token holding check (bots are exempt)
        if (!isBotBetting) {
            if (!_holdsToken(msg.sender, prediction.tokenAddress)) revert MustHoldToken();
        }
        
        // Check if user already has a bet
        if (hasBet[_predictionId][msg.sender]) {
            // User already bet - allow adding to same option only
            Bet storage existingBet = userBets[msg.sender][_predictionId];
            require(existingBet.optionId == _optionId, "Can only add to same option");
            
            // Add to existing bet
            existingBet.amount += msg.value;
            
            options[_predictionId][_optionId].totalStaked += msg.value;
            prediction.prizePool += msg.value;
            totalVolumeAllTime += msg.value;
            
            emit BetIncreased(_predictionId, msg.sender, _optionId, msg.value, existingBet.amount);
        } else {
            // New bet
            userBets[msg.sender][_predictionId] = Bet({
                predictionId: _predictionId,
                optionId: _optionId,
                amount: msg.value,
                claimed: false,
                timestamp: block.timestamp
            });
            
            hasBet[_predictionId][msg.sender] = true;
            predictionBettors[_predictionId].push(msg.sender);
            userPredictionIds[msg.sender].push(_predictionId);
            
            options[_predictionId][_optionId].totalStaked += msg.value;
            options[_predictionId][_optionId].numBettors++;
            
            prediction.prizePool += msg.value;
            prediction.totalBets++;
            totalVolumeAllTime += msg.value;
            
            emit BetPlaced(_predictionId, msg.sender, _optionId, msg.value, isBotBetting);
        }
    }
    
    /**
     * @notice Resolve a prediction with tie support
     */
    function resolvePrediction(
        uint256 _predictionId,
        uint8 _winningOption,
        bool _isTie,
        uint8[] calldata _tiedOptions
    ) external onlyOracle predictionExists(_predictionId) {
        Prediction storage prediction = predictions[_predictionId];
        
        if (prediction.resolved) revert PredictionAlreadyResolved();
        if (prediction.cancelled) revert PredictionCancelled_();
        if (block.timestamp < prediction.endTime) revert BettingStillOpen();
        if (_winningOption == 0 || _winningOption > prediction.numOptions) revert InvalidOption();
        
        prediction.resolved = true;
        prediction.winningOption = _winningOption;
        prediction.resolveTime = block.timestamp;
        prediction.isTie = _isTie;
        
        if (_isTie && _tiedOptions.length > 0) {
            for (uint i = 0; i < _tiedOptions.length; i++) {
                tiedWinningOptions[_predictionId].push(_tiedOptions[i]);
            }
        }
        
        uint256 fee = (prediction.prizePool * platformFee) / 10000;
        accumulatedFees += fee;
        
        emit PredictionResolved(_predictionId, _winningOption, prediction.prizePool, _isTie);
    }
    
    /**
     * @notice Resolve without tie (backwards compatible)
     */
    function resolvePrediction(
        uint256 _predictionId,
        uint8 _winningOption
    ) external onlyOracle predictionExists(_predictionId) {
        Prediction storage prediction = predictions[_predictionId];
        
        if (prediction.resolved) revert PredictionAlreadyResolved();
        if (prediction.cancelled) revert PredictionCancelled_();
        if (block.timestamp < prediction.endTime) revert BettingStillOpen();
        if (_winningOption == 0 || _winningOption > prediction.numOptions) revert InvalidOption();
        
        prediction.resolved = true;
        prediction.winningOption = _winningOption;
        prediction.resolveTime = block.timestamp;
        
        uint256 fee = (prediction.prizePool * platformFee) / 10000;
        accumulatedFees += fee;
        
        emit PredictionResolved(_predictionId, _winningOption, prediction.prizePool, false);
    }
    
    /**
     * @notice Claim winnings
     */
    function claimWinnings(uint256 _predictionId) external nonReentrant predictionExists(_predictionId) {
        Prediction storage prediction = predictions[_predictionId];
        Bet storage bet = userBets[msg.sender][_predictionId];
        
        if (!prediction.resolved) revert PredictionNotFound();
        if (prediction.cancelled) revert PredictionCancelled_();
        if (bet.amount == 0) revert NoBetFound();
        if (bet.claimed) revert AlreadyClaimed();
        
        bool winner = _isWinner(_predictionId, bet.optionId);
        if (!winner) revert NotWinner();
        
        bet.claimed = true;
        
        uint256 winnings;
        uint256 poolAfterFee = prediction.prizePool - ((prediction.prizePool * platformFee) / 10000);
        
        if (prediction.isTie) {
            uint256 totalTiedStake = 0;
            for (uint i = 0; i < tiedWinningOptions[_predictionId].length; i++) {
                totalTiedStake += options[_predictionId][tiedWinningOptions[_predictionId][i]].totalStaked;
            }
            winnings = (bet.amount * poolAfterFee) / totalTiedStake;
        } else {
            Option storage winningOpt = options[_predictionId][prediction.winningOption];
            winnings = (bet.amount * poolAfterFee) / winningOpt.totalStaked;
        }
        
        (bool success, ) = payable(msg.sender).call{value: winnings}("");
        if (!success) revert TransferFailed();
        
        emit WinningsClaimed(_predictionId, msg.sender, winnings);
    }
    
    /**
     * @notice Cancel a prediction
     */
    function cancelPrediction(uint256 _predictionId) external onlyOwner predictionExists(_predictionId) {
        Prediction storage prediction = predictions[_predictionId];
        
        if (prediction.resolved) revert PredictionAlreadyResolved();
        if (prediction.cancelled) revert PredictionCancelled_();
        
        prediction.cancelled = true;
        
        emit PredictionCancelled(_predictionId);
    }
    
    /**
     * @notice Claim refund from cancelled prediction
     */
    function claimRefund(uint256 _predictionId) external nonReentrant predictionExists(_predictionId) {
        Prediction storage prediction = predictions[_predictionId];
        Bet storage bet = userBets[msg.sender][_predictionId];
        
        if (!prediction.cancelled) revert NotCancelled();
        if (bet.amount == 0) revert NoBetFound();
        if (bet.claimed) revert AlreadyClaimed();
        
        bet.claimed = true;
        
        (bool success, ) = payable(msg.sender).call{value: bet.amount}("");
        if (!success) revert TransferFailed();
        
        emit RefundClaimed(_predictionId, msg.sender, bet.amount);
    }
    
    // ============================================================
    // INTERNAL FUNCTIONS
    // ============================================================
    
    function _holdsToken(address _user, address _token) internal view returns (bool) {
        try IERC20(_token).balanceOf(_user) returns (uint256 balance) {
            return balance >= minTokenHolding;
        } catch {
            return false;
        }
    }
    
    function _isWinner(uint256 _predictionId, uint8 _optionId) internal view returns (bool) {
        Prediction storage p = predictions[_predictionId];
        if (!p.resolved) return false;
        
        if (p.isTie) {
            for (uint i = 0; i < tiedWinningOptions[_predictionId].length; i++) {
                if (_optionId == tiedWinningOptions[_predictionId][i]) {
                    return true;
                }
            }
            return false;
        }
        
        return _optionId == p.winningOption;
    }
    
    // ============================================================
    // VIEW FUNCTIONS - SINGLE
    // ============================================================
    
    function getPrediction(uint256 _predictionId) external view returns (
        Prediction memory prediction,
        Option[] memory opts
    ) {
        prediction = predictions[_predictionId];
        opts = new Option[](prediction.numOptions);
        
        for (uint8 i = 1; i <= prediction.numOptions; i++) {
            opts[i - 1] = options[_predictionId][i];
        }
    }
    
    function getPredictionFull(uint256 _predictionId) external view returns (PredictionView memory) {
        Prediction storage p = predictions[_predictionId];
        
        Option[] memory opts = new Option[](p.numOptions);
        for (uint8 i = 1; i <= p.numOptions; i++) {
            opts[i - 1] = options[_predictionId][i];
        }
        
        return PredictionView({
            id: p.id,
            tokenAddress: p.tokenAddress,
            question: p.question,
            predictionType: p.predictionType,
            endTime: p.endTime,
            resolveTime: p.resolveTime,
            prizePool: p.prizePool,
            totalBets: p.totalBets,
            numOptions: p.numOptions,
            winningOption: p.winningOption,
            resolved: p.resolved,
            cancelled: p.cancelled,
            isTie: p.isTie,
            creator: p.creator,
            createdAt: predictionCreatedAt[_predictionId],
            options: opts
        });
    }
    
    function getOption(uint256 _predictionId, uint8 _optionId) external view returns (Option memory) {
        return options[_predictionId][_optionId];
    }
    
    function getAllOptions(uint256 _predictionId) external view returns (Option[] memory) {
        Prediction storage p = predictions[_predictionId];
        Option[] memory opts = new Option[](p.numOptions);
        
        for (uint8 i = 1; i <= p.numOptions; i++) {
            opts[i - 1] = options[_predictionId][i];
        }
        
        return opts;
    }
    
    function getTiedWinningOptions(uint256 _predictionId) external view returns (uint8[] memory) {
        return tiedWinningOptions[_predictionId];
    }
    
    // ============================================================
    // VIEW FUNCTIONS - MULTIPLE
    // ============================================================
    
    function getLatestPredictions(uint256 _count) external view returns (PredictionView[] memory) {
        uint256 count = _count > predictionCount ? predictionCount : _count;
        PredictionView[] memory results = new PredictionView[](count);
        
        for (uint256 i = 0; i < count; i++) {
            uint256 id = predictionCount - i;
            Prediction storage p = predictions[id];
            
            Option[] memory opts = new Option[](p.numOptions);
            for (uint8 j = 1; j <= p.numOptions; j++) {
                opts[j - 1] = options[id][j];
            }
            
            results[i] = PredictionView({
                id: p.id,
                tokenAddress: p.tokenAddress,
                question: p.question,
                predictionType: p.predictionType,
                endTime: p.endTime,
                resolveTime: p.resolveTime,
                prizePool: p.prizePool,
                totalBets: p.totalBets,
                numOptions: p.numOptions,
                winningOption: p.winningOption,
                resolved: p.resolved,
                cancelled: p.cancelled,
                isTie: p.isTie,
                creator: p.creator,
                createdAt: predictionCreatedAt[id],
                options: opts
            });
        }
        
        return results;
    }
    
    function getActivePredictions(uint256 _offset, uint256 _limit) external view returns (
        PredictionView[] memory results,
        uint256 total
    ) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= predictionCount; i++) {
            Prediction storage p = predictions[i];
            if (!p.resolved && !p.cancelled && block.timestamp < p.endTime) {
                activeCount++;
            }
        }
        
        total = activeCount;
        uint256 limit = _limit > 50 ? 50 : _limit;
        results = new PredictionView[](limit);
        
        uint256 collected = 0;
        uint256 skipped = 0;
        
        for (uint256 i = 1; i <= predictionCount && collected < limit; i++) {
            Prediction storage p = predictions[i];
            if (!p.resolved && !p.cancelled && block.timestamp < p.endTime) {
                if (skipped < _offset) {
                    skipped++;
                    continue;
                }
                
                Option[] memory opts = new Option[](p.numOptions);
                for (uint8 j = 1; j <= p.numOptions; j++) {
                    opts[j - 1] = options[i][j];
                }
                
                results[collected] = PredictionView({
                    id: p.id,
                    tokenAddress: p.tokenAddress,
                    question: p.question,
                    predictionType: p.predictionType,
                    endTime: p.endTime,
                    resolveTime: p.resolveTime,
                    prizePool: p.prizePool,
                    totalBets: p.totalBets,
                    numOptions: p.numOptions,
                    winningOption: p.winningOption,
                    resolved: p.resolved,
                    cancelled: p.cancelled,
                    isTie: p.isTie,
                    creator: p.creator,
                    createdAt: predictionCreatedAt[i],
                    options: opts
                });
                
                collected++;
            }
        }
        
        assembly {
            mstore(results, collected)
        }
    }
    
    // ============================================================
    // VIEW FUNCTIONS - USER
    // ============================================================
    
    function getUserBet(address _user, uint256 _predictionId) external view returns (Bet memory) {
        return userBets[_user][_predictionId];
    }
    
    function getUserBets(address _user) external view returns (
        Bet[] memory bets,
        uint256[] memory predictionIds
    ) {
        predictionIds = userPredictionIds[_user];
        bets = new Bet[](predictionIds.length);
        
        for (uint i = 0; i < predictionIds.length; i++) {
            bets[i] = userBets[_user][predictionIds[i]];
        }
    }
    
    function getUserStats(address _user) external view returns (UserStats memory) {
        uint256[] storage pIds = userPredictionIds[_user];
        
        UserStats memory stats;
        stats.totalBets = pIds.length;
        
        for (uint i = 0; i < pIds.length; i++) {
            uint256 predId = pIds[i];
            Bet storage bet = userBets[_user][predId];
            Prediction storage p = predictions[predId];
            
            stats.totalStaked += bet.amount;
            
            if (!p.resolved && !p.cancelled) {
                stats.activeBets++;
            } else if (p.resolved) {
                bool winner = _isWinner(predId, bet.optionId);
                if (winner) {
                    if (!bet.claimed) stats.claimableBets++;
                    stats.totalWon += _calculateWinnings(predId, bet.amount);
                } else {
                    stats.totalLost += bet.amount;
                }
            }
        }
        
        return stats;
    }
    
    function _calculateWinnings(uint256 _predictionId, uint256 _betAmount) internal view returns (uint256) {
        Prediction storage p = predictions[_predictionId];
        uint256 poolAfterFee = p.prizePool - ((p.prizePool * platformFee) / 10000);
        
        if (p.isTie) {
            uint256 totalTiedStake = _getTotalTiedStake(_predictionId);
            return (_betAmount * poolAfterFee) / totalTiedStake;
        } else {
            return (_betAmount * poolAfterFee) / options[_predictionId][p.winningOption].totalStaked;
        }
    }
    
    function _getTotalTiedStake(uint256 _predictionId) internal view returns (uint256) {
        uint256 total = 0;
        uint8[] storage tied = tiedWinningOptions[_predictionId];
        for (uint i = 0; i < tied.length; i++) {
            total += options[_predictionId][tied[i]].totalStaked;
        }
        return total;
    }
    
    function getClaimablePredictions(address _user) external view returns (uint256[] memory) {
        uint256[] storage pIds = userPredictionIds[_user];
        uint256 count = 0;
        
        for (uint i = 0; i < pIds.length; i++) {
            Bet storage bet = userBets[_user][pIds[i]];
            Prediction storage p = predictions[pIds[i]];
            
            if (p.resolved && !bet.claimed && _isWinner(pIds[i], bet.optionId)) {
                count++;
            }
            if (p.cancelled && !bet.claimed) {
                count++;
            }
        }
        
        uint256[] memory claimable = new uint256[](count);
        uint256 idx = 0;
        
        for (uint i = 0; i < pIds.length; i++) {
            Bet storage bet = userBets[_user][pIds[i]];
            Prediction storage p = predictions[pIds[i]];
            
            if (p.resolved && !bet.claimed && _isWinner(pIds[i], bet.optionId)) {
                claimable[idx++] = pIds[i];
            }
            if (p.cancelled && !bet.claimed) {
                claimable[idx++] = pIds[i];
            }
        }
        
        return claimable;
    }
    
    // ============================================================
    // VIEW FUNCTIONS - ODDS & CHECKS
    // ============================================================
    
    function calculatePotentialWinnings(
        uint256 _predictionId,
        uint8 _optionId,
        uint256 _amount
    ) external view returns (uint256) {
        Prediction storage prediction = predictions[_predictionId];
        Option storage opt = options[_predictionId][_optionId];
        
        if (opt.totalStaked == 0) {
            return _amount;
        }
        
        uint256 newOptionTotal = opt.totalStaked + _amount;
        uint256 newPoolTotal = prediction.prizePool + _amount;
        uint256 poolAfterFee = newPoolTotal - ((newPoolTotal * platformFee) / 10000);
        
        return (_amount * poolAfterFee) / newOptionTotal;
    }
    
    function getOdds(uint256 _predictionId, uint8 _optionId) external view returns (uint256) {
        Prediction storage prediction = predictions[_predictionId];
        Option storage opt = options[_predictionId][_optionId];
        
        if (opt.totalStaked == 0 || prediction.prizePool == 0) {
            return 10000;
        }
        
        return (prediction.prizePool * 10000) / opt.totalStaked;
    }
    
    function getAllOdds(uint256 _predictionId) external view returns (uint256[] memory) {
        Prediction storage p = predictions[_predictionId];
        uint256[] memory odds = new uint256[](p.numOptions);
        
        for (uint8 i = 1; i <= p.numOptions; i++) {
            Option storage opt = options[_predictionId][i];
            if (opt.totalStaked == 0 || p.prizePool == 0) {
                odds[i - 1] = 10000;
            } else {
                odds[i - 1] = (p.prizePool * 10000) / opt.totalStaked;
            }
        }
        
        return odds;
    }
    
    function canBet(address _user, uint256 _predictionId) external view returns (bool) {
        Prediction storage prediction = predictions[_predictionId];
        
        if (prediction.resolved || prediction.cancelled) return false;
        if (block.timestamp >= prediction.endTime) return false;
        // Removed: hasBet check - users can now add to existing bets
        
        if (isBot(_user)) return true;
        
        return _holdsToken(_user, prediction.tokenAddress);
    }
    
    function canBetDetailed(address _user, uint256 _predictionId) external view returns (
        bool canBetResult,
        string memory reason
    ) {
        if (_predictionId == 0 || _predictionId > predictionCount) {
            return (false, "Prediction does not exist");
        }
        
        Prediction storage prediction = predictions[_predictionId];
        
        if (prediction.resolved) return (false, "Prediction already resolved");
        if (prediction.cancelled) return (false, "Prediction cancelled");
        if (block.timestamp >= prediction.endTime) return (false, "Betting has ended");
        
        // Check if user already has a bet (but they can still add to it)
        if (hasBet[_predictionId][_user]) {
            return (true, "Can add to existing bet");
        }
        
        if (isBot(_user)) return (true, "Bot can bet");
        
        if (!_holdsToken(_user, prediction.tokenAddress)) return (false, "Must hold token to bet");
        
        return (true, "Can bet");
    }
    
    /**
     * @notice Check if bot can bet on specific option (self-bet restriction)
     */
    function canBotBetOnOption(address _bot, uint256 _predictionId, uint8 _optionId) external view returns (
        bool canBetResult,
        string memory reason
    ) {
        if (!isBot(_bot)) return (false, "Not a bot");
        
        Prediction storage p = predictions[_predictionId];
        if (p.predictionType == PredictionType.BOT_ROI) {
            if (getBotOptionId(_bot) == _optionId) {
                return (false, "Bot cannot bet on itself");
            }
        }
        
        return (true, "Bot can bet on this option");
    }
    
    // ============================================================
    // VIEW FUNCTIONS - GLOBAL & BOTS
    // ============================================================
    
    function getGlobalStats() external view returns (
        uint256 totalPredictions,
        uint256 totalVolume,
        uint256 totalFees,
        uint256 activePredictionCount
    ) {
        totalPredictions = predictionCount;
        totalVolume = totalVolumeAllTime;
        totalFees = accumulatedFees;
        
        for (uint256 i = 1; i <= predictionCount; i++) {
            Prediction storage p = predictions[i];
            if (!p.resolved && !p.cancelled && block.timestamp < p.endTime) {
                activePredictionCount++;
            }
        }
    }
    
    function getPredictionBettors(uint256 _predictionId) external view returns (address[] memory) {
        return predictionBettors[_predictionId];
    }
    
    function getPredictionBettorCount(uint256 _predictionId) external view returns (uint256) {
        return predictionBettors[_predictionId].length;
    }
    
    function getRegisteredBots() external view returns (address[] memory) {
        return registeredBots;
    }
    
    function getBotInfo(address _wallet) external view returns (BotInfo memory) {
        return botWallets[_wallet];
    }
    
    // ============================================================
    // ADMIN FUNCTIONS
    // ============================================================
    
    /**
     * @notice Seed a prediction pool with liquidity (owner only)
     * @param _predictionId The prediction to seed
     * @param _optionId The option to add liquidity to (0 = split evenly)
     */
    function seedPrediction(
        uint256 _predictionId,
        uint8 _optionId
    ) external payable onlyOwner predictionExists(_predictionId) {
        require(msg.value > 0, "Need MON to seed");
        
        Prediction storage prediction = predictions[_predictionId];
        require(!prediction.resolved, "Already resolved");
        require(!prediction.cancelled, "Cancelled");
        
        if (_optionId == 0) {
            // Split evenly across all options
            uint256 perOption = msg.value / prediction.numOptions;
            for (uint8 i = 1; i <= prediction.numOptions; i++) {
                options[_predictionId][i].totalStaked += perOption;
            }
            prediction.prizePool += perOption * prediction.numOptions;
        } else {
            // Seed specific option
            require(_optionId <= prediction.numOptions, "Invalid option");
            options[_predictionId][_optionId].totalStaked += msg.value;
            prediction.prizePool += msg.value;
        }
        
        emit PoolSeeded(_predictionId, msg.value);
    }
    
    function setOracle(address _oracle, bool _status) external onlyOwner {
        oracles[_oracle] = _status;
    }
    
    function setMinBetAmount(uint256 _amount) external onlyOwner {
        minBetAmount = _amount;
    }
    
    function setMaxBetAmount(uint256 _amount) external onlyOwner {
        maxBetAmount = _amount;
    }
    
    function setMinTokenHolding(uint256 _amount) external onlyOwner {
        minTokenHolding = _amount;
    }
    
    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee too high");
        platformFee = _fee;
    }
    
    function withdrawFees() external onlyOwner {
        uint256 amount = accumulatedFees;
        accumulatedFees = 0;
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert TransferFailed();
    }
    
    receive() external payable {}
}
