/*HOLOGRAPH_LICENSE_HEADER*/

/*SOLIDITY_COMPILER_VERSION*/

import "../abstract/Admin.sol";
import "../abstract/Initializable.sol";

import "../enum/ChainIdType.sol";

import "../interface/CrossChainMessageInterface.sol";
import "../interface/HolographOperatorInterface.sol";
import "../interface/InitializableInterface.sol";
import "../interface/HolographInterfacesInterface.sol";
import "../interface/LayerZeroModuleInterface.sol";
import "../interface/LayerZeroOverrides.sol";

/**
 * @title Holograph LayerZero Module
 * @author https://github.com/holographxyz
 * @notice Holograph module for enabling LayerZero cross-chain messaging
 * @dev This contract abstracts all of the LayerZero specific logic into an isolated module
 */
contract LayerZeroModule is Admin, Initializable, CrossChainMessageInterface, LayerZeroModuleInterface {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.Holograph.bridge')) - 1)
   */
  bytes32 constant _bridgeSlot = precomputeslot("eip1967.Holograph.bridge");
  /**
   * @dev bytes32(uint256(keccak256('eip1967.Holograph.interfaces')) - 1)
   */
  bytes32 constant _interfacesSlot = precomputeslot("eip1967.Holograph.interfaces");
  /**
   * @dev bytes32(uint256(keccak256('eip1967.Holograph.lZEndpoint')) - 1)
   */
  bytes32 constant _lZEndpointSlot = precomputeslot("eip1967.Holograph.lZEndpoint");
  /**
   * @dev bytes32(uint256(keccak256('eip1967.Holograph.operator')) - 1)
   */
  bytes32 constant _operatorSlot = precomputeslot("eip1967.Holograph.operator");
  /**
   * @dev bytes32(uint256(keccak256('eip1967.Holograph.msgBaseGas')) - 1)
   */
  bytes32 constant _msgBaseGasSlot = precomputeslot("eip1967.Holograph.msgBaseGas");
  /**
   * @dev bytes32(uint256(keccak256('eip1967.Holograph.msgGasPerByte')) - 1)
   */
  bytes32 constant _msgGasPerByteSlot = precomputeslot("eip1967.Holograph.msgGasPerByte");
  /**
   * @dev bytes32(uint256(keccak256('eip1967.Holograph.jobBaseGas')) - 1)
   */
  bytes32 constant _jobBaseGasSlot = precomputeslot("eip1967.Holograph.jobBaseGas");
  /**
   * @dev bytes32(uint256(keccak256('eip1967.Holograph.jobGasPerByte')) - 1)
   */
  bytes32 constant _jobGasPerByteSlot = precomputeslot("eip1967.Holograph.jobGasPerByte");

  /**
   * @dev Constructor is left empty and init is used instead
   */
  constructor() {}

  /**
   * @notice Used internally to initialize the contract instead of through a constructor
   * @dev This function is called by the deployer/factory when creating a contract
   * @param initPayload abi encoded payload to use for contract initilaization
   */
  function init(bytes memory initPayload) external override returns (bytes4) {
    require(!_isInitialized(), "HOLOGRAPH: already initialized");
    (
      address bridge,
      address interfaces,
      address operator,
      uint256 msgBaseGas,
      uint256 msgGasPerByte,
      uint256 jobBaseGas,
      uint256 jobGasPerByte
    ) = abi.decode(initPayload, (address, address, address, uint256, uint256, uint256, uint256));
    assembly {
      sstore(_adminSlot, origin())
      sstore(_bridgeSlot, bridge)
      sstore(_interfacesSlot, interfaces)
      sstore(_operatorSlot, operator)
      sstore(_msgBaseGasSlot, msgBaseGas)
      sstore(_msgGasPerByteSlot, msgGasPerByte)
      sstore(_jobBaseGasSlot, jobBaseGas)
      sstore(_jobGasPerByteSlot, jobGasPerByte)
    }
    _setInitialized();
    return InitializableInterface.init.selector;
  }

  /**
   * @notice Receive cross-chain message from LayerZero
   * @dev This function only allows calls from the configured LayerZero endpoint address
   */
  function lzReceive(
    uint16, /* _srcChainId*/
    bytes calldata _srcAddress,
    uint64, /* _nonce*/
    bytes calldata _payload
  ) external payable {
    assembly {
      /**
       * @dev check if msg.sender is LayerZero Endpoint
       */
      switch eq(sload(_lZEndpointSlot), caller())
      case 0 {
        /**
         * @dev this is the assembly version of -> revert("HOLOGRAPH: LZ only endpoint");
         */
        mstore(0x80, 0x08c379a000000000000000000000000000000000000000000000000000000000)
        mstore(0xa0, 0x0000002000000000000000000000000000000000000000000000000000000000)
        mstore(0xc0, 0x0000001b484f4c4f47524150483a204c5a206f6e6c7920656e64706f696e7400)
        mstore(0xe0, 0x0000000000000000000000000000000000000000000000000000000000000000)
        revert(0x80, 0xc4)
      }
      let ptr := mload(0x40)
      calldatacopy(add(ptr, 0x0c), _srcAddress.offset, _srcAddress.length)
      /**
       * @dev check if LZ from address is same as address(this)
       */
      switch eq(mload(ptr), address())
      case 0 {
        /**
         * @dev this is the assembly version of -> revert("HOLOGRAPH: unauthorized sender");
         */
        mstore(0x80, 0x08c379a000000000000000000000000000000000000000000000000000000000)
        mstore(0xa0, 0x0000002000000000000000000000000000000000000000000000000000000000)
        mstore(0xc0, 0x0000001e484f4c4f47524150483a20756e617574686f72697a65642073656e64)
        mstore(0xe0, 0x6572000000000000000000000000000000000000000000000000000000000000)
        revert(0x80, 0xc4)
      }
    }
    /**
     * @dev if validation has passed, submit payload to Holograph Operator for converting into an operator job
     */
    _operator().crossChainMessage(_payload);
  }

  /**
   * @dev Need to add an extra function to get LZ gas amount needed for their internal cross-chain message verification
   */
  function send(
    uint256, /* gasLimit*/
    uint256, /* gasPrice*/
    uint32 toChain,
    address msgSender,
    uint256 msgValue,
    bytes calldata crossChainPayload
  ) external payable {
    require(msg.sender == address(_operator()), "HOLOGRAPH: operator only call");
    LayerZeroOverrides lZEndpoint;
    assembly {
      lZEndpoint := sload(_lZEndpointSlot)
    }
    // need to recalculate the gas amounts for LZ to deliver message
    lZEndpoint.send{value: msgValue}(
      uint16(_interfaces().getChainId(ChainIdType.HOLOGRAPH, uint256(toChain), ChainIdType.LAYERZERO)),
      abi.encodePacked(address(this), address(this)),
      crossChainPayload,
      payable(msgSender),
      address(this),
      abi.encodePacked(uint16(1), uint256(_msgBaseGas() + (crossChainPayload.length * _msgGasPerByte())))
    );
  }

  function getMessageFee(
    uint32 toChain,
    uint256 gasLimit,
    uint256 gasPrice,
    bytes calldata crossChainPayload
  )
    external
    view
    returns (
      uint256 hlgFee,
      uint256 msgFee,
      uint256 dstGasPrice
    )
  {
    uint16 lzDestChain = uint16(
      _interfaces().getChainId(ChainIdType.HOLOGRAPH, uint256(toChain), ChainIdType.LAYERZERO)
    );
    LayerZeroOverrides lz;
    assembly {
      lz := sload(_lZEndpointSlot)
    }
    // convert holograph chain id to lz chain id
    (uint128 dstPriceRatio, uint128 dstGasPriceInWei) = _getPricing(lz, lzDestChain);
    if (gasPrice == 0) {
      gasPrice = dstGasPriceInWei;
    }
    bytes memory adapterParams = abi.encodePacked(
      uint16(1),
      uint256(_msgBaseGas() + (crossChainPayload.length * _msgGasPerByte()))
    );
    gasLimit += _jobBaseGas() + (crossChainPayload.length * _jobGasPerByte());
    (uint256 nativeFee, ) = lz.estimateFees(lzDestChain, address(this), crossChainPayload, false, adapterParams);
    return (((gasPrice * (gasLimit + (gasLimit / 10))) * dstPriceRatio) / (10**10), nativeFee, dstGasPriceInWei);
  }

  function getHlgFee(
    uint32 toChain,
    uint256 gasLimit,
    uint256 gasPrice,
    uint256 payloadLength
  ) external view returns (uint256 hlgFee) {
    LayerZeroOverrides lz;
    assembly {
      lz := sload(_lZEndpointSlot)
    }
    uint16 lzDestChain = uint16(
      _interfaces().getChainId(ChainIdType.HOLOGRAPH, uint256(toChain), ChainIdType.LAYERZERO)
    );
    (uint128 dstPriceRatio, uint128 dstGasPriceInWei) = _getPricing(lz, lzDestChain);
    if (gasPrice == 0) {
      gasPrice = dstGasPriceInWei;
    }
    gasLimit += _jobBaseGas() + (payloadLength * _jobGasPerByte());
    return ((gasPrice * (gasLimit + (gasLimit / 10))) * dstPriceRatio) / (10**10);
  }

  function _getPricing(LayerZeroOverrides lz, uint16 lzDestChain)
    private
    view
    returns (uint128 dstPriceRatio, uint128 dstGasPriceInWei)
  {
    return
      LayerZeroOverrides(LayerZeroOverrides(lz.defaultSendLibrary()).getAppConfig(lzDestChain, address(this)).relayer)
        .dstPriceLookup(lzDestChain);
  }

  /**
   * @notice Get the address of the Holograph Bridge module
   * @dev Used for beaming holographable assets cross-chain
   */
  function getBridge() external view returns (address bridge) {
    assembly {
      bridge := sload(_bridgeSlot)
    }
  }

  /**
   * @notice Update the Holograph Bridge module address
   * @param bridge address of the Holograph Bridge smart contract to use
   */
  function setBridge(address bridge) external onlyAdmin {
    assembly {
      sstore(_bridgeSlot, bridge)
    }
  }

  /**
   * @notice Get the address of the Holograph Interfaces module
   * @dev Holograph uses this contract to store data that needs to be accessed by a large portion of the modules
   */
  function getInterfaces() external view returns (address interfaces) {
    assembly {
      interfaces := sload(_interfacesSlot)
    }
  }

  /**
   * @notice Update the Holograph Interfaces module address
   * @param interfaces address of the Holograph Interfaces smart contract to use
   */
  function setInterfaces(address interfaces) external onlyAdmin {
    assembly {
      sstore(_interfacesSlot, interfaces)
    }
  }

  /**
   * @notice Get the address of the approved LayerZero Endpoint
   * @dev All lzReceive function calls allow only requests from this address
   */
  function getLZEndpoint() external view returns (address lZEndpoint) {
    assembly {
      lZEndpoint := sload(_lZEndpointSlot)
    }
  }

  /**
   * @notice Update the approved LayerZero Endpoint address
   * @param lZEndpoint address of the LayerZero Endpoint to use
   */
  function setLZEndpoint(address lZEndpoint) external onlyAdmin {
    assembly {
      sstore(_lZEndpointSlot, lZEndpoint)
    }
  }

  /**
   * @notice Get the address of the Holograph Operator module
   * @dev All cross-chain Holograph Bridge beams are handled by the Holograph Operator module
   */
  function getOperator() external view returns (address operator) {
    assembly {
      operator := sload(_operatorSlot)
    }
  }

  /**
   * @notice Update the Holograph Operator module address
   * @param operator address of the Holograph Operator smart contract to use
   */
  function setOperator(address operator) external onlyAdmin {
    assembly {
      sstore(_operatorSlot, operator)
    }
  }

  /**
   * @dev Internal function used for getting the Holograph Bridge Interface
   */
  function _bridge() private view returns (address bridge) {
    assembly {
      bridge := sload(_bridgeSlot)
    }
  }

  /**
   * @dev Internal function used for getting the Holograph Interfaces Interface
   */
  function _interfaces() private view returns (HolographInterfacesInterface interfaces) {
    assembly {
      interfaces := sload(_interfacesSlot)
    }
  }

  /**
   * @dev Internal function used for getting the Holograph Operator Interface
   */
  function _operator() private view returns (HolographOperatorInterface operator) {
    assembly {
      operator := sload(_operatorSlot)
    }
  }

  /**
   * @dev Purposefully reverts to prevent having any type of ether transfered into the contract
   */
  receive() external payable {
    revert();
  }

  /**
   * @dev Purposefully reverts to prevent any calls to undefined functions
   */
  fallback() external payable {
    revert();
  }

  /**
   * @notice Get the msgBaseGas value
   * @dev Cross-chain messages require at least this much gas
   */
  function getMsgBaseGas() external view returns (uint256 msgBaseGas) {
    assembly {
      msgBaseGas := sload(_msgBaseGasSlot)
    }
  }

  /**
   * @notice Update the msgBaseGas value
   * @param msgBaseGas minimum gas amount that a message requires
   */
  function setMsgBaseGas(uint256 msgBaseGas) external onlyAdmin {
    assembly {
      sstore(_msgBaseGasSlot, msgBaseGas)
    }
  }

  /**
   * @dev Internal function used for getting the msgBaseGas value
   */
  function _msgBaseGas() private view returns (uint256 msgBaseGas) {
    assembly {
      msgBaseGas := sload(_msgBaseGasSlot)
    }
  }

  /**
   * @notice Get the msgGasPerByte value
   * @dev Cross-chain messages require at least this much gas (per payload byte)
   */
  function getMsgGasPerByte() external view returns (uint256 msgGasPerByte) {
    assembly {
      msgGasPerByte := sload(_msgGasPerByteSlot)
    }
  }

  /**
   * @notice Update the msgGasPerByte value
   * @param msgGasPerByte minimum gas amount (per payload byte) that a message requires
   */
  function setMsgGasPerByte(uint256 msgGasPerByte) external onlyAdmin {
    assembly {
      sstore(_msgGasPerByteSlot, msgGasPerByte)
    }
  }

  /**
   * @dev Internal function used for getting the msgGasPerByte value
   */
  function _msgGasPerByte() private view returns (uint256 msgGasPerByte) {
    assembly {
      msgGasPerByte := sload(_msgGasPerByteSlot)
    }
  }

  /**
   * @notice Get the jobBaseGas value
   * @dev Executing jobs require at least this much gas
   */
  function getJobBaseGas() external view returns (uint256 jobBaseGas) {
    assembly {
      jobBaseGas := sload(_jobBaseGasSlot)
    }
  }

  /**
   * @notice Update the jobBaseGas value
   * @param jobBaseGas minimum gas amount that a executeJob requires
   */
  function setJobBaseGas(uint256 jobBaseGas) external onlyAdmin {
    assembly {
      sstore(_jobBaseGasSlot, jobBaseGas)
    }
  }

  /**
   * @dev Internal function used for getting the jobBaseGas value
   */
  function _jobBaseGas() private view returns (uint256 jobBaseGas) {
    assembly {
      jobBaseGas := sload(_jobBaseGasSlot)
    }
  }

  /**
   * @notice Get the jobGasPerByte value
   * @dev Executing jobs require at least this much gas (per payload byte)
   */
  function getJobGasPerByte() external view returns (uint256 jobGasPerByte) {
    assembly {
      jobGasPerByte := sload(_jobGasPerByteSlot)
    }
  }

  /**
   * @notice Update the jobGasPerByte value
   * @param jobGasPerByte minimum gas amount (per payload byte) that a executeJob requires
   */
  function setJobGasPerByte(uint256 jobGasPerByte) external onlyAdmin {
    assembly {
      sstore(_jobGasPerByteSlot, jobGasPerByte)
    }
  }

  /**
   * @dev Internal function used for getting the jobGasPerByte value
   */
  function _jobGasPerByte() private view returns (uint256 jobGasPerByte) {
    assembly {
      jobGasPerByte := sload(_jobGasPerByteSlot)
    }
  }
}
