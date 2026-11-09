// Conditional rendering and events: the badge appears only for cancelled games; the buttons call functions passed down from App.
import ConceptTag from './ConceptTag';

export default function GameCard({ game, onToggle, onRemove }) {
  return (
    <li className={game.cancelled ? 'card cancelled' : 'card'}>
      <div className="when">{game.date} {game.time}</div>
      <div className="teams">{game.home} vs {game.away}</div>
      <div className="where">{game.field}</div>
      {game.cancelled && <span className="badge">Cancelled</span>}
      <div className="actions">
        <button onClick={() => onToggle(game.id)}>{game.cancelled ? 'Reinstate' : 'Cancel'}</button>
        <button onClick={() => onRemove(game.id)} aria-label={`Remove ${game.home} vs ${game.away}`}>Remove</button>
        <ConceptTag>events</ConceptTag>
      </div>
    </li>
  );
}
