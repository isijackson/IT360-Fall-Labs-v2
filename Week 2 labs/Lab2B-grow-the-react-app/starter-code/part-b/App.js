import { useEffect, useState } from 'react';
import './App.css';
import GameCard from './GameCard';

const BUILD = (process.env.REACT_APP_BUILD_SHA || 'local').slice(0, 7);

function App() {
  const [games, setGames] = useState([]);
  const [status, setStatus] = useState('loading');

  useEffect(() => {
    fetch('/schedule.json')
      .then((response) => response.json())
      .then((data) => {
        setGames(data);
        setStatus('ready');
      })
      .catch(() => setStatus('error'));
  }, []);

  return (
    <div className="App">
      <h1>Hello from React deployed with Azure CI/CD!</h1>
      {status === 'loading' && <p>Loading the schedule...</p>}
      {status === 'error' && <p>Could not load the schedule.</p>}
      <ul className="games">
        {games.map((game) => (
          <GameCard key={game.id} game={game} />
        ))}
      </ul>
      <footer className="build">Build {BUILD}</footer>
    </div>
  );
}

export default App;
