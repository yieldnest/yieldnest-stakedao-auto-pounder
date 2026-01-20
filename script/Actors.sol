/* solhint-disable one-contract-per-file, const-name-snakecase */
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IActors {
    function ADMIN() external view returns (address);
    /// @dev multisig
    function PAUSER() external view returns (address);
    /// @dev multisig
    function UNPAUSER() external view returns (address);
}

contract MainnetActors is IActors {
    address public constant YnSecurityCouncil = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;
    address public constant YnDev = 0xa08F39d30dc865CC11a49b6e5cBd27630D6141C3;

    address public constant ADMIN = YnSecurityCouncil;
    address public constant PAUSER = YnDev;
    address public constant UNPAUSER = YnSecurityCouncil;
}
