// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBinaryPredictionMarket {
    function resolve(bool _yesWon) external;
}