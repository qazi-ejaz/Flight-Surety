pragma solidity ^0.4.25;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";


/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)
    using SafeMath for uint8;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;
    uint8 private constant STATUS_CODE_CONSENSUS_COUNT = 4;
    uint256 public constant STATUS_CODE_MAX_FEE = 1 ether;
    uint256 public constant STATUS_CODE_MIN_CREDIT = 10 ether;
    address private contractOwner; // Account used to deploy contract
    uint8 public registeredAirlinesCounter = 1;
    FlightSuretyData _flightSuretyData;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }
    mapping(bytes32 => Flight) private flights;
    struct airlineConsensus {
        address airline;
        bool poll;
    }

    mapping(address => mapping(address => bool)) private airlinePolls;

    mapping(address => uint8) private noOfVoters;

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        //  call data contract's status
        require(
            _flightSuretyData.isOperational(),
            "Contract is currently not operational"
        );
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireIsAirlineRegistered() {
        require(
            _flightSuretyData.isAirlineRegistered(msg.sender),
            "Airline is not registered"
        );
        _;
    }

    modifier requireIsNotRegistered(address airline) {
        require(
            !_flightSuretyData.isAirlineRegistered(airline),
            "Airline is already registered"
        );
        _;
    }
    modifier requireAirlineRegistered(address airline) {
        require(
            _flightSuretyData.isAirlineRegistered(airline),
            "Airline is not registered"
        );
        _;
    }
    modifier requireIsFundsDeposited() {
        bool funded = false;
        uint256 funds = _flightSuretyData.getAirlineFunds(msg.sender);
        if (funds >= STATUS_CODE_MIN_CREDIT) funded = true;

        require(
            funded == true,
            "Please make sure to submit 10 ether for Airline to participate in contract"
        );
        _;
    }

    modifier requireIsTimestampValid(uint256 timestamp) {
        uint256 currentTime = block.timestamp;
        require(timestamp >= currentTime, "Timetstamp is not valid");
        _;
    }

    modifier requireInsuranceNotPurchased(
        address airline,
        string flight,
        uint256 timestamp
    ) {
        require(
            _flightSuretyData.isnotinsured(
                airline,
                flight,
                timestamp,
                msg.sender
            ),
            "You are already insured"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
     * @dev Contract constructor
     *
     */
    constructor(address dataContract) public {
        contractOwner = msg.sender;
        _flightSuretyData = FlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns (bool) {
        return _flightSuretyData.isOperational(); // Modify to call data contract's status
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue. If there are more than 4 registered airlines
     *      then there needs to be a consensus of 50% of the registered airlines
     *
     */

    function registerAirline(address airline)
        external
        requireIsOperational
        requireIsAirlineRegistered
        requireIsFundsDeposited
        requireIsNotRegistered(airline)
        returns (bool success, uint256 votes)
    {
        require(airline != address(0), "'airline' must be a valid address.");
        success = false;
        votes = 0;
        if (registeredAirlinesCounter < STATUS_CODE_CONSENSUS_COUNT) {
            success = _flightSuretyData.registerAirline(airline);
            if (success) {
                registeredAirlinesCounter++;
            }
        } else {
            mapping(address => bool) supportingAirlines = airlinePolls[airline];
            //check if the airline is not calling 2nd time
            if (!supportingAirlines[msg.sender]) {
                airlinePolls[airline][msg.sender] = true; //add the sender to the list of voters for the airline
                noOfVoters[airline]++;
                if (noOfVoters[airline] >= registeredAirlinesCounter.div(2)) {
                    success = _flightSuretyData.registerAirline(airline);
                    votes = noOfVoters[airline];
                    if (success) {
                        registeredAirlinesCounter++;
                    }
                }
            }
        }

        return (success, votes);
    }

    /**
     * @dev add funds for airline.
     *
     */
    function AirlineFunding()
        public
        payable
        requireIsOperational
        requireAirlineRegistered(msg.sender)
    {
        // Transfer Fund to Data Contract
        address(_flightSuretyData).transfer(msg.value);
        _flightSuretyData.fundAirline(msg.sender, msg.value);
    }

    /**
     * @dev Register a future flight for insuring.Timestamp is the departure time of a flight.
     *       Purchase Flight insurance before flight departure
     */

    function registerFlight(
        address airline,
        string flight,
        uint256 timestamp
    )
        public
        payable
        requireIsOperational
        requireAirlineRegistered(airline)
        requireIsTimestampValid(timestamp)
        requireInsuranceNotPurchased(airline, flight, timestamp)
    {
        require(
            msg.value <= STATUS_CODE_MAX_FEE,
            "Insurance fee must be less than 1 ether"
        );
        //check if the passenger already has insurance

        address(_flightSuretyData).transfer(msg.value);

        _flightSuretyData.buy(
            airline,
            flight,
            timestamp,
            msg.sender,
            msg.value
        );
    }

    //test
    //uint balance = 150;

    /**
     * @dev Called after oracle has updated flight status
     *
     */

    function processFlightStatus(
        address airline,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    ) internal requireIsOperational {
        // address[] memory insurees = _flightSuretyData.getInsurees(airline, flight, timestamp);

        if (statusCode == STATUS_CODE_LATE_AIRLINE) {
            _flightSuretyData.creditInsurees(
                airline,
                flight,
                timestamp,
                15,
                10
            );
        }
    }

    /*  function getBalancetest() public view returns(uint)
   {
    return balance;
   } */
    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(
        address airline,
        string flight,
        uint256 timestamp
    ) external requireIsOperational requireAirlineRegistered(airline) {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        oracleResponses[key] = ResponseInfo({
            requester: msg.sender,
            isOpen: true
        });

        emit OracleRequest(index, airline, flight, timestamp);
    }

    // region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester; // Account that requested status
        bool isOpen; // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses; // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    event OracleReport(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp
    );

    // Register an oracle with the contract
    function registerOracle() external payable requireIsOperational {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes()
        external
        view
        requireIsOperational
        returns (uint8[3])
    {
        require(
            oracles[msg.sender].isRegistered,
            "Not registered as an oracle"
        );

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    ) external requireIsOperational {
        require(
            (oracles[msg.sender].indexes[0] == index) ||
                (oracles[msg.sender].indexes[1] == index) ||
                (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );

        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        require(oracleResponses[key].isOpen, "oracle request already resolved");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);

        if (
            oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES
        ) {
            oracleResponses[key].isOpen = false;

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }

    function getFlightKey(
        address airline,
        string flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns (uint8[3]) {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(blockhash(block.number - nonce++), account)
                )
            ) % maxValue
        );

        if (nonce > 250) {
            nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    function getExistingAirlines()
        public
        view
        requireIsOperational
        returns (address[])
    {
        return _flightSuretyData.getAirlines();
    }

    function getAirlineFunds(address airline)
        public
        view
        requireIsOperational
        returns (uint256 funds)
    {
        return _flightSuretyData.getAirlineFunds(airline);
    }

    function getBalance()
        public
        view
        requireIsOperational
        returns (uint256 funds)
    {
        return _flightSuretyData.getPassengerFunds(msg.sender);
    }

    function withdrawFunds(uint256 amount)
        public
        requireIsOperational
        returns (uint256 funds)
    {
        uint256 balance = _flightSuretyData.getPassengerFunds(msg.sender);
        require(amount <= balance, "Requested amount exceeds balance");

        return _flightSuretyData.withdrawPassengerFunds(amount, msg.sender);
    }

    /*  function getInsured(address airline, string flight, uint ts) public view returns(address[] insurees)
            {
                return _flightSuretyData.getInsurees(airline,flight,ts);
            }
            function getInsuredamount(address airline, string flight, uint ts) public view returns(uint amount)
            {
                return _flightSuretyData.getInsureesAmount(airline,flight,ts);
            } */

    // endregion
}


contract FlightSuretyData {
    //address [] public insurees;
    function isOperational() public view returns (bool);

    function isAirlineRegistered(address airline) public view returns (bool);

    // function isAirlineFunded(address airline) public view returns (bool);
    function registerAirline(address airline) external returns (bool success);

    function fundAirline(address airline, uint256 amount) external;

    function buy(
        address airline,
        string flight,
        uint256 timestamp,
        address passenger,
        uint256 amount
    ) external;

    function creditInsurees(
        address airline,
        string flight,
        uint256 timestamp,
        uint256 factor_numerator,
        uint256 factor_denominator
    ) external;

    function getAirlines() external view returns (address[]);

    function getAirlineFunds(address airline)
        external
        view
        returns (uint256 funds);

    function isnotinsured(
        address airline,
        string flight,
        uint256 timestamp,
        address passenger
    ) external view returns (bool);

    function getPassengerFunds(address passenger)
        external
        view
        returns (uint256);

    function withdrawPassengerFunds(uint256 amount, address passenger)
        external
        returns (uint256);
}
