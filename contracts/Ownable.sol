pragma solidity ^0.5.2;

contract Ownable {
    address private _owner;

    event LogOwnerChanged(address indexed sender, address indexed newOwner);

    constructor () internal {
        _owner = msg.sender;
        emit LogOwnerChanged(address(0), _owner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(isOwner(), "Only owner can execute");
        _;
    }

    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    function changeOwner(address newOwner) public onlyOwner {
        require(newOwner != address(0), "new owner is the zero address");

        _owner = newOwner;
        emit LogOwnerChanged(_owner, newOwner);
    }
}
