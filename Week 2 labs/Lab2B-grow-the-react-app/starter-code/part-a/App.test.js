import { render, screen } from '@testing-library/react';
import App from './App';

test('renders the Azure CI/CD heading', () => {
  render(<App />);
  const heading = screen.getByText(/hello from react deployed with azure ci\/cd/i);
  expect(heading).toBeInTheDocument();
});

test('shows the build stamp', () => {
  render(<App />);
  expect(screen.getByText(/build local/i)).toBeInTheDocument();
});
