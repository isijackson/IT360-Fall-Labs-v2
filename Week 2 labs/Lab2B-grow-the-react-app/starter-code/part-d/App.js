import { useEffect, useState } from 'react';
import './App.css';
import GameCard from './GameCard';

const BUILD = (process.env.REACT_APP_BUILD_SHA || 'local').slice(0, 7);

function App() {
  const [games, setGames] = useState([]);
  const [status, setStatus] = useState('loading');
  const [field, setField] = useState('All fields');

  useEffect(() => {
    fetch('/schedule.json')
      .then((response) => response.json())
      .then((data) => {
        setGames(data);
        setStatus('ready');
      })
      .catch(() => setStatus('error'));
  }, []);

  const toggleGame = (id) =>
    setGames(games.map((g) => (g.id === id ? { ...g, cancelled: !g.cancelled } : g)));

  const visible = games.filter((g) => field === 'All fields' || g.field === field);

  return (
    <div className="App">
      <h1>Wasatch Front Fall Sports Schedule</h1>
      {status === 'loading' && <p>Loading the schedule...</p>}
      {status === 'error' && <p>Could not load the schedule.</p>}
      <label>
        Field{' '}
        <select value={field} onChange={(e) => setField(e.target.value)}>
          <option>All fields</option>
          <option>Field 1</option>
          <option>Field 2</option>
          <option>Field 3</option>
        </select>
      </label>
      <p>{visible.length} {visible.length === 1 ? 'game' : 'games'} shown</p>
      <ul className="games">
        {visible.map((game) => (
          <GameCard key={game.id} game={game} onToggle={toggleGame} />
        ))}
      </ul>
      <footer className="build">Build {BUILD}</footer>
    </div>
  );
}

export default App;
