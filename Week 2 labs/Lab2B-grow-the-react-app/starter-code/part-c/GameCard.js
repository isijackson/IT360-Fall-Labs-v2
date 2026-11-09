function GameCard({ game, onToggle }) {
  return (
    <li className={game.cancelled ? 'game cancelled' : 'game'}>
      <strong>{game.home} vs {game.away}</strong>
      <span>{game.date} at {game.time}, {game.field}</span>
      <button onClick={() => onToggle(game.id)}>
        {game.cancelled ? 'Reinstate' : 'Cancel'}
      </button>
    </li>
  );
}

export default GameCard;
