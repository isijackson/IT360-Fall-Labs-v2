// Rendering a list: map() turns the array into cards; each card needs a stable key so React can update it efficiently.
import GameCard from './GameCard';
import ConceptTag from './ConceptTag';

export default function GameList({ games, onToggle, onRemove }) {
  return (
    <section className="panel">
      <h2>Schedule <ConceptTag>lists and keys</ConceptTag></h2>
      {games.length === 0 ? (
        <p>No games match the filter.</p>
      ) : (
        <ul className="games">
          {games.map((g) => <GameCard key={g.id} game={g} onToggle={onToggle} onRemove={onRemove} />)}
        </ul>
      )}
    </section>
  );
}
