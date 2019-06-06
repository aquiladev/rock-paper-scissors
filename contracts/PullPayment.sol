pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract PullPayment {
    using SafeMath for uint256;

    event LogWithdrawn(address indexed who, uint amount);

    mapping(address => uint256) private payments;

    function transferTo(address to, uint256 amount) internal {
        payments[to] = payments[to].add(amount);
    }

    function transferFrom(address from, uint256 amount) internal {
        payments[from] = payments[from].sub(amount);
    }

    function balanceOf(address account) public view returns(uint256) {
        return payments[account];
    }

    function withdraw() public {
        uint256 payment = payments[msg.sender];
        require(payment != 0, "Balance is empty");

        assert(payment <= address(this).balance);
        payments[msg.sender] = 0;

        emit LogWithdrawn(msg.sender, payment);
        msg.sender.transfer(payment);
    }
}