// A form with its own state and validation; on submit it lifts the new game up to App through the onAdd prop.
import { useState } from 'react';
import ConceptTag from './ConceptTag';

const empty = { date: '', time: '', field: 'Field 1', home: '', away: '' };

export default function AddGameForm({ fields, onAdd }) {
  const [form, setForm] = useState(empty);
  const [error, setError] = useState('');
  const update = (e) => setForm({ ...form, [e.target.name]: e.target.value });
  const submit = (e) => {
    e.preventDefault();
    if (!form.date || !form.time || !form.home || !form.away) return setError('Fill in every field.');
    if (form.home === form.away) return setError('A team cannot play itself.');
    onAdd(form);
    setForm(empty);
    setError('');
  };
  return (
    <section className="panel">
      <h2>Add a game <ConceptTag>useState + forms</ConceptTag></h2>
      <form onSubmit={submit} className="add">
        <input name="date" type="date" aria-label="Date" value={form.date} onChange={update} />
        <input name="time" type="time" aria-label="Time" value={form.time} onChange={update} />
        <select name="field" aria-label="Field" value={form.field} onChange={update}>
          {fields.map((f) => <option key={f}>{f}</option>)}
        </select>
        <input name="home" placeholder="Home team" aria-label="Home team" value={form.home} onChange={update} />
        <input name="away" placeholder="Away team" aria-label="Away team" value={form.away} onChange={update} />
        <button type="submit">Add game</button>
      </form>
      {error && <p role="alert" className="error">{error}</p>}
    </section>
  );
}
