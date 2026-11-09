function GameCard({ game }) {
  return (
    <li className="game">
      <strong>{game.home} vs {game.away}</strong>
      <span>{game.date} at {game.time}, {game.field}</span>
    </li>
  );
}

export default GameCard;
