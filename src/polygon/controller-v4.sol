// https://github.com/iearn-finance/jars/blob/master/contracts/controllers/StrategyControllerV1.sol

pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "../interfaces/controller.sol";

import "../lib/erc20.sol";
import "../lib/safe-math.sol";

import "../interfaces/jar.sol";
import "../interfaces/jar-converter.sol";
import "../interfaces/strategy.sol";
import "../interfaces/converter.sol";

contract ControllerV4 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant burn = 0x000000000000000000000000000000000000dEaD;

    address public governance;
    address public strategist;
    address public devfund;
    address public treasury;
    address public timelock;

    // Convenience fee 0.1%
    uint256 public convenienceFee = 100;
    uint256 public constant convenienceFeeMax = 100000;

    mapping(address => address) public jars;
    mapping(address => address) public strategies;
    mapping(address => mapping(address => address)) public converters;
    mapping(address => mapping(address => bool)) public approvedStrategies;
    mapping(address => bool) public approvedJarConverters;

    uint256 public split = 500;
    uint256 public constant max = 10000;

    constructor(
        address _governance,
        address _strategist,
        address _timelock,
        address _devfund,
        address _treasury
    ) public {
        governance = _governance;
        strategist = _strategist;
        timelock = _timelock;
        devfund = _devfund;
        treasury = _treasury;
    }

    function setDevFund(address _devfund) public {
        require(msg.sender == governance, "!governance");
        devfund = _devfund;
    }

    function setTreasury(address _treasury) public {
        require(msg.sender == governance, "!governance");
        treasury = _treasury;
    }

    function setStrategist(address _strategist) public {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    function setSplit(uint256 _split) public {
        require(msg.sender == governance, "!governance");
        require(_split <= max, "numerator cannot be greater than denominator");
        split = _split;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setTimelock(address _timelock) public {
        require(msg.sender == timelock, "!timelock");
        timelock = _timelock;
    }

    function setJar(address _token, address _jar) public {
        require(
            msg.sender == strategist || msg.sender == governance,
            "!strategist"
        );
        require(jars[_token] == address(0), "jar");
        jars[_token] = _jar;
    }

    function approveJarConverter(address _converter) public {
        require(msg.sender == governance, "!governance");
        approvedJarConverters[_converter] = true;
    }

    function revokeJarConverter(address _converter) public {
        require(msg.sender == governance, "!governance");
        approvedJarConverters[_converter] = false;
    }

    function approveStrategy(address _token, address _strategy) public {
        require(msg.sender == timelock, "!timelock");
        approvedStrategies[_token][_strategy] = true;
    }

    function revokeStrategy(address _token, address _strategy) public {
        require(msg.sender == governance, "!governance");
        require(strategies[_token] != _strategy, "cannot revoke active strategy");
        approvedStrategies[_token][_strategy] = false;
    }

    function setConvenienceFee(uint256 _convenienceFee) external {
        require(msg.sender == timelock, "!timelock");
        convenienceFee = _convenienceFee;
    }

    function setStrategy(address _token, address _strategy) public {
        require(
            msg.sender == strategist || msg.sender == governance,
            "!strategist"
        );
        require(approvedStrategies[_token][_strategy] == true, "!approved");

        address _current = strategies[_token];
        if (_current != address(0)) {
            IStrategy(_current).withdrawAll();
        }
        strategies[_token] = _strategy;
    }

    function earn(address _token, uint256 _amount) public {
        address _strategy = strategies[_token];
        address _want = IStrategy(_strategy).want();
        if (_want != _token) {
            address converter = converters[_token][_want];
            IERC20(_token).safeTransfer(converter, _amount);
            _amount = Converter(converter).convert(_strategy);
            IERC20(_want).safeTransfer(_strategy, _amount);
        } else {
            IERC20(_token).safeTransfer(_strategy, _amount);
        }
        IStrategy(_strategy).deposit();
    }

    function balanceOf(address _token) external view returns (uint256) {
        return IStrategy(strategies[_token]).balanceOf();
    }

    function withdrawAll(address _token) public {
        require(
            msg.sender == strategist || msg.sender == governance,
            "!strategist"
        );
        IStrategy(strategies[_token]).withdrawAll();
    }

    function inCaseTokensGetStuck(address _token, uint256 _amount) public {
        require(
            msg.sender == strategist || msg.sender == governance,
            "!governance"
        );
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function inCaseStrategyTokenGetStuck(address _strategy, address _token)
        public
    {
        require(
            msg.sender == strategist || msg.sender == governance,
            "!governance"
        );
        IStrategy(_strategy).withdraw(_token);
    }

    function withdraw(address _token, uint256 _amount) public {
        require(msg.sender == jars[_token], "!jar");
        IStrategy(strategies[_token]).withdraw(_amount);
    }

    // Function to swap between jars
    function swapExactJarForJar(
        address _fromJar, // From which Jar
        address _toJar, // To which Jar
        uint256 _fromJarAmount, // How much jar tokens to swap
        uint256 _toJarMinAmount, // How much jar tokens you'd like at a minimum
        address payable[] calldata _targets,
        bytes[] calldata _data
    ) external returns (uint256) {
        require(_targets.length == _data.length, "!length");

        // Only return last response
        for (uint256 i = 0; i < _targets.length; i++) {
            require(_targets[i] != address(0), "!converter");
            require(approvedJarConverters[_targets[i]], "!converter");
        }

        address _fromJarToken = IJar(_fromJar).token();
        address _toJarToken = IJar(_toJar).token();

        // Get pTokens from msg.sender
        IERC20(_fromJar).safeTransferFrom(
            msg.sender,
            address(this),
            _fromJarAmount
        );

        // Calculate how much underlying
        // is the amount of pTokens worth
        uint256 _fromJarUnderlyingAmount = _fromJarAmount
            .mul(IJar(_fromJar).getRatio())
            .div(10**uint256(IJar(_fromJar).decimals()));

        // Call 'withdrawForSwap' on Jar's current strategy if Jar
        // doesn't have enough initial capital.
        // This has moves the funds from the strategy to the Jar's
        // 'earnable' amount. Enabling 'free' withdrawals
        uint256 _fromJarAvailUnderlying = IERC20(_fromJarToken).balanceOf(
            _fromJar
        );
        if (_fromJarAvailUnderlying < _fromJarUnderlyingAmount) {
            IStrategy(strategies[_fromJarToken]).withdrawForSwap(
                _fromJarUnderlyingAmount.sub(_fromJarAvailUnderlying)
            );
        }

        // Withdraw from Jar
        // Note: this is free since its still within the "earnable" amount
        //       as we transferred the access
        IERC20(_fromJar).safeApprove(_fromJar, 0);
        IERC20(_fromJar).safeApprove(_fromJar, _fromJarAmount);
        IJar(_fromJar).withdraw(_fromJarAmount);

        // Calculate fee
        uint256 _fromUnderlyingBalance = IERC20(_fromJarToken).balanceOf(
            address(this)
        );
        uint256 _convenienceFee = _fromUnderlyingBalance.mul(convenienceFee).div(
            convenienceFeeMax
        );

        if (_convenienceFee > 1) {
            IERC20(_fromJarToken).safeTransfer(devfund, _convenienceFee.div(2));
            IERC20(_fromJarToken).safeTransfer(treasury, _convenienceFee.div(2));
        }

        // Executes sequence of logic
        for (uint256 i = 0; i < _targets.length; i++) {
            _execute(_targets[i], _data[i]);
        }

        // Deposit into new Jar
        uint256 _toBal = IERC20(_toJarToken).balanceOf(address(this));
        IERC20(_toJarToken).safeApprove(_toJar, 0);
        IERC20(_toJarToken).safeApprove(_toJar, _toBal);
        IJar(_toJar).deposit(_toBal);

        // Send Jar Tokens to user
        uint256 _toJarBal = IJar(_toJar).balanceOf(address(this));
        if (_toJarBal < _toJarMinAmount) {
            revert("!min-jar-amount");
        }

        IJar(_toJar).transfer(msg.sender, _toJarBal);

        return _toJarBal;
    }

    function _execute(address _target, bytes memory _data)
        internal
        returns (bytes memory response)
    {
        require(_target != address(0), "!target");

        // call contract in current context
        assembly {
            let succeeded := delegatecall(
                sub(gas(), 5000),
                _target,
                add(_data, 0x20),
                mload(_data),
                0,
                0
            )
            let size := returndatasize()

            response := mload(0x40)
            mstore(
                0x40,
                add(response, and(add(add(size, 0x20), 0x1f), not(0x1f)))
            )
            mstore(response, size)
            returndatacopy(add(response, 0x20), 0, size)

            switch iszero(succeeded)
                case 1 {
                    // throw if delegatecall failed
                    revert(add(response, 0x20), size)
                }
        }
    }
}
