import { render, screen, fireEvent, within } from '@testing-library/react';
import App from './App';

const schedule = [
  { id: 1, date: '2026-11-14', time: '09:00', field: 'Field 1', home: 'Canyon Hawks', away: 'Mesa Rockets', cancelled: false },
  { id: 2, date: '2026-11-14', time: '10:30', field: 'Field 2', home: 'Red Rock United', away: 'Flat Iron FC', cancelled: false },
];

// The schedule list (the "Next kickoff" panel repeats one matchup, so queries look inside the list).
const scheduleList = () => screen.findByRole('list');

beforeEach(() => {
  window.localStorage.clear();
  global.fetch = jest.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve(schedule) }));
});

test('loads the schedule from schedule.json and shows the heading', async () => {
  render(<App />);
  expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Wasatch Front Fall Sports Schedule');
  const list = await scheduleList();
  expect(within(list).getByText('Canyon Hawks vs Mesa Rockets')).toBeInTheDocument();
  expect(screen.getByText('2 games shown')).toBeInTheDocument();
});

test('filters the schedule by field', async () => {
  render(<App />);
  await scheduleList();
  fireEvent.change(screen.getByLabelText('Filter by field'), { target: { value: 'Field 2' } });
  expect(screen.getByText('1 game shown')).toBeInTheDocument();
  expect(within(screen.getByRole('list')).queryByText('Canyon Hawks vs Mesa Rockets')).not.toBeInTheDocument();
});

test('cancels a game and shows the badge', async () => {
  render(<App />);
  const card = within(await scheduleList()).getByText('Canyon Hawks vs Mesa Rockets').closest('li');
  fireEvent.click(within(card).getByText('Cancel'));
  expect(within(card).getByText('Cancelled')).toBeInTheDocument();
});

test('adds a game through the form and rejects a team playing itself', async () => {
  render(<App />);
  await scheduleList();
  fireEvent.change(screen.getByLabelText('Date'), { target: { value: '2026-12-12' } });
  fireEvent.change(screen.getByLabelText('Time'), { target: { value: '11:00' } });
  fireEvent.change(screen.getByLabelText('Home team'), { target: { value: 'Owls' } });
  fireEvent.change(screen.getByLabelText('Away team'), { target: { value: 'Owls' } });
  fireEvent.click(screen.getByText('Add game'));
  expect(screen.getByRole('alert')).toHaveTextContent('A team cannot play itself.');
  fireEvent.change(screen.getByLabelText('Away team'), { target: { value: 'Foxes' } });
  fireEvent.click(screen.getByText('Add game'));
  expect(within(screen.getByRole('list')).getByText('Owls vs Foxes')).toBeInTheDocument();
  expect(screen.getByText('3 games shown')).toBeInTheDocument();
});
