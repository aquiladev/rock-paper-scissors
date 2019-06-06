pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract PullPayment {
    using SafeMath for uint256;

    event LogWithdrawn(address indexed who, uint amount);

    mapping(address => uint256) public payments;
    uint256 public totalPayments;

    function transferTo(address to, uint256 amount) internal {
        payments[to] = payments[to].add(amount);
        totalPayments = totalPayments.add(amount);
    }

    function transferFrom(address from, uint256 amount) internal {
        payments[from] = payments[from].sub(amount);
        totalPayments = totalPayments.sub(amount);
    }

    function withdraw() public {
        uint256 payment = payments[msg.sender];
        require(payment != 0, "Balance is empty");

        assert(payment <= address(this).balance);
        totalPayments = totalPayments.sub(payment);
        payments[msg.sender] = 0;

        emit LogWithdrawn(msg.sender, payment);
        msg.sender.transfer(payment);
    }
}