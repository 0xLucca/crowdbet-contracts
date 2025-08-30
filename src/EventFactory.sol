// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Market.sol";
import "./interfaces/IPricingCurve.sol";
// import "./resolvers/ManualResolver.sol";
// import "./resolvers/TimeBasedResolver.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title EventFactory
 * @dev Factory contract for creating prediction market events with multiple markets
 */
contract EventFactory is Ownable, ReentrancyGuard {
    // Market configuration structure
    struct MarketConfig {
        string question;
        uint256 endTime;
        address pricingCurve;
        address oracle; // Only used for time-based resolution, ignored for manual
        uint256 creatorFeePercentage; // Fee percentage set by event creator in basis points
    }
    
    // Event structure
    struct Event {
        string title;
        string description;
        address creator;
        uint256 createdAt;
        uint256[] marketIds;
        bool exists;
    }
    
    // Market structure
    struct MarketInfo {
        address marketContract;
        string question;
        uint256 eventId;
        uint256 endTime;
        address resolver;
        address pricingCurve;
        bool exists;
    }
    
    // State variables
    mapping(uint256 => Event) public events;
    mapping(uint256 => MarketInfo) public markets;
    
    uint256 public nextEventId = 1;
    uint256 public nextMarketId = 1;
    
    // Protocol configuration
    uint256 public protocolFeeSharePercentage = 5000; // 50% of creator fees go to protocol (in basis points)
    address public protocolFeeRecipient;
    uint256 public maxCreatorFeePercentage = 5000; // Max 50% creator fee allowed
    
    mapping(address => bool) public approvedPricingCurves;
    
    // Events
    event EventCreated(
        uint256 indexed eventId,
        string title,
        address indexed creator,
        uint256[] marketIds
    );
    
    event MarketCreated(
        uint256 indexed marketId,
        uint256 indexed eventId,
        address indexed marketContract,
        string question
    );
    
    event PricingCurveApproved(address indexed pricingCurve, bool approved);
    event ProtocolFeeShareUpdated(uint256 oldShare, uint256 newShare);
    event ProtocolFeeRecipientUpdated(address oldRecipient, address newRecipient);
    event MaxCreatorFeeUpdated(uint256 oldMaxFee, uint256 newMaxFee);
    
    // Errors
    error EventNotFound();
    error MarketNotFound();
    error InvalidResolver();
    error InvalidPricingCurve();
    error InvalidFeePercentage();
    error CreatorFeeExceedsMaximum();
    error InvalidEndTime();
    error EmptyQuestion();
    error EmptyTitle();
    error NoMarketsProvided();
    
    /**
     * @dev Constructor
     * @param _protocolFeeRecipient Address to receive protocol fees
     */
    constructor(address _protocolFeeRecipient) Ownable(msg.sender) {
        require(_protocolFeeRecipient != address(0), "Invalid fee recipient");
        protocolFeeRecipient = _protocolFeeRecipient;
    }
    
    /**
     * @dev Creates a new manual resolution event with multiple markets
     * @param title The title of the event
     * @param description The description of the event
     * @param marketConfigs Array of market configurations (oracle field ignored)
     * @return eventId The ID of the created event
     * @return marketIds Array of created market IDs
     */
    function createManualEvent(
        string memory title,
        string memory description,
        MarketConfig[] memory marketConfigs
    ) external nonReentrant returns (uint256 eventId, uint256[] memory marketIds) {
        // Validation
        if (bytes(title).length == 0) revert EmptyTitle();
        if (marketConfigs.length == 0) revert NoMarketsProvided();
        
        return _createEventInternal(title, description, marketConfigs, msg.sender, true);
    }
    
    /**
     * @dev Internal function to create events
     */
    function _createEventInternal(
        string memory title,
        string memory description,
        MarketConfig[] memory marketConfigs,
        address resolver,
        bool isManual
    ) internal returns (uint256 eventId, uint256[] memory marketIds) {
        eventId = nextEventId++;
        marketIds = new uint256[](marketConfigs.length);
        
        // Create the event first so creator is available
        events[eventId] = Event({
            title: title,
            description: description,
            creator: msg.sender,
            createdAt: block.timestamp,
            marketIds: marketIds,
            exists: true
        });
        
        // Create markets for the event
        for (uint256 i = 0; i < marketConfigs.length; i++) {
            marketIds[i] = _createMarket(eventId, marketConfigs[i], resolver, isManual);
        }

        // Update the event with the actual market IDs
        events[eventId].marketIds = marketIds;
        
        emit EventCreated(eventId, title, msg.sender, marketIds);
    }
    
    /**
     * @dev Internal function to create a single market
     */
    function _createMarket(
        uint256 eventId,
        MarketConfig memory config,
        address resolver,
        bool isManual
    ) internal returns (uint256 marketId) {
        // Validation
        if (bytes(config.question).length == 0) revert EmptyQuestion();
        if (config.endTime <= block.timestamp) revert InvalidEndTime();
        if (!approvedPricingCurves[config.pricingCurve]) revert InvalidPricingCurve();
        if (config.creatorFeePercentage > maxCreatorFeePercentage) revert CreatorFeeExceedsMaximum();
        
        marketId = nextMarketId++;
        
        // Deploy the market contract
        Market market = new Market(
            marketId,
            config.question,
            config.endTime,
            config.creatorFeePercentage,
            protocolFeeSharePercentage,
            protocolFeeRecipient,
            events[eventId].creator,
            resolver,
            IPricingCurve(config.pricingCurve)
        );
        
        // Store market info
        markets[marketId] = MarketInfo({
            marketContract: address(market),
            question: config.question,
            eventId: eventId,
            endTime: config.endTime,
            resolver: resolver,
            pricingCurve: config.pricingCurve,
            exists: true
        });
        
        // // Auto-configure the resolver for the event creator
        // _configureResolver(marketId, config, resolver, isManual, events[eventId].creator);
        
        emit MarketCreated(marketId, eventId, address(market), config.question);
    }
    
    /**
     * @dev Approves or disapproves a pricing curve contract
     * @param pricingCurve The pricing curve contract address
     * @param approved Whether to approve or disapprove
     */
    function setPricingCurveApproval(address pricingCurve, bool approved) external onlyOwner {
        approvedPricingCurves[pricingCurve] = approved;
        emit PricingCurveApproved(pricingCurve, approved);
    }
    
    
    /**
     * @dev Updates the protocol fee share percentage
     * @param newSharePercentage New share percentage in basis points (max 10000 = 100%)
     */
    function setProtocolFeeShare(uint256 newSharePercentage) external onlyOwner {
        if (newSharePercentage > 10000) revert InvalidFeePercentage(); // Max 100%
        
        uint256 oldShare = protocolFeeSharePercentage;
        protocolFeeSharePercentage = newSharePercentage;
        
        emit ProtocolFeeShareUpdated(oldShare, newSharePercentage);
    }
    
    /**
     * @dev Updates the maximum creator fee percentage
     * @param newMaxFeePercentage New max fee percentage in basis points (max 2000 = 20%)
     */
    function setMaxCreatorFeePercentage(uint256 newMaxFeePercentage) external onlyOwner {
        if (newMaxFeePercentage > 2000) revert InvalidFeePercentage(); // Max 20%
        
        uint256 oldMaxFee = maxCreatorFeePercentage;
        maxCreatorFeePercentage = newMaxFeePercentage;
        
        emit MaxCreatorFeeUpdated(oldMaxFee, newMaxFeePercentage);
    }
    
    /**
     * @dev Updates the protocol fee recipient
     * @param newRecipient New fee recipient address
     */
    function setProtocolFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        
        address oldRecipient = protocolFeeRecipient;
        protocolFeeRecipient = newRecipient;
        
        emit ProtocolFeeRecipientUpdated(oldRecipient, newRecipient);
    }
    
    /**
     * @dev Gets event information
     * @param eventId The event ID
     * @return title Event title
     * @return description Event description
     * @return creator Event creator address
     * @return createdAt Creation timestamp
     * @return marketIds Array of market IDs in this event
     */
    function getEvent(uint256 eventId) external view returns (
        string memory title,
        string memory description,
        address creator,
        uint256 createdAt,
        uint256[] memory marketIds
    ) {
        Event storage evt = events[eventId];
        if (!evt.exists) revert EventNotFound();
        
        return (evt.title, evt.description, evt.creator, evt.createdAt, evt.marketIds);
    }
    
    /**
     * @dev Gets market information
     * @param marketId The market ID
     * @return marketContract Market contract address
     * @return question Market question
     * @return eventId Parent event ID
     * @return endTime Market end time
     * @return resolver Resolver contract address
     * @return pricingCurve Pricing curve contract address
     */
    function getMarket(uint256 marketId) external view returns (
        address marketContract,
        string memory question,
        uint256 eventId,
        uint256 endTime,
        address resolver,
        address pricingCurve
    ) {
        MarketInfo storage market = markets[marketId];
        if (!market.exists) revert MarketNotFound();
        
        return (
            market.marketContract,
            market.question,
            market.eventId,
            market.endTime,
            market.resolver,
            market.pricingCurve
        );
    }
    
    /**
     * @dev Gets all markets for an event
     * @param eventId The event ID
     * @return marketContracts Array of market contract addresses
     */
    function getEventMarkets(uint256 eventId) external view returns (address[] memory marketContracts) {
        Event storage evt = events[eventId];
        if (!evt.exists) revert EventNotFound();
        
        marketContracts = new address[](evt.marketIds.length);
        for (uint256 i = 0; i < evt.marketIds.length; i++) {
            marketContracts[i] = markets[evt.marketIds[i]].marketContract;
        }
    }

    /**
     * @dev Gets a specific event with all its market information
     * @param eventId The event ID to get
     * @return eventInfo The event information
     * @return marketInfos Array of market information for this event
     */
    function getEventWithMarkets(uint256 eventId) external view returns (
        Event memory eventInfo,
        MarketInfo[] memory marketInfos
    ) {
        Event storage evt = events[eventId];
        if (!evt.exists) revert EventNotFound();
        
        eventInfo = evt;
        marketInfos = new MarketInfo[](evt.marketIds.length);
        
        for (uint256 i = 0; i < evt.marketIds.length; i++) {
            marketInfos[i] = markets[evt.marketIds[i]];
        }
    }

    /**
     * @dev Returns all events with their underlying markets information
     * @return allEvents Array of all events with their market information
     */
    function getAllEventsWithMarkets() external view returns (
        Event[] memory allEvents,
        MarketInfo[][] memory allMarkets
    ) {
        allEvents = new Event[](nextEventId - 1);
        allMarkets = new MarketInfo[][](nextEventId - 1);

        for (uint256 i = 1; i < nextEventId; i++) {
            Event storage evt = events[i];
            if (evt.exists) {
                allEvents[i - 1] = evt;
                allMarkets[i - 1] = new MarketInfo[](evt.marketIds.length);
                for (uint256 j = 0; j < evt.marketIds.length; j++) {
                    allMarkets[i - 1][j] = markets[evt.marketIds[j]];
                }
            }
        }
    }
}
