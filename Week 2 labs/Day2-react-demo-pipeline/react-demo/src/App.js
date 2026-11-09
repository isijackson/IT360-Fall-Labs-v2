// App owns the data (the games and the filters) and passes it down to the components as props.
import { useEffect, useMemo, useState } from 'react';
import './App.css';
import { ConceptContext } from './ConceptContext';
import useLocalStorage from './hooks/useLocalStorage';
import Header from './components/Header';
import NextGame from './components/NextGame';
import FilterBar from './components/FilterBar';
import GameList from './components/GameList';
import AddGameForm from './components/AddGameForm';
import ConceptTag from './components/ConceptTag';

const FIELDS = ['Field 1', 'Field 2', 'Field 3'];
const BUILD = process.env.REACT_APP_BUILD_SHA ? process.env.REACT_APP_BUILD_SHA.slice(0, 7) : 'local build';
const BUILT_AT = process.env.REACT_APP_BUILD_TIME || 'not set';

function App() {
  const [games, setGames] = useLocalStorage('wasatch-games', null);
  const [status, setStatus] = useState(games ? 'ready' : 'loading');
  const [field, setField] = useState('All fields');
  const [search, setSearch] = useState('');
  const [showConcepts, setShowConcepts] = useState(true);

  // Fetch the starting schedule from public/schedule.json the first time (or after a reset).
  useEffect(() => {
    if (games) return;
    setStatus('loading');
    fetch(`${process.env.PUBLIC_URL}/schedule.json`)
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json();
      })
      .then((data) => {
        setGames(data);
        setStatus('ready');
      })
      .catch(() => setStatus('error'));
  }, [games, setGames]);

  // Derived data: recomputed only when the games or the filters change.
  const visible = useMemo(() => {
    const term = search.trim().toLowerCase();
    return (games || [])
      .filter((g) => field === 'All fields' || g.field === field)
      .filter((g) => !term || `${g.home} ${g.away}`.toLowerCase().includes(term))
      .sort((a, b) => `${a.date}${a.time}`.localeCompare(`${b.date}${b.time}`));
  }, [games, field, search]);

  const addGame = (g) => setGames([...games, { ...g, id: Date.now(), cancelled: false }]);
  const toggleGame = (id) => setGames(games.map((g) => (g.id === id ? { ...g, cancelled: !g.cancelled } : g)));
  const removeGame = (id) => setGames(games.filter((g) => g.id !== id));

  return (
    <ConceptContext.Provider value={showConcepts}>
      <div className="App">
        <Header
          title="Wasatch Front Fall Sports Schedule"
          showConcepts={showConcepts}
          onToggleConcepts={() => setShowConcepts(!showConcepts)}
        />
        {status === 'loading' && <p role="status">Loading schedule…</p>}
        {status === 'error' && <p role="alert" className="error">Could not load schedule.json.</p>}
        {status === 'ready' && (
          <main>
            <NextGame games={games} />
            <FilterBar fields={FIELDS} field={field} search={search} count={visible.length}
              onFieldChange={setField} onSearchChange={setSearch} />
            <GameList games={visible} onToggle={toggleGame} onRemove={removeGame} />
            <AddGameForm fields={FIELDS} onAdd={addGame} />
            <p>
              <button onClick={() => setGames(null)}>Reset to the published schedule</button>{' '}
              <ConceptTag>custom hook: useLocalStorage</ConceptTag> <ConceptTag>fetch in useEffect</ConceptTag>
            </p>
          </main>
        )}
        <footer className="footer">
          Build <code>{BUILD}</code>, built {BUILT_AT} <ConceptTag>environment variables at build time</ConceptTag>
        </footer>
      </div>
    </ConceptContext.Provider>
  );
}

export default App;
