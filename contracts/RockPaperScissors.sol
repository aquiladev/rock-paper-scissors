pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./Pausable.sol";
import "./PullPayment.sol";

contract RockPaperScissors is Pausable, PullPayment {
    using SafeMath for uint256;

    enum Move { None, Rock, Paper, Scissors }
    enum State { Init, WaitForPlayer, Active, Finished }
    enum Outcome { None, Win1, Win2, Draw }

    event LogStarted(address indexed owner, uint256 indexed id, uint256 stake);
    event LogDeclined(address indexed owner, uint256 indexed id);
    event LogJoined(address indexed player, uint256 indexed id);
    event LogFirstMoved(address indexed player, uint256 indexed id, bytes32 hashedMove);
    event LogSecondMoved(address indexed player, uint256 indexed id, uint8 move);
    event LogRevealed(address indexed player, uint256 indexed id, uint8 move);
    event LogOutcome(uint256 indexed id, uint8 outcome, uint256 stake);
    event LogClaimed(uint256 indexed id, uint8 outcome, uint256 stake);

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

    function getGame(uint256 gameId) public view returns(address, address, uint256, uint8, uint8, uint8, uint256, uint256, bytes32) {
        Game storage game = _games[gameId];

        return (game.player1, game.player2, game.stake, uint8(game.state), uint8(game.move1), uint8(game.move2), game.stepDuration, game.nextDeadline, game.hashedMove1);
    }

    function generateMoveHash(uint256 gameId, uint8 move, bytes32 secret) public view exist(gameId) returns(bytes32) {
        return keccak256(abi.encodePacked(address(this), gameId, Move(move), secret));
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

        emit LogStarted(msg.sender, gameId, msg.value);
    }

    function decline(uint256 gameId) public exist(gameId) onlyPlayer1(gameId) {
        Game storage current = _games[gameId];
        require(current.state == State.WaitForPlayer, "Only not statred game can be declined");

        transferTo(msg.sender, current.stake);
        cleanUp(current);

        emit LogDeclined(msg.sender, gameId);
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

        emit LogJoined(msg.sender, gameId);
    }

    function move1(uint256 gameId, bytes32 hashedMove) public exist(gameId) onlyPlayer1(gameId) onlyActive(gameId) {
        require(hashedMove != 0, "Hashed move cannot be empty");

        Game storage current = _games[gameId];

        require(current.hashedMove1 == 0, "Cannot move twice");
        require(block.number <= current.nextDeadline, "First move deadline reached");

        current.hashedMove1 = hashedMove;
        current.nextDeadline = block.number.add(current.stepDuration);

        emit LogFirstMoved(msg.sender, gameId, hashedMove);
    }

    function move2(uint256 gameId, uint8 move) public exist(gameId) onlyActive(gameId) {
        require(move != 0, "Move cannot be empty");

        Game storage current = _games[gameId];

        require(msg.sender == current.player2, "Only player2 can execute");
        require(current.hashedMove1 != 0, "Second move should be after first");
        require(current.move2 == Move.None, "Cannot move twice");
        require(block.number <= current.nextDeadline, "Second move deadline reached");

        current.move2 = Move(move);
        current.nextDeadline = block.number.add(current.stepDuration);

        emit LogSecondMoved(msg.sender, gameId, move);
    }

    function reveal(uint256 gameId, uint8 move, bytes32 secret) public exist(gameId) onlyPlayer1(gameId) onlyActive(gameId) returns (Outcome) {
        Game storage current = _games[gameId];

        require(current.move2 != Move.None, "Reveal should be after second move");
        require(current.move1 == Move.None, "Cannot reveal twice");
        require(block.number <= current.nextDeadline, "Reveal deadline reached");
        require(generateMoveHash(gameId, move, secret) == current.hashedMove1, "Move does not match");

        current.move1 = Move(move);

        emit LogRevealed(msg.sender, gameId, move);

        Outcome outcome = getOutcome(move, uint8(current.move2));
        uint stake = current.stake;
        settle(outcome, current);

        emit LogOutcome(gameId, uint8(outcome), stake);

        return outcome;
    }

    function claim(uint256 gameId) public exist(gameId) onlyActive(gameId) returns (Outcome) {
        Game storage current = _games[gameId];

        Outcome outcome;

        if(current.move1 == Move.None && block.number > current.nextDeadline) {
            outcome = Outcome.Win2;
        }

        if(current.move2 == Move.None && block.number > current.nextDeadline) {
            outcome = Outcome.Win1;
        }

        if(current.hashedMove1 == 0 && block.number > current.nextDeadline) {
            outcome = Outcome.Win2;
        }

        require(outcome != Outcome.None, "Game still active");

        uint stake = current.stake;
        settle(outcome, current);

        emit LogClaimed(gameId, uint8(outcome), stake);

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

    function getOutcome(uint8 move1, uint8 move2) public pure returns(Outcome) {
        Move m1 = Move(move1);
        Move m2 = Move(move2);
        if (m1 == Move.None || m2 == Move.None) return Outcome.None;
        if (m1 == m2) return Outcome.Draw;
        if (m1 == Move.Rock && m2 == Move.Scissors) return Outcome.Win1;
        if (move1 < move2) return Outcome.Win2;
        if (m1 == Move.Scissors && m2 == Move.Rock) return Outcome.Win2;
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