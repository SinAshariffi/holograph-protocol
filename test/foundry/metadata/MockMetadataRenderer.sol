// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IMetadataRenderer} from "../../../src/drops/interface/IMetadataRenderer.sol";

contract MockMetadataRenderer is IMetadataRenderer {
  function tokenURI(uint256) external view returns (string memory) {
    return "DEMO";
  }

  function contractURI() external view returns (string memory) {
    return "DEMO";
  }

  function initializeWithData(bytes memory initData) external {
    require(initData.length == 0, "not zero");
  }
}
