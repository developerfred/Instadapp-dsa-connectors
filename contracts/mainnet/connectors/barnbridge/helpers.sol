pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { Basic } from "../../common/basic.sol";

import {
    AaveV2LendingPoolProviderInterface, 
    AaveV2DataProviderInterface,
    AaveV2Interface,
    ComptrollerInterface,
    CTokenInterface,
    CompoundMappingInterface,
    CreamMappingInterface
} from "./interfaces.sol";

import { TokenInterface } from "../../common/interfaces.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Helpers is Basic {
    using SafeERC20 for IERC20;

    enum Protocol {
        AaveV2,
        Compound,
        Cream
    }

    address payable constant feeCollector = 0xb1DC62EC38E6E3857a887210C38418E4A17Da5B2;

    /**
     * @dev Return InstaDApp Mapping Address
     */
    address constant internal getMappingAddr = 0xA8F9D4aA7319C54C04404765117ddBf9448E2082; // CompoundMapping Address

    /**
     * @dev Return Compound Comptroller Address
     */
    address constant internal getComptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B; // Compound Comptroller Address

    /**
     * @dev Return Cream Comptroller Address
     * todo add CREAM Mapping Address 
     */
    address constant internal getCreamMappingAddr = (address(0)); // CREAMMapping Address
    /**
     * @dev Return Cream Comptroller Address
     */
    address constant internal getCreamComptrollerAddress = 0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258; // CREAM Comptroller Address

    /**
     * @dev get Aave Lending Pool Provider
    */
    AaveV2LendingPoolProviderInterface constant internal getAaveV2Provider =
                    AaveV2LendingPoolProviderInterface(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);

    /**
     * @dev get Aave Protocol Data Provider
    */
    AaveV2DataProviderInterface constant internal getAaveV2DataProvider =
                    AaveV2DataProviderInterface(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);

    /**
     * @dev get Referral Code
    */
    uint16 constant internal getReferralCode =  13;

}

contract protocolHelpers is Helpers {
    using SafeERC20 for IERC20;

    function getWithdrawBalance(AaveV1Interface aave, address token) internal view returns (uint bal) {
        (bal, , , , , , , , , ) = aave.getUserReserveData(token, address(this));
    }

    function getPaybackBalance(AaveV1Interface aave, address token) internal view returns (uint bal, uint fee) {
        (, bal, , , , , fee, , , ) = aave.getUserReserveData(token, address(this));
    }

    function getTotalBorrowBalance(AaveV1Interface aave, address token) internal view returns (uint amt) {
        (, uint bal, , , , , uint fee, , , ) = aave.getUserReserveData(token, address(this));
        amt = add(bal, fee);
    }

    function getWithdrawBalanceV2(AaveV2DataProviderInterface aaveData, address token) internal view returns (uint bal) {
        (bal, , , , , , , , ) = aaveData.getUserReserveData(token, address(this));
    }

    function getPaybackBalanceV2(AaveV2DataProviderInterface aaveData, address token, uint rateMode) internal view returns (uint bal) {
        if (rateMode == 1) {
            (, bal, , , , , , , ) = aaveData.getUserReserveData(token, address(this));
        } else {
            (, , bal, , , , , , ) = aaveData.getUserReserveData(token, address(this));
        }
    }

    function getIsColl(AaveV1Interface aave, address token) internal view returns (bool isCol) {
        (, , , , , , , , , isCol) = aave.getUserReserveData(token, address(this));
    }

    function getIsCollV2(AaveV2DataProviderInterface aaveData, address token) internal view returns (bool isCol) {
        (, , , , , , , , isCol) = aaveData.getUserReserveData(token, address(this));
    }

    function getMaxBorrow(Protocol target, address token, CTokenInterface ctoken, uint rateMode) internal returns (uint amt) {
        AaveV1Interface aaveV1 = AaveV1Interface(getAaveProvider.getLendingPool());
        AaveV2DataProviderInterface aaveData = getAaveV2DataProvider;

        if (target == Protocol.Aave) {
            (uint _amt, uint _fee) = getPaybackBalance(aaveV1, token);
            amt = _amt + _fee;
        } else if (target == Protocol.AaveV2) {
            amt = getPaybackBalanceV2(aaveData, token, rateMode);
        } else if (target == Protocol.Compound) {
            amt = ctoken.borrowBalanceCurrent(address(this));
        }
    }

    function transferFees(address token, uint feeAmt) internal {
        if (feeAmt > 0) {
            if (token == ethAddr) {
                feeCollector.transfer(feeAmt);
            } else {
                IERC20(token).safeTransfer(feeCollector, feeAmt);
            }
        }
    }

    function calculateFee(uint256 amount, uint256 fee, bool toAdd) internal pure returns(uint feeAmount, uint _amount){
        feeAmount = wmul(amount, fee);
        _amount = toAdd ? add(amount, feeAmount) : sub(amount, feeAmount);
    }

    function getTokenInterfaces(uint length, address[] memory tokens) internal pure returns (TokenInterface[] memory) {
        TokenInterface[] memory _tokens = new TokenInterface[](length);
        for (uint i = 0; i < length; i++) {
            if (tokens[i] ==  ethAddr) {
                _tokens[i] = TokenInterface(wethAddr);
            } else {
                _tokens[i] = TokenInterface(tokens[i]);
            }
        }
        return _tokens;
    }

    function getCtokenInterfaces(uint length, string[] memory tokenIds) internal view returns (CTokenInterface[] memory) {
        CTokenInterface[] memory _ctokens = new CTokenInterface[](length);
        for (uint i = 0; i < length; i++) {
            (address token, address cToken) = CompoundMappingInterface(getMappingAddr).getMapping(tokenIds[i]);
            require(token != address(0) && cToken != address(0), "invalid token/ctoken address");
            _ctokens[i] = CTokenInterface(cToken);
        }
        return _ctokens;
    }

    function enterMarket(address cToken) internal {
        address[] memory markets = troller.getAssetsIn(address(this));
        bool isEntered = false;
        for (uint i = 0; i < markets.length; i++) {
            if (markets[i] == cToken) {
                isEntered = true;
            }
        }
        if (!isEntered) {
            address[] memory toEnter = new address[](1);
            toEnter[0] = cToken;
            troller.enterMarkets(toEnter);
        }
    }
}