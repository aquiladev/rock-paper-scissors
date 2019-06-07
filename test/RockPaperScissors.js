const { BN, expectRevert, expectEvent } = require('openzeppelin-test-helpers');

const RockPaperScissors = artifacts.require('./RockPaperScissors.sol');

contract('RockPaperScissors', accounts => {
    let game;
    beforeEach(async () => {
        game = await RockPaperScissors.new(false, { from: accounts[0] });
    });

    describe('game', () => {
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

    describe('start', () => {
        it('revert when step duration is zero', async () => {
            await expectRevert(game.start(0, { value: 0, from: accounts[0] }), 'Step duration cannot be zero');
        })

        it('start game', async () => {
            const { logs } = await game.start(10, { value: 10, from: accounts[0] });
            expectEvent.inLogs(logs, 'LogStarted', {
                owner: accounts[0],
                id: new BN('0'),
                stake: new BN('10')
            });
        })

        it('start multiple games', async () => {
            const { logs: game1Logs } = await game.start(10, { value: 10, from: accounts[0] });
            expectEvent.inLogs(game1Logs, 'LogStarted', {
                owner: accounts[0],
                id: new BN('0'),
                stake: new BN('10')
            });

            const { logs: game2Logs } = await game.start(10, { value: 10, from: accounts[0] });
            expectEvent.inLogs(game2Logs, 'LogStarted', {
                owner: accounts[0],
                id: new BN('1'),
                stake: new BN('10')
            });
        })

        it('start multiple games by diff accounts', async () => {
            const { logs: game1Logs } = await game.start(10, { value: 10, from: accounts[0] });
            expectEvent.inLogs(game1Logs, 'LogStarted', {
                owner: accounts[0],
                id: new BN('0'),
                stake: new BN('10')
            });

            const { logs: game2Logs } = await game.start(1, { value: 100, from: accounts[1] });
            expectEvent.inLogs(game2Logs, 'LogStarted', {
                owner: accounts[1],
                id: new BN('1'),
                stake: new BN('100')
            });
        })
    });

    describe('decline', () => {
        it('reverts when decline non-existing game', async () => {
            await expectRevert(game.decline(1, { from: accounts[0] }), 'Game not exist');
        })

        it('reverts when decline not game owner', async () => {
            const { logs: startLogs } = await game.start(10, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await expectRevert(game.decline(id, { from: accounts[1] }), 'Only player1 can execute');
        })

        it('decline unstarted game', async () => {
            const { logs: startLogs } = await game.start(10, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            const { logs: declineLogs } = await game.decline(id, { from: accounts[0] });
            expectEvent.inLogs(declineLogs, 'LogDeclined', {
                owner: accounts[0],
                id: new BN('0')
            });

            const balance = await game.balanceOf(accounts[0]);
            balance.should.be.bignumber.equal('1');
        })
    });

    describe('join', () => {
        it('reverts when join non-existing game', async () => {
            await expectRevert(game.join(1, { from: accounts[0] }), 'Game not exist');
        })

        it('reverts when join game owner', async () => {
            const { logs: startLogs } = await game.start(10, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await expectRevert(game.join(id, { from: accounts[0] }), 'You can\'t play with yourself');
        })

        it('revert when value not equal to stake', async () => {
            const { logs: startLogs } = await game.start(10, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await expectRevert(game.join(id, { from: accounts[1] }), 'Stake should be equal');
        })

        it('revert when deadline is reached', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            // new block allows to reach deadline
            await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await expectRevert(game.join(id, { value: 1, from: accounts[1] }), 'Join deadline reached');
        })

        it('join game', async () => {
            const { logs: startLogs } = await game.start(10, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            const { logs: joinLogs } = await game.join(id, { value: 1, from: accounts[1] });
            expectEvent.inLogs(joinLogs, 'LogJoined', {
                player: accounts[1],
                id: new BN('0')
            });
        })
    });

    describe('move1', () => {
        it('reverts when call move1 of non-existing game', async () => {
            await expectRevert(game.move1(1, web3.utils.fromAscii('0'), { from: accounts[0] }), 'Game not exist');
        })

        it('reverts when call move1 non-active game', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await expectRevert(game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] }), 'Game not active');
        })

        it('reverts when call move1 by game non-owner', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            await expectRevert(game.move1(id, web3.utils.fromAscii('0'), { from: accounts[1] }), 'Only player1 can execute');
        })

        it('reverts when call move1 with empty hashed move', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            await expectRevert(game.move1(id, '0x0', { from: accounts[0] }), 'Hashed move cannot be empty');
        })

        it('reverts when call move1 when deadline reached', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            // new block allows to reach deadline
            await game.start(1, { value: 1, from: accounts[0] });

            await expectRevert(game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] }), 'First move deadline reached');
        })

        it('reverts when call move1 twice', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });

            await expectRevert(game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] }), 'Cannot move twice');
        })

        it('move1', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            const hashedMove = '0x1000000000000000000000000000000000000000000000000000000000000000';
            const { logs: move1Logs } = await game.move1(id, hashedMove, { from: accounts[0] });
            expectEvent.inLogs(move1Logs, 'LogFirstMoved', {
                player: accounts[0],
                id: new BN('0'),
                hashedMove
            });
        })
    });

    describe('move2', () => {
        it('reverts when call move2 of non-existing game', async () => {
            await expectRevert(game.move2(1, 0, { from: accounts[0] }), 'Game not exist');
        })

        it('reverts when call move2 non-active game', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await expectRevert(game.move2(id, 0, { from: accounts[0] }), 'Game not active');
        })

        it('reverts when call move2 when move is zero', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });

            await expectRevert(game.move2(id, 0, { from: accounts[1] }), 'Move cannot be empty');
        })

        it('reverts when call move2 by game owner', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            await expectRevert(game.move2(id, 1, { from: accounts[0] }), 'Only player2 can execute');
        })

        it('reverts when call move2 before move1', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            await expectRevert(game.move2(id, 1, { from: accounts[1] }), 'Second move should be after first');
        })

        it('reverts when call move2 twice', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });

            await game.move2(id, 1, { from: accounts[1] });

            await expectRevert(game.move2(id, 1, { from: accounts[1] }), 'Cannot move twice');
        })

        it('reverts when call move2 when deadline reached', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });

            // new block allows to reach deadline
            await game.start(1, { value: 1, from: accounts[0] });

            await expectRevert(game.move2(id, 1, { from: accounts[1] }), 'Second move deadline reached');
        })

        it('move2', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });

            const { logs: move2Logs } = await game.move2(id, 1, { from: accounts[1] });
            expectEvent.inLogs(move2Logs, 'LogSecondMoved', {
                player: accounts[1],
                id: new BN('0'),
                move: new BN('1')
            });
        })
    });

    describe('reveal', () => {
        it('reverts when call reveal of non-existing game', async () => {
            await expectRevert(game.reveal(1, 0, web3.utils.fromAscii('0'), { from: accounts[0] }), 'Game not exist');
        })

        it('reverts when call reveal non-active game', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await expectRevert(game.reveal(id, 0, web3.utils.fromAscii('0'), { from: accounts[0] }), 'Game not active');
        })

        it('reverts when call reveal by game non-owner', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            await expectRevert(game.reveal(id, 1, web3.utils.fromAscii('0'), { from: accounts[1] }), 'Only player1 can execute');
        })

        it('reverts when call reveal before move2', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            await expectRevert(game.reveal(id, 1, web3.utils.fromAscii('0'), { from: accounts[0] }), 'Reveal should be after second move');
        })

        it('reverts when call reveal with reached deadline', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });
            await game.move2(id, 1, { from: accounts[1] });

            // new block allows to reach deadline
            await game.start(1, { value: 1, from: accounts[0] });

            await expectRevert(game.reveal(id, 1, web3.utils.fromAscii('0'), { from: accounts[0] }), 'Reveal deadline reached');
        })

        it('reverts when call reveal with reached deadline', async () => {
            const { logs: startLogs } = await game.start(2, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });
            await game.move2(id, 1, { from: accounts[1] });

            await expectRevert(game.reveal(id, 1, web3.utils.fromAscii('0'), { from: accounts[0] }), 'Move does not match');
        })

        it('reveal move', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            const firstMove = 1;
            const secret = 'super secure pwd';
            const hashedMove = await game.generateMoveHash(id, firstMove, web3.utils.fromAscii(secret));

            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, hashedMove, { from: accounts[0] });
            await game.move2(id, 1, { from: accounts[1] });

            const { logs: revealLogs } = await game.reveal(id, firstMove, web3.utils.fromAscii(secret), { from: accounts[0] });
            expectEvent.inLogs(revealLogs, 'LogRevealed', {
                player: accounts[0],
                id: new BN('0'),
                move: new BN('1')
            });
            expectEvent.inLogs(revealLogs, 'LogOutcome', {
                id: new BN('0'),
                outcome: new BN('3'),
                stake: new BN('2')
            });

            const balance1 = await game.balanceOf(accounts[0]);
            balance1.should.be.bignumber.equal('1');

            const balance2 = await game.balanceOf(accounts[1]);
            balance2.should.be.bignumber.equal('1');
        })
    });

    describe('claim', () => {
        it('reverts when call claim of non-existing game', async () => {
            await expectRevert(game.claim(1, { from: accounts[0] }), 'Game not exist');
        })

        it('reverts when call claim non-active game', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await expectRevert(game.claim(id, { from: accounts[0] }), 'Game not active');
        })

        it('claim when move1 reached deadline, player2 takes a stake', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });

            // new block allows to reach deadline
            await game.start(1, { value: 1, from: accounts[0] });

            const { logs: claimLogs } = await game.claim(id, { from: accounts[0] });
            expectEvent.inLogs(claimLogs, 'LogClaimed', {
                id: new BN('0'),
                outcome: new BN('2'),
                stake: new BN('2')
            });
        })

        it('claim when move2 reached deadline, player1 takes a stake', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });

            // new block allows to reach deadline
            await game.start(1, { value: 1, from: accounts[0] });

            const { logs: claimLogs } = await game.claim(id, { from: accounts[0] });
            expectEvent.inLogs(claimLogs, 'LogClaimed', {
                id: new BN('0'),
                outcome: new BN('1'),
                stake: new BN('2')
            });
        })

        it('claim when reveal reached deadline, player2 takes a stake', async () => {
            const { logs: startLogs } = await game.start(1, { value: 1, from: accounts[0] });

            const { id } = startLogs[0].args;
            await game.join(id, { value: 1, from: accounts[1] });
            await game.move1(id, web3.utils.fromAscii('0'), { from: accounts[0] });
            await game.move2(id, 1, { from: accounts[1] });

            // new block allows to reach deadline
            await game.start(1, { value: 1, from: accounts[0] });

            const { logs: claimLogs } = await game.claim(id, { from: accounts[0] });
            expectEvent.inLogs(claimLogs, 'LogClaimed', {
                id: new BN('0'),
                outcome: new BN('2'),
                stake: new BN('2')
            });
        })
    });
});
