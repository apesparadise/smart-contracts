//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Supply cap of 15,000,000
contract Tree is ERC20Capped(15_000_000 * 1e18), Ownable {

    address public upgradeAddress;
    address public forestAddress;

    constructor() ERC20("TREE", "TREE") {}

    function setUpgradeAddress(address _upgradeAddress) external onlyOwner {
        upgradeAddress = _upgradeAddress;
    }

    function setForestAddress(address _forestAddress) external onlyOwner {
        forestAddress = _forestAddress;
    }

    // external

    function mint(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0));
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        require(upgradeAddress != address(0) && forestAddress != address(0), "missing initial requirements");
        require(_msgSender() == upgradeAddress || _msgSender() == forestAddress, "msgsender does not have permission");
        _burn(_from, _amount);
    }

    function transferForUpgradesFees(address _from, uint256 _amount) external {
        require(upgradeAddress != address(0), "missing initial requirements");
        require(_msgSender() == upgradeAddress, "only the upgrade contract can call transferForUpgradesFees");
        _transfer(_from, upgradeAddress, _amount);
    }
}
