import { render, screen, fireEvent } from '@testing-library/react';
import App from './App';

const sample = [
  { id: 1, date: '2026-11-14', time: '09:00', field: 'Field 1', home: 'Canyon Hawks', away: 'Mesa Rockets', cancelled: false },
  { id: 2, date: '2026-11-14', time: '10:30', field: 'Field 2', home: 'Red Rock United', away: 'Flat Iron FC', cancelled: false },
];

beforeEach(() => {
  global.fetch = jest.fn(() => Promise.resolve({ json: () => Promise.resolve(sample) }));
});

test('renders the Azure CI/CD heading', async () => {
  render(<App />);
  expect(screen.getByText(/hello from react deployed with azure ci\/cd/i)).toBeInTheDocument();
  await screen.findByText('Canyon Hawks vs Mesa Rockets');
});

test('shows one card per game in schedule.json', async () => {
  render(<App />);
  expect(await screen.findByText('Canyon Hawks vs Mesa Rockets')).toBeInTheDocument();
  expect(screen.getAllByRole('listitem')).toHaveLength(2);
});

test('shows the build stamp', async () => {
  render(<App />);
  expect(screen.getByText(/build local/i)).toBeInTheDocument();
  await screen.findByText('Canyon Hawks vs Mesa Rockets');
});

test('filters the list by field', async () => {
  render(<App />);
  await screen.findByText('Canyon Hawks vs Mesa Rockets');
  fireEvent.change(screen.getByRole('combobox'), { target: { value: 'Field 2' } });
  expect(screen.getByText('1 game shown')).toBeInTheDocument();
  expect(screen.queryByText('Canyon Hawks vs Mesa Rockets')).not.toBeInTheDocument();
});

test('cancels a game and can reinstate it', async () => {
  render(<App />);
  await screen.findByText('Canyon Hawks vs Mesa Rockets');
  fireEvent.click(screen.getAllByText('Cancel')[0]);
  expect(screen.getByText('Reinstate')).toBeInTheDocument();
  fireEvent.click(screen.getByText('Reinstate'));
  expect(screen.getAllByText('Cancel')).toHaveLength(2);
});
