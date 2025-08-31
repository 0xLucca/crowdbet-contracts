// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FtsoV2Consumer} from "./FtsoV2Consumer.sol";
import {IBinaryPredictionMarket} from "./interfaces/IBinaryPredictionMarket.sol";

contract FlareOracleResolver is FtsoV2Consumer {

    enum ComparisonType {
        LessThan,
        LessThanOrEqual,
        GreaterThan,
        GreaterThanOrEqual
    }

    bytes21 public oracleTokenId;
    address public marketAddress;
    uint256 public threshold;
    ComparisonType public comparisonType;

    constructor(bytes21 _oracleTokenId, address _marketAddress, uint256 _threshold, ComparisonType _comparisonType) {
        oracleTokenId = _oracleTokenId;
        marketAddress = _marketAddress;
        threshold = _threshold;
        comparisonType = _comparisonType;
    }

    function resolve() external {
        (uint256 price, uint64 timestamp) = getTokenUsdPriceWei(oracleTokenId);
        bool yesWon;
        if (comparisonType == ComparisonType.LessThan) {
            yesWon = price < threshold;
        } else if (comparisonType == ComparisonType.LessThanOrEqual) {
            yesWon = price <= threshold;
        } else if (comparisonType == ComparisonType.GreaterThan) {
            yesWon = price > threshold;
        } else if (comparisonType == ComparisonType.GreaterThanOrEqual) {
            yesWon = price >= threshold;
        } else {
            revert("Invalid comparison type");
        }
        IBinaryPredictionMarket(marketAddress).resolve(yesWon);
    }
}