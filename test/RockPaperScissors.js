const { BN, expectRevert, expectEvent } = require('openzeppelin-test-helpers');

const RockPaperScissors = artifacts.require('./RockPaperScissors.sol');

contract('RockPaperScissors', accounts => {
    let game;
    beforeEach(async () => {
        game = await RockPaperScissors.new(false, { from: accounts[0] });
    });

    describe('game', function () {
        it('should pass sunny flow', async () => {
            const secret = 'super secure pwd';
            const { logs: startLogs } = await game.start(10, { value: 1, from: accounts[0] });
            expectEvent.inLogs(startLogs, 'LogStarted');

            const { id } = startLogs[0].args;
            const { logs: joinLogs } = await game.join(id, { value: 1, from: accounts[1] });
            expectEvent.inLogs(joinLogs, 'LogJoined');

            const hashedMove = await game.generateMoveHash(id, 1, web3.utils.fromAscii(secret));
            const { logs: move1Logs } = await game.move1(id, hashedMove, { from: accounts[0] });
            expectEvent.inLogs(move1Logs, 'LogFirstMoved');

            const { logs: move2Logs } = await game.move2(id, 2, { from: accounts[1] });
            expectEvent.inLogs(move2Logs, 'LogSecondMoved');

            const { logs: revealLogs } = await game.reveal(id, 1, web3.utils.fromAscii(secret), { from: accounts[0] });
            expectEvent.inLogs(revealLogs, 'LogRevealed');
            expectEvent.inLogs(revealLogs, 'LogOutcome');

            const result1 = await game.balanceOf(accounts[0]);
            result1.should.be.bignumber.equal('0');

            const result2 = await game.balanceOf(accounts[1]);
            result2.should.be.bignumber.equal('2');
        });
    });
});