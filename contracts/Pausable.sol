pragma solidity ^0.5.2;

import "./Ownable.sol";

contract Pausable is Ownable {
    event LogPaused(address indexed account);
    event LogResumed(address indexed account);
    event LogKilled(address indexed account);

    bool private _paused;
    bool private _killed;

    modifier whenRunning() {
        require(!_paused, "Paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Running");
        _;
    }

    modifier whenAlive() {
        require(!_killed, "Killed");
        _;
    }

    constructor (bool paused) internal {
        _paused = paused;
    }

    function isPaused() public view returns (bool) {
        return _paused;
    }

    function pause() public onlyOwner whenRunning whenAlive {
        _paused = true;
        emit LogPaused(msg.sender);
    }

    function resume() public onlyOwner whenPaused whenAlive {
        _paused = false;
        emit LogResumed(msg.sender);
    }

    function kill() public onlyOwner whenPaused whenAlive {
        _killed = true;
        emit LogKilled(msg.sender);
    }
}
