// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libraries/math/SafeMath.sol";
import "./interfaces/IX2Market.sol";
import "./interfaces/IX2Token.sol";
import "./interfaces/IX2RewardDistributor.sol";
import "./libraries/token/IERC20.sol";

contract X2Reader {
    using SafeMath for uint256;
    uint256 constant PRECISION = 1e20;

    function getMarketInfo(address _market) public view returns (uint256[] memory) {
        address bullToken = IX2Market(_market).bullToken();
        address bearToken = IX2Market(_market).bearToken();

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = IX2Market(_market).latestPrice();
        amounts[1] = IERC20(bullToken).totalSupply();
        amounts[2] = IERC20(bearToken).totalSupply();

        return amounts;
    }

    function getRewards(address _token, address _account) public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](6);
        address distributor = IX2Token(_token).distributor();
        if (distributor == address(0)) {
            return amounts;
        }

        amounts[0] = IX2RewardDistributor(distributor).tokensPerInterval(_token);

        uint256 rewards = IX2Token(_token).getReward(_account);
        uint256 pendingRewards = IX2RewardDistributor(distributor).getDistributionAmount(_token);
        uint256 balance = IX2Token(_token)._balanceOf(_account);
        uint256 cumulativeRewardPerToken = IX2Token(_token).cumulativeRewardPerToken();

        uint256 supply = IX2Token(_token)._totalSupply();
        if (supply > 0) {
            amounts[1] = rewards.add(pendingRewards.mul(balance).div(supply));
        }
        amounts[2] = IERC20(_token).totalSupply();

        amounts[3] = balance;
        amounts[4] = cumulativeRewardPerToken;
        amounts[5] = PRECISION;

        return amounts;
    }

    function getBalanceInfo(address _market, address _account) public view returns (uint256[] memory) {
        address bullToken = IX2Market(_market).bullToken();
        address bearToken = IX2Market(_market).bearToken();
        (uint256 bullFunding, uint256 bearFunding) = IX2Market(_market).getFunding();

        uint256[] memory amounts = new uint256[](9);

        amounts[0] = _account.balance;
        amounts[1] = IERC20(bullToken).balanceOf(_account);
        amounts[2] = IERC20(bearToken).balanceOf(_account);
        amounts[3] = IX2Token(bullToken).lastBoughtAt(_account);
        amounts[4] = IX2Token(bearToken).lastBoughtAt(_account);
        amounts[5] = IX2Token(bullToken).getPendingProfit(_account);
        amounts[6] = IX2Token(bearToken).getPendingProfit(_account);
        amounts[7] = IX2Token(bullToken).costOf(_account);
        amounts[8] = IX2Token(bearToken).costOf(_account);
        amounts[9] = bullFunding;
        amounts[10] = bearFunding;

        return amounts;
    }
}
