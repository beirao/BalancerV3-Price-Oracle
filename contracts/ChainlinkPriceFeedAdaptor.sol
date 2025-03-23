// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IChainlinkAggregatorV2V3} from "./interfaces/IChainlinkAggregatorV2V3.sol";

abstract contract ChainlinkPriceFeedAdaptor is IChainlinkAggregatorV2V3 {}
