import { render, screen } from '@testing-library/react';
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
