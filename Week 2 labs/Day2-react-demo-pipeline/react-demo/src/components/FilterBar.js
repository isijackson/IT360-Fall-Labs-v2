// Controlled inputs: what the inputs show always comes from state in App, and every keystroke updates that state.
import ConceptTag from './ConceptTag';

export default function FilterBar({ fields, field, search, count, onFieldChange, onSearchChange }) {
  return (
    <section className="panel filters">
      <h2>Find a game <ConceptTag>controlled inputs</ConceptTag></h2>
      <label>
        Field{' '}
        <select aria-label="Filter by field" value={field} onChange={(e) => onFieldChange(e.target.value)}>
          <option>All fields</option>
          {fields.map((f) => <option key={f}>{f}</option>)}
        </select>
      </label>
      <label>
        Team{' '}
        <input aria-label="Filter by team" placeholder="Type a team name" value={search} onChange={(e) => onSearchChange(e.target.value)} />
      </label>
      <span className="count">{count} game{count === 1 ? '' : 's'} shown</span>
    </section>
  );
}
