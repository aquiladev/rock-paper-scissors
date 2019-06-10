pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./Pausable.sol";
import "./PullPayment.sol";

contract RockPaperScissors is Pausable, PullPayment {
    using SafeMath for uint256;

    enum Move { None, Rock, Paper, Scissors }
    enum State { Init, WaitForPlayer, Active, Finished }
    enum Outcome { None, Win1, Win2, Draw }

    event LogStarted(uint256 indexed id, address indexed player1, uint256 stake);
    event LogDeclined(uint256 indexed id, address indexed player1);
    event LogJoined(uint256 indexed id, address indexed player2);
    event LogFirstMoved(uint256 indexed id, address indexed player1, bytes32 hashedMove);
    event LogSecondMoved(uint256 indexed id, address indexed player2, Move move);
    event LogRevealed(uint256 indexed id, address indexed player1, Move move);
    event LogOutcome(uint256 indexed id, Outcome outcome, uint256 stake);
    event LogClaimed(uint256 indexed id, Outcome outcome, uint256 stake);

    struct Game {
        address player1;
        State state;
        address player2;
        Move move2;
        Move move1;
        uint256 stake;
        uint256 stepDuration;
        uint256 nextDeadline;
        bytes32 hashedMove1;
    }

    uint256 private _gameIndex;
    mapping (uint256 => Game) private _games;

    modifier exist(uint256 gameId) {
        require(_games[gameId].player1 != address(0), "Game not exist");
        _;
    }

    modifier onlyPlayer1(uint256 gameId) {
        require(msg.sender == _games[gameId].player1, "Only player1 can execute");
        _;
    }

    modifier onlyActive(uint256 gameId) {
        require(_games[gameId].state == State.Active, "Game not active");
        _;
    }

    constructor (bool paused) public Pausable(paused) {
    }

    function getGame(uint256 gameId) public view returns(
        address player1,
        address player2,
        uint256 stake,
        State state,
        Move move1,
        Move move2,
        uint256 stepDuration,
        uint256 nextDeadline,
        bytes32 hashedMove1) {
        Game storage game = _games[gameId];

        player1 = game.player1;
        player2 = game.player2;
        stake = game.stake;
        state = game.state;
        move1 = game.move1;
        move2 = game.move2;
        stepDuration = game.stepDuration;
        nextDeadline = game.nextDeadline;
        hashedMove1 = game.hashedMove1;
    }

    function generateMoveHash(uint256 gameId, Move move, bytes32 secret) public view exist(gameId) returns(bytes32) {
        require(move != Move.None, "Move cannot be empty");
        return keccak256(abi.encodePacked(address(this), gameId, move, secret));
    }

    function start(uint256 maxStepDuration) public payable returns(uint256 gameId) {
        require(maxStepDuration > 0, "Step duration cannot be zero");

        Game storage current = _games[_gameIndex];
        current.player1 = msg.sender;
        current.state = State.WaitForPlayer;
        current.stake = msg.value;
        current.stepDuration = maxStepDuration;
        current.nextDeadline = block.number.add(maxStepDuration);

        gameId = _gameIndex;
        _gameIndex += 1;

        emit LogStarted(gameId, msg.sender, msg.value);
    }

    function decline(uint256 gameId) public exist(gameId) onlyPlayer1(gameId) {
        Game storage current = _games[gameId];
        require(current.state == State.WaitForPlayer, "Only not statred game can be declined");

        transferTo(msg.sender, current.stake);
        cleanUp(current);

        emit LogDeclined(gameId, msg.sender);
    }

    function join(uint256 gameId) public payable exist(gameId) {
        Game storage current = _games[gameId];

        require(msg.sender != current.player1, "You can't play with yourself");
        require(msg.value == current.stake, "Stake should be equal");
        require(current.state == State.WaitForPlayer, "Not possible to join the game");
        require(block.number <= current.nextDeadline, "Join deadline reached");

        current.player2 = msg.sender;
        current.state = State.Active;
        current.stake = current.stake.add(msg.value);
        current.nextDeadline = block.number.add(current.stepDuration);

        emit LogJoined(gameId, msg.sender);
    }

    function move1(uint256 gameId, bytes32 hashedMove) public exist(gameId) onlyPlayer1(gameId) onlyActive(gameId) {
        require(hashedMove != 0, "Hashed move cannot be empty");

        Game storage current = _games[gameId];

        require(current.hashedMove1 == 0, "Cannot move twice");
        require(block.number <= current.nextDeadline, "First move deadline reached");

        current.hashedMove1 = hashedMove;
        current.nextDeadline = block.number.add(current.stepDuration);

        emit LogFirstMoved(gameId, msg.sender, hashedMove);
    }

    function move2(uint256 gameId, Move move) public exist(gameId) onlyActive(gameId) {
        require(move != Move.None, "Move cannot be empty");

        Game storage current = _games[gameId];

        require(msg.sender == current.player2, "Only player2 can execute");
        require(current.hashedMove1 != 0, "Second move should be after first");
        require(current.move2 == Move.None, "Cannot move twice");
        require(block.number <= current.nextDeadline, "Second move deadline reached");

        current.move2 = move;
        current.nextDeadline = block.number.add(current.stepDuration);

        emit LogSecondMoved(gameId, msg.sender, move);
    }

    function reveal(uint256 gameId, Move move, bytes32 secret) public exist(gameId) onlyPlayer1(gameId) onlyActive(gameId) returns (Outcome) {
        Game storage current = _games[gameId];

        require(current.move2 != Move.None, "Reveal should be after second move");
        require(current.move1 == Move.None, "Cannot reveal twice");
        require(block.number <= current.nextDeadline, "Reveal deadline reached");
        require(generateMoveHash(gameId, move, secret) == current.hashedMove1, "Move does not match");

        current.move1 = move;

        emit LogRevealed(gameId, msg.sender, move);

        Outcome outcome = getOutcome(move, current.move2);
        uint stake = current.stake;
        settle(outcome, current);

        emit LogOutcome(gameId, outcome, stake);

        return outcome;
    }

    function claim(uint256 gameId) public exist(gameId) onlyActive(gameId) returns (Outcome) {
        Game storage current = _games[gameId];

        require(block.number > current.nextDeadline, "Game still active");

        Outcome outcome;

        if(current.move1 == Move.None) {
            outcome = Outcome.Win2;
        }

        if(current.move2 == Move.None) {
            outcome = Outcome.Win1;
        }

        if(current.hashedMove1 == 0) {
            outcome = Outcome.Win2;
        }

        require(outcome != Outcome.None, "Game still active");

        uint stake = current.stake;
        settle(outcome, current);

        emit LogClaimed(gameId, outcome, stake);

        return outcome;
    }

    function cleanUp(Game storage game) private {
        game.player1 = address(0);
        game.player2 = address(0);
        game.stake = 0;
        game.state = State.Finished;
        game.stepDuration = 0;
        game.nextDeadline = 0;
        game.move2 = Move.None;
        game.move1 = Move.None;
        game.hashedMove1 = 0;
    }

    function getOutcome(Move move1, Move move2) public pure returns(Outcome) {
        if (move1 == Move.None || move2 == Move.None) return Outcome.None;
        if (move1 == move2) return Outcome.Draw;
        if (move1 == Move.Rock && move2 == Move.Scissors) return Outcome.Win1;
        if (move1 < move2) return Outcome.Win2;
        if (move1 == Move.Scissors && move2 == Move.Rock) return Outcome.Win2;
        return Outcome.Win1;
    }

    function settle(Outcome outcome, Game storage game) private {
        uint stake = game.stake;
        address player1 = game.player1;
        address player2 = game.player2;

        cleanUp(game);

        if (stake > 0) {
            if (outcome == Outcome.Draw) {
                uint256 half = stake.div(2);
                transferTo(player1, half);
                transferTo(player2, half);
            } else if (outcome == Outcome.Win1) {
                transferTo(player1, stake);
            } else if (outcome == Outcome.Win2) {
                transferTo(player2, stake);
            } else {
                revert("Something went wrong");
            }
        }
    }
}