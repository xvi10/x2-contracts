//SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "../interfaces/IGmxIou.sol";
import "../interfaces/IAmmRouter.sol";

contract GmxMigrator is ReentrancyGuard {
    using SafeMath for uint256;

    uint256 constant PRECISION = 1000000;

    bool public isInitialized;
    bool public isMigrationActive = true;

    uint256 public minAuthorizations;

    address public ammRouter;
    address public xvix;
    address public uni;
    address public xlge;
    address public weth;
    address public xvixGmxIou;
    address public uniGmxIou;
    address public xlgeGmxIou;

    uint256 public gmxPrice;
    uint256 public xvixPrice;
    uint256 public uniPrice;
    uint256 public xlgePrice;

    uint256 public actionsNonce;
    address public admin;

    address[] public signers;
    mapping (address => bool) public isSigner;
    mapping (bytes32 => bool) public pendingActions;
    mapping (address => mapping (bytes32 => bool)) public signedActions;

    event SignalApprove(address token, address spender, uint256 amount, bytes32 action, uint256 nonce);

    event SignalPendingAction(bytes32 action, uint256 nonce);
    event SignAction(bytes32 action, uint256 nonce);
    event ClearAction(bytes32 action, uint256 nonce);

    constructor(uint256 _minAuthorizations, address[] memory _signers) public {
        admin = msg.sender;
        minAuthorizations = _minAuthorizations;
        signers = _signers;
        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            isSigner[signer] = true;
        }
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "GmxMigrator: forbidden");
        _;
    }

    modifier onlySigner() {
        require(isSigner[msg.sender], "GmxMigrator: forbidden");
        _;
    }

    function initialize(
        address[] memory _addresses,
        uint256 _xvixPrice,
        uint256 _uniPrice,
        uint256 _xlgePrice,
        uint256 _gmxPrice
    ) public onlyAdmin {
        require(!isInitialized, "GmxMigrator: already initialized");
        isInitialized = true;

        ammRouter = _addresses[0];
        xvix = _addresses[1];
        uni = _addresses[2];
        xlge = _addresses[3];
        weth = _addresses[4];

        xvixGmxIou = _addresses[5];
        uniGmxIou = _addresses[6];
        xlgeGmxIou = _addresses[7];

        xvixPrice = _xvixPrice;
        uniPrice = _uniPrice;
        xlgePrice = _xlgePrice;
        gmxPrice = _gmxPrice;
    }

    function endMigration() public onlyAdmin {
        isMigrationActive = false;
    }

    function migrate(
        address _token,
        uint256 _tokenAmount
    ) public nonReentrant {
        require(isMigrationActive, "GmxMigrator: migration is no longer active");
        require(_token == xvix || _token == uni || _token == xlge, "GmxMigrator: unsupported token");
        require(_tokenAmount > 0, "GmxMigrator: invalid tokenAmount");

        uint256 tokenPrice = getTokenPrice(_token);
        uint256 mintAmount = _tokenAmount.mul(tokenPrice).div(gmxPrice);
        require(mintAmount > 0, "GmxMigrator: invalid mintAmount");

        IERC20(_token).transferFrom(msg.sender, address(this), _tokenAmount);
        if (_token == uni) {
            IERC20(_token).approve(ammRouter, _tokenAmount);
            IAmmRouter(ammRouter).removeLiquidity(weth, xvix, _tokenAmount, 0, 0, address(this), block.timestamp);
        }

        address iouToken = getIouToken(_token);
        IGmxIou(iouToken).mint(msg.sender, mintAmount);
    }

    function getTokenPrice(address _token) public view returns (uint256) {
        if (_token == xvix) {
            return xvixPrice;
        }
        if (_token == uni) {
            return uniPrice;
        }
        if (_token == xlge) {
            return xlgePrice;
        }
        revert("GmxMigrator: unsupported token");
    }

    function getIouToken(address _token) public view returns (address) {
        if (_token == xvix) {
            return xvixGmxIou;
        }
        if (_token == uni) {
            return uniGmxIou;
        }
        if (_token == xlge) {
            return xlgeGmxIou;
        }
        revert("GmxMigrator: unsupported token");
    }

    function signalApprove(address _token, address _spender, uint256 _amount) external onlyAdmin {
        actionsNonce++;
        uint256 nonce = actionsNonce;
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount, nonce));
        _setPendingAction(action, nonce);
        emit SignalApprove(_token, _spender, _amount, action, nonce);
    }

    function signApprove(address _token, address _spender, uint256 _amount, uint256 _nonce) external onlySigner {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount, _nonce));
        _validateAction(action);
        require(!signedActions[msg.sender][action], "GmxMigrator: already signed");
        signedActions[msg.sender][action] = true;
        emit SignAction(action, _nonce);
    }

    function approve(address _token, address _spender, uint256 _amount, uint256 _nonce) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount, _nonce));
        _validateAction(action);
        _validateAuthorization(action);

        IERC20(_token).approve(_spender, _amount);
        _clearAction(action, _nonce);
    }

    function _setPendingAction(bytes32 _action, uint256 _nonce) private {
        pendingActions[_action] = true;
        emit SignalPendingAction(_action, _nonce);
    }

    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action], "GmxMigrator: action not signalled");
    }

    function _validateAuthorization(bytes32 _action) private view {
        uint256 count = 0;
        for (uint256 i = 0; i < signers.length; i++) {
            address signer = signers[i];
            if (signedActions[signer][_action]) {
                count++;
            }
        }

        if (count == 0) {
            revert("GmxMigrator: action not authorized");
        }
        require(count >= minAuthorizations, "GmxMigrator: insufficient authorization");
    }

    function _clearAction(bytes32 _action, uint256 _nonce) private {
        require(pendingActions[_action], "GmxMigrator: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action, _nonce);
    }
}
