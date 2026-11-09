// Props: the title and the concepts toggle come from App. The component only displays them.
export default function Header({ title, showConcepts, onToggleConcepts }) {
  return (
    <header className="header">
      <h1>{title}</h1>
      <label className="toggle">
        <input type="checkbox" checked={showConcepts} onChange={onToggleConcepts} />
        Show React concepts
      </label>
    </header>
  );
}
