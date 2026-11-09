import './App.css';

const BUILD = (process.env.REACT_APP_BUILD_SHA || 'local').slice(0, 7);

function App() {
  return (
    <div className="App">
      <h1>Hello from React deployed with Azure CI/CD!</h1>
      <footer className="build">Build {BUILD}</footer>
    </div>
  );
}

export default App;
