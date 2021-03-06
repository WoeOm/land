pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";
import "@evolutionland/common/contracts/DSAuth.sol";
import "@evolutionland/common/contracts/SettingIds.sol";
import "./interfaces/ILandBase.sol";
import "./interfaces/IMysteriousTreasure.sol";

contract MysteriousTreasure is DSAuth, SettingIds, IMysteriousTreasure {
    using SafeMath for *;
    
    bool private singletonLock = false;

    ISettingsRegistry public registry;

    // the key of resourcePool are 0,1,2,3,4
    // respectively refer to gold,wood,water,fire,soil
    mapping (uint256 => uint256) public resourcePool;

    // number of box left
    uint public totalBoxNotOpened;

    // event unbox
    event Unbox(uint indexed tokenId, uint goldRate, uint woodRate, uint waterRate, uint fireRate, uint soilRate);

    /*
  *  Modifiers
  */
    modifier singletonLockCall() {
        require(!singletonLock, "Only can call once");
        _;
        singletonLock = true;
    }

    // this need to be created in ClockAuction cotnract
    constructor() public {

      // initializeContract
    }

    function initializeContract(ISettingsRegistry _registry, uint256[5] _resources) public singletonLockCall {
        owner = msg.sender;

        registry = _registry;

        totalBoxNotOpened = 176;
        for(uint i = 0; i < 5; i++) {
            _setResourcePool(i, _resources[i]);
        }
    }

    //TODO: consider authority again
    // this is invoked in auction.claimLandAsset
    function unbox(uint256 _tokenId)
    public
    auth
    returns (uint, uint, uint, uint, uint) {
        ILandBase landBase = ILandBase(registry.addressOf(SettingIds.CONTRACT_LAND_BASE));
        if(! landBase.isHasBox(_tokenId) ) {
            return (0,0,0,0,0);
        }

        // after unboxing, set hasBox(tokenId) to false to restrict unboxing
        // set hasBox to false before unboxing operations for safety reason
        landBase.setHasBox(_tokenId, false);

        uint16[5] memory resourcesReward;
        (resourcesReward[0], resourcesReward[1],
        resourcesReward[2], resourcesReward[3], resourcesReward[4]) = _computeAndExtractRewardFromPool();

        address resouceToken = registry.addressOf(SettingIds.CONTRACT_GOLD_ERC20_TOKEN);
        landBase.setResourceRate(_tokenId, resouceToken, landBase.getResourceRate(_tokenId, resouceToken) + resourcesReward[0]);

        resouceToken = registry.addressOf(SettingIds.CONTRACT_WOOD_ERC20_TOKEN);
        landBase.setResourceRate(_tokenId, resouceToken, landBase.getResourceRate(_tokenId, resouceToken) + resourcesReward[1]);

        resouceToken = registry.addressOf(SettingIds.CONTRACT_WATER_ERC20_TOKEN);
        landBase.setResourceRate(_tokenId, resouceToken, landBase.getResourceRate(_tokenId, resouceToken) + resourcesReward[2]);

        resouceToken = registry.addressOf(SettingIds.CONTRACT_FIRE_ERC20_TOKEN);
        landBase.setResourceRate(_tokenId, resouceToken, landBase.getResourceRate(_tokenId, resouceToken) + resourcesReward[3]);

        resouceToken = registry.addressOf(SettingIds.CONTRACT_SOIL_ERC20_TOKEN);
        landBase.setResourceRate(_tokenId, resouceToken, landBase.getResourceRate(_tokenId, resouceToken) + resourcesReward[4]);

        // only record increment of resources
        emit Unbox(_tokenId, resourcesReward[0], resourcesReward[1], resourcesReward[2], resourcesReward[3], resourcesReward[4]);

        return (resourcesReward[0], resourcesReward[1], resourcesReward[2], resourcesReward[3], resourcesReward[4]);
    }

    // rewards ranges from [0, 2 * average_of_resourcePool_left]
    // if early players get high resourceReward, then the later ones will get lower.
    // in other words, if early players get low resourceReward, the later ones get higher.
    // think about snatching wechat's virtual red envelopes in groups.
    function _computeAndExtractRewardFromPool() internal returns(uint16,uint16,uint16,uint16,uint16) {
        if ( totalBoxNotOpened == 0 ) {
            return (0,0,0,0,0);
        }

        uint16[5] memory resourceRewards;

        // from fomo3d
        // msg.sender is always address(auction),
        // so change msg.sender to tx.origin
        uint256 seed = uint256(keccak256(abi.encodePacked(
                (block.timestamp).add
                (block.difficulty).add
                ((uint256(keccak256(abi.encodePacked(block.coinbase)))) / (now)).add
                (block.gaslimit).add
                ((uint256(keccak256(abi.encodePacked(tx.origin)))) / (now)).add
                (block.number)
            )));

        for(uint i = 0; i < 5; i++) {
            if (totalBoxNotOpened > 1) {
                // recources in resourcePool is set by owner
                // nad totalBoxNotOpened is set by rules
                // there is no need to consider overflow
                // goldReward, woodReward, waterReward, fireReward, soilReward
                // 2 ** 16 - 1
                uint doubleAverage = (2 * resourcePool[i] / totalBoxNotOpened);
                if (doubleAverage > 65535) {
                    doubleAverage = 65535;
                }
                
                uint resourceReward = seed % doubleAverage;

                resourceRewards[i] = uint16(resourceReward);
                
                // update resourcePool
                _setResourcePool(i, resourcePool[i] - resourceRewards[i]);
            }

            if(totalBoxNotOpened == 1) {
                resourceRewards[i] = uint16(resourcePool[i]);
                _setResourcePool(i, resourcePool[i] - uint256(resourceRewards[i]));
            }
        }

        totalBoxNotOpened--;

        return (resourceRewards[0],resourceRewards[1], resourceRewards[2], resourceRewards[3], resourceRewards[4]);

    }


    function _setResourcePool(uint _keyNumber, uint _resources) internal {
        require(_keyNumber >= 0 && _keyNumber < 5);
        resourcePool[_keyNumber] = _resources;
    }

    function setResourcePool(uint _keyNumber, uint _resources) public auth {
        _setResourcePool(_keyNumber, _resources);
    }

    function setTotalBoxNotOpened(uint _totalBox) public auth {
        totalBoxNotOpened = _totalBox;
    }

}
