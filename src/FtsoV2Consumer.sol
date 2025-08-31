// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TestFtsoV2Interface} from "@flare-periphery//coston2/TestFtsoV2Interface.sol";
import {ContractRegistry} from "@flare-periphery//coston2/ContractRegistry.sol";
import {IFeeCalculator} from "@flare-periphery//coston2/IFeeCalculator.sol";

contract FtsoV2Consumer {
    function getTokenUsdPrice(bytes21 id) public view returns (uint256, int8, uint64) {
        TestFtsoV2Interface ftsoV2 = ContractRegistry.getTestFtsoV2();
        return ftsoV2.getFeedById(id);
    }
    function getTokenUsdPriceWei(bytes21 id) public view returns (uint256, uint64) {
        TestFtsoV2Interface ftsoV2 = ContractRegistry.getTestFtsoV2();
        return ftsoV2.getFeedByIdInWei(id);
    }
}