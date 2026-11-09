// useEffect with cleanup: a timer ticks every second to update the countdown, and is stopped when the component goes away.
import { useEffect, useState } from 'react';
import ConceptTag from './ConceptTag';

function countdown(ms) {
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  return `${d}d ${h}h ${m}m ${s % 60}s`;
}

export default function NextGame({ games }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  const next = games
    .filter((g) => !g.cancelled && new Date(`${g.date}T${g.time}`).getTime() > now)
    .sort((a, b) => `${a.date}${a.time}`.localeCompare(`${b.date}${b.time}`))[0];
  return (
    <section className="panel next">
      <h2>Next kickoff <ConceptTag>useEffect + timer</ConceptTag></h2>
      {next ? (
        <p>
          <strong>{next.home} vs {next.away}</strong>, {next.field}, in{' '}
          <span className="countdown">{countdown(new Date(`${next.date}T${next.time}`).getTime() - now)}</span>
        </p>
      ) : (
        <p>No upcoming games.</p>
      )}
    </section>
  );
}
