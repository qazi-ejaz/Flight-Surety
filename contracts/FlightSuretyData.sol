pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";


contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false
    address[] airlines;
    mapping(address => bool) private recordedAirline;
    mapping(address => uint256) private airlineAssets;
    mapping(address => uint256) private approved;
    mapping(address => uint256) private balance;
    mapping(bytes32 => address[]) private airlineinsurees;
    //mapping(address => uint256) private fundedinsurance;
    mapping(address => mapping(bytes32 => uint256)) amountInsurance;
    mapping(bytes32 => mapping(address => uint256)) payoutInsurance;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor(address firstAirline) public {
        contractOwner = msg.sender;
        recordedAirline[firstAirline] = true;
        airlines.push(firstAirline);
    }

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
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireIsContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier requireIsAirlineRegistered(address caller) {
        require(recordedAirline[caller] == true, "Caller not registered");
        _;
    }

    modifier requireIsNotRegistered(address airline) {
        require(
            recordedAirline[airline] == false,
            "Airline already registered"
        );
        _;
    }
    modifier requireIsAuthorized() {
        require(
            approved[msg.sender] == 1,
            "Caller is not contract owner"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */

    function notInsured(
        address airline,
        string flight,
        uint256 timestamp,
        address passenger
    ) external view returns (bool) {
        bytes32 flightkey = getFlightKey(airline, flight, timestamp);
        uint256 amount = amountInsurance[passenger][flightkey];
        return (amount == 0);
    }

    function isAirline(address airline) public view returns (bool) {
        return recordedAirline[airline];
    }

    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */

    function setOperatingStatus(bool mode) external requireIsContractOwner {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */

    function authorizeCaller(address contractAddress)
        external
        requireIsContractOwner
    {
        approved[contractAddress] = 1;
    }

    function unauthorizeCaller(address contractAddress)
        external
        requireIsContractOwner
    {
        delete approved[contractAddress];
    }

    function registerAirline(address airline)
        external
        requireIsOperational
        requireIsAuthorized
        requireIsNotRegistered(airline)
        returns (bool success)
    {
        require(airline != address(0));
        recordedAirline[airline] = true;
        airlines.push(airline);
        return recordedAirline[airline];
    }

    function allAirlines() external view returns (address[]) {
        return airlines;
    }

    function passengerMoney(address passenger)
        external
        view
        returns (uint256)
    {
        return balance[passenger];
    }

    function withdrawFunds(uint256 amount, address passenger)
        external
        requireIsOperational
        requireIsAuthorized
        returns (uint256)
    {
        balance[passenger] = balance[passenger] - amount;
        passenger.transfer(amount);

        return balance[passenger];
    }

    /**
     * @dev airline can deposit funds in any amount
     */
    function creditAirline(address airline, uint256 amount)
        external
        requireIsOperational
        requireIsAuthorized
        requireIsAirlineRegistered(airline)
    {
        airlineAssets[airline] += amount;
    }

    /**
     * @dev to see how much fund an airline has
     */
    function airlineBudget(address airline)
        external
        view
        requireIsOperational
        requireIsAuthorized
        requireIsAirlineRegistered(airline)
        returns (uint256 funds)
    {
        return (airlineAssets[airline]);
    }

    /**
     * @dev Buy insurance for a flight
     *
     */

    function buy(
        address airline,
        string flight,
        uint256 _timestamp,
        address passenger,
        uint256 amount
    )
        external
        requireIsOperational
        requireIsAuthorized
        requireIsAirlineRegistered(airline)
    {
        bytes32 flightkey = getFlightKey(airline, flight, _timestamp);

        // PassengerInsurance memory pinsurance = PassengerInsurance({passenger:_passenger,insuranceamount:amount,payout:0});
        //airlineInsurance[flightkey].push(pinsurance);

        airlineinsurees[flightkey].push(passenger);
        amountInsurance[passenger][flightkey] = amount;
        payoutInsurance[flightkey][passenger] = 0;
    }

    uint256 public total = 0;

    /**
    /**
     *  @dev Credits payouts to insurees
     */
    function creditInsurees(
        address airline,
        string flight,
        uint256 timestamp,
        uint256 factor_numerator,
        uint256 factor_denominator
    ) external requireIsOperational requireIsAuthorized {
        //get all the insurees
        bytes32 flightkey = getFlightKey(airline, flight, timestamp);

        address[] storage insurees = airlineinsurees[flightkey];

        for (uint8 i = 0; i < insurees.length; i++) {
            address passenger = insurees[i];
            uint256 payout;
            uint256 amount = amountInsurance[passenger][flightkey];
            uint256 paid = payoutInsurance[flightkey][passenger];
            if (paid == 0) {
                // bool success = _appcontract.call(bytes4(keccak256("calculatePayout(uint256)")), amount);
                payout = amount.mul(factor_numerator).div(factor_denominator);
                payoutInsurance[flightkey][passenger] = payout;
                balance[passenger] += payout;
            }
        }
    }

    function getbalance(address passenger)
        external
        view
        requireIsOperational
        requireIsAuthorized
        returns (uint256)
    {
        return balance[passenger];
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay(
        address airline,
        string flight,
        uint256 ts,
        address passenger,
        uint256 payout
    ) external requireIsOperational requireIsAuthorized {
        bytes32 flightkey = getFlightKey(airline, flight, ts);
        payoutInsurance[flightkey][passenger] = payout;
        balance[passenger] += payout;

        //uint256 prev = balance[customerAddress];
        //balance[customerAddress] = 0;
        //passenger.transfer(payout);
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */

    function fund() public payable {}

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
     * @dev Fallback function for funding smart contract.
     *
     */
    function() external payable {
        fund();
    }
}
